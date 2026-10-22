#!/bin/bash

set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

python3 - "$ROOT" <<'PY'
import os
import pathlib
import subprocess
import sys
import tempfile

repo = pathlib.Path(sys.argv[1])

def replace_fixture(text, old, new, count=None):
  found = text.count(old)
  assert found > 0 and (count is None or found == count), f"fixture target changed: {old!r} ({found} matches)"
  return text.replace(old, new)

with tempfile.TemporaryDirectory(prefix="monarch-sudo-test-") as directory:
  root = pathlib.Path(directory)
  tools = root / "tools"
  tools.mkdir()
  sudoers = root / "etc/sudoers.d"
  sudoers.mkdir(parents=True)
  lock = root / "run/lock"
  lock.mkdir(parents=True)
  log = root / "calls"
  helper = root / "helper"
  cli = root / "cli"
  source = repo / "bin/monarch-sudo-passwordless-root"
  assert source.exists(), "missing packaged root boundary for temporary grants"
  text = source.read_text()
  for old, new in (("/etc/sudoers.d", str(sudoers)), ("/run/lock", str(lock)),
      ("/usr/bin/monarch-sudo-passwordless-root", str(helper)),
      ("/usr/bin/", str(tools) + "/"), ("/usr/sbin/visudo", str(tools / "visudo")),
      ("EUID", "FIXTURE_EUID"), ('[[ $path == / ]]', '[[ $path == "' + str(root) + '" ]]')):
    text = replace_fixture(text, old, new)
  lines = text.splitlines()
  lines.insert(1, "readonly FIXTURE_EUID=0")
  helper.write_text("\n".join(lines) + "\n")
  helper.chmod(0o755)
  cli_text = replace_fixture((repo / "bin/monarch-sudo-passwordless").read_text(),
    "/usr/bin/monarch-sudo-passwordless-root", str(helper), count=1)
  cli.write_text(replace_fixture(cli_text, "/usr/bin/id", str(tools / "id"), count=1))
  cli.chmod(0o755)
  mock = tools / "mock"
  mock.write_text(r'''#!/bin/bash
name=${0##*/}
{
  printf '%s' "$name"
  printf ' %q' "$@"
  printf '\n'
} >>"$LOG"
case $name in
  getent) printf '%s\n' "${ACCOUNT:-alice:x:1000:1000::/home/alice:/bin/bash}" ;;
  id) printf '1000\n' ;;
  stat)
    if [[ $* == *'%u'* ]]; then
      printf '0\n'
    else
      exec /usr/bin/stat "$@"
    fi
    ;;
  chown) : ;;
  date)
    if [[ $* == '+%s' ]]; then
      printf '%s\n' "${NOW:-1800000000}"
    else
      exec /usr/bin/date "$@"
    fi
    ;;
  systemd-run | systemctl | visudo | gum)
    if [[ $name == 'systemd-run' ]]; then
      [[ -z ${EXPECT_ABSENT:-} || ! -e $RULE ]] || exit 99
      [[ ${KILL:-} != 'before-publish' ]] || kill -KILL "$PPID"
    fi
    [[ ${FAIL:-} != "$name" ]]
    ;;
  sudo)
    [[ ${1:-} != '--' ]] || shift
    exec /usr/bin/env SUDO_UID=1000 "$@"
    ;;
  *)
    [[ ${FAIL:-} != "$name" ]] || exit 1
    if [[ $name == 'mv' && ${KILL:-} == 'after-publish' ]]; then
      /usr/bin/mv "$@" || exit 1
      kill -KILL "$PPID"
      exit 0
    fi
    exec "/usr/bin/$name" "$@"
    ;;
esac
''')
  mock.chmod(0o755)
  commands = ("getent", "id", "stat", "chown", "date", "systemd-run", "systemctl",
    "visudo", "gum", "sudo", "realpath", "flock", "chmod", "mktemp", "mv", "rm", "cat", "tr")
  for command in commands:
    (tools / command).symlink_to(mock)
  rule = sudoers / "99-monarch-nopasswd-1000"
  legacy_rule = sudoers / "99-monarch-nopasswd-alice"
  env = dict(os.environ, PATH=str(tools) + ":/usr/bin", LOG=str(log), RULE=str(rule),
    SUDO_UID="1000", USER="attacker", NOW="1800000000")

  def run(*args, success=True, changes=None, client=False):
    result = subprocess.run([str(cli if client else helper), *args], env=env | (changes or {}),
      text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if success:
      assert result.returncode == 0, (args, result.returncode, result.stdout, result.stderr)
    else:
      assert result.returncode != 0, ("unexpected success", args)
    return result

  run("enable", "1000", "15", changes={"EXPECT_ABSENT": "1"})
  assert rule.read_text().splitlines()[1] == "alice ALL=(ALL) NOTAFTER=20270115081500Z NOPASSWD: ALL"
  assert rule.stat().st_mode & 0o777 == 0o440
  calls = log.read_text()
  assert "--on-calendar=@1800000900" in calls and "--on-active" not in calls
  assert calls.index("visudo ") < calls.index("systemd-run ") < calls.index("mv ")
  assert not list(sudoers.glob(".monarch-nopasswd.*"))
  print("PASS validated UTC deadline, absolute timer and atomic publication")

  old = rule.read_text()
  for minutes in ("0", "-1", "1441", "1m", "permanent", "999999999999999999999", "1\\n2", ""):
    run("enable", "1000", minutes, success=False)
    assert rule.read_text() == old
  for uid in ("0", "-1", "1001", "1000/../x", "99999999999999999"):
    run("enable", uid, "15", success=False)
    assert rule.read_text() == old
  for account in ("root:x:0:0::/root:/bin/bash", "ALL:x:1000:1000::/:/bin/bash",
      "../alice:x:1000:1000::/:/bin/bash", "alice:x:1001:1001::/:/bin/bash"):
    run("enable", "1000", "15", success=False, changes={"ACCOUNT": account})
    assert rule.read_text() == old
  run("enable", "1000", "15", success=False, changes={"SUDO_UID": "1001"})
  run("enable", "1000", "15", success=False, changes={"SUDO_UID": ""})
  for arguments in (("enable", "1000"), ("status", "1000", "extra"),
      ("expire", "1000", "../../x", "20270115081500Z"),
      ("expire", "1000", "f" * 32, "20271399081500Z")):
    run(*arguments, success=False)
  nonroot = root / "nonroot"
  nonroot.write_text(replace_fixture(helper.read_text(),
    "readonly FIXTURE_EUID=0", "readonly FIXTURE_EUID=1000", count=1))
  nonroot.chmod(0o755)
  assert subprocess.run([str(nonroot), "enable", "1000", "15"], env=env,
    stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode != 0
  assert subprocess.run(["/bin/bash", str(helper), "enable", "1000", "15"], env=env,
    stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode == 126
  assert rule.read_text() == old
  print("PASS root revalidates durations and caller identity independent of USER")

  old_token = old.splitlines()[0].split("=", 1)[1]
  run("enable", "1000", "30")
  renewed = rule.read_text()
  run("expire", "1000", old_token, "20270115081500Z", changes={"NOW": "1800000901"})
  assert rule.read_text() == renewed
  run("expire", "1000", old_token, "20270115081500Z", changes={"NOW": "1800001801"})
  assert rule.read_text() == renewed
  token = renewed.splitlines()[0].split("=", 1)[1]
  run("expire", "1000", token, "20270115083000Z", changes={"NOW": "1800001799"})
  assert rule.read_text() == renewed
  run("expire", "1000", token, "20270115083000Z", changes={"NOW": "1800001801"})
  assert not rule.exists()
  run("enable", "1000", "15")
  first_token = rule.read_text().splitlines()[0].split("=", 1)[1]
  run("enable", "1000", "15")
  same_deadline = rule.read_text()
  run("expire", "1000", first_token, "20270115081500Z", changes={"NOW": "1800000901"})
  assert rule.read_text() == same_deadline
  run("disable", "1000")
  print("PASS stale or early expiry callbacks never delete a renewed grant")

  for failure in ("visudo", "systemd-run", "systemctl", "mv"):
    run("enable", "1000", "15", success=False, changes={"FAIL": failure})
    assert not rule.exists() and not list(sudoers.glob(".monarch-nopasswd.*"))
  run("enable", "1000", "15")
  previous = rule.read_text()
  run("enable", "1000", "30", success=False, changes={"FAIL": "systemd-run"})
  assert rule.read_text() == previous
  run("status", "1000", success=False, changes={"NOW": "1800000901"})
  assert not rule.exists()
  print("PASS failures publish no grant or extension; status retires expired rules")

  run("enable", "1000", "15", success=False, changes={"KILL": "before-publish"})
  assert not rule.exists()
  for stage in sudoers.glob(".monarch-nopasswd.*"):
    stage.unlink()
  run("enable", "1000", "15", success=False, changes={"KILL": "after-publish"})
  assert "NOTAFTER=20270115081500Z" in rule.read_text()
  run("status", "1000", success=False, changes={"NOW": "1800000901"})
  assert not rule.exists()
  print("PASS abrupt termination cannot publish an unbounded grant")

  external = root / "unrelated"
  external.write_text("keep me")
  rule.symlink_to(external)
  run("enable", "1000", "15", success=False)
  assert external.read_text() == "keep me"
  rule.unlink()
  rule.write_text("administrator policy\n")
  run("enable", "1000", "15", success=False)
  assert rule.read_text() == "administrator policy\n"
  rule.unlink()
  print("PASS unrecognized policy and symlink targets remain untouched")

  legacy_rule.write_text("alice ALL=(ALL) NOPASSWD: ALL\n")
  run("status", "1000", success=False)
  assert not legacy_rule.exists() and not rule.exists()
  run("enable", "1000", "15")
  legacy_rule.unlink(missing_ok=True)
  assert rule.exists(), "legacy timer rm callback can delete the replacement grant"
  run("disable", "1000")
  print("PASS exact legacy unbounded grants are retired")

  startup = root / "startup"
  marker = root / "startup-was-executed"
  startup.write_text("touch '" + str(marker) + "'\n")
  run("status", "1000", success=False, changes={"BASH_ENV": str(startup),
    "MONARCH_PATH": str(root / "untrusted"), "USER": "root"})
  assert not marker.exists()
  print("PASS privileged Bash startup ignores caller startup code")

  legacy_rule.write_text("alice ALL=(ALL) NOPASSWD: ALL\n")
  other_legacy = sudoers / "99-monarch-nopasswd-bob"
  other_legacy.write_text("bob ALL=(ALL) NOPASSWD: ALL\n")
  custom = sudoers / "99-monarch-nopasswd-admin"
  custom.write_text("administrator policy\n")
  run("enable", "1000", "15")
  current = rule.read_text()
  run("revoke-legacy", changes={"SUDO_UID": ""})
  run("revoke-legacy", changes={"SUDO_UID": ""})
  assert not other_legacy.exists() and not legacy_rule.exists()
  assert custom.read_text() == "administrator policy\n" and rule.read_text() == current
  custom.unlink()
  run("disable", "1000")
  print("PASS root upgrade cleanup retires all exact legacy rules idempotently")

  run(client=True)
  assert rule.exists()
  run(client=True)
  assert not rule.exists()
  run("15", client=True, changes={"FAIL": "gum"})
  assert not rule.exists()
  run("0001", client=True)
  assert "NOTAFTER=20270115080100Z" in rule.read_text()
  run("30", client=True)
  assert "NOTAFTER=20270115083000Z" in rule.read_text()
  run("permanent", client=True, success=False)
  run("", client=True, success=False)
  run("15", "extra", client=True, success=False)
  run(client=True)
  assert not rule.exists()
  print("PASS CLI opt-in, leading zeros, renewal, toggle and argument validation")

  cleanup = (repo / "default/tmpfiles.d/monarch-nopasswd-sudo.conf").read_text()
  assert "r! /etc/sudoers.d/99-monarch-nopasswd-*" in cleanup
  print("PASS existing boot cleanup and fixed packaged elevation route")

  menu = (repo / "default/monarch/monarch-menu.jsonc").read_text()
  guard = next(line for line in menu.splitlines() if '"trigger.toggle.passwordless-sudo"' in line)
  assert '/usr/bin/monarch-sudo-passwordless-root status' in guard
  assert '$(id -u)' in guard and 'systemctl' not in guard and '$USER' not in guard
  system = (repo / "install/reconcile/system.sh").read_text()
  assert 'sudo /usr/bin/monarch-sudo-passwordless-root revoke-legacy' in system
  print("PASS menu reads the bounded grant and upgrades revoke legacy unbounded rules")
PY
