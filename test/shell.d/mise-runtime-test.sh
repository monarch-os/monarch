#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

real_mise=$(type -P mise) || fail "mise is required for runtime tests"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/home"
export HOME="$test_tmp/home"
export PATH="$test_tmp/bin:$ROOT/bin:$PATH"
export MONARCH_PATH="$ROOT"
export MISE_TEST_LOG="$test_tmp/mise-calls"

cat >"$test_tmp/bin/mise" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$MISE_TEST_LOG"
STUB
cat >"$test_tmp/bin/monarch-mise-install" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$test_tmp/bin/"*

[[ -f $ROOT/etc/mise/conf.d/monarch.toml ]] || fail "the package supplies mise defaults"
python3 - "$ROOT/etc/mise/conf.d/monarch.toml" <<'PY'
import sys
import tomllib
with open(sys.argv[1], "rb") as stream:
    config = tomllib.load(stream)
assert "tools" not in config, "Cursor must stay optional"
assert "settings" not in config, "user settings do not belong in system defaults"
cursor = config["tool_alias"]["cursor-agent"]
assert "bin_path=bin" in cursor
assert "dist-package/cursor-agent" in cursor
PY
pass "packaged mise defaults match Quattro without enabling optional tools"

source "$ROOT/install/user/mise.sh"
[[ $(<"$MISE_TEST_LOG") == "settings set upgrade.auto_prune false" ]] || fail "install does not persist the mise setting"

: >"$MISE_TEST_LOG"
bash "$ROOT/install/reconcile/mise.sh"
[[ $(<"$MISE_TEST_LOG") == "settings set upgrade.auto_prune false" ]] || fail "reconcile does not persist the mise setting"
pass "install and reconcile disable mise auto-pruning in the user settings"

mkdir -p "$HOME/Work"
printf '%s\n' '[env]' '_.path = "{{ cwd }}/bin"' >"$HOME/Work/.mise.toml"
bash "$ROOT/install/reconcile/mise.sh"
[[ ! -e $HOME/Work/.mise.toml ]] || fail "the stock Work config still trusts executables from every project"
printf '%s\n' '[env]' 'CUSTOM = "keep"' >"$HOME/Work/.mise.toml"
before=$(sha256sum "$HOME/Work/.mise.toml")
bash "$ROOT/install/reconcile/mise.sh"
[[ $(sha256sum "$HOME/Work/.mise.toml") == "$before" ]] || fail "mise reconciliation deletes custom Work settings"
mv "$HOME/Work/.mise.toml" "$test_tmp/custom.toml"
ln -s "$test_tmp/custom.toml" "$HOME/Work/.mise.toml"
bash "$ROOT/install/reconcile/mise.sh"
[[ -L $HOME/Work/.mise.toml ]] || fail "mise reconciliation deletes a custom Work symlink"
pass "mise removes only the generated project PATH trust and retains custom Work settings"

python3 - "$ROOT" "$HOME/Work/.mise.toml" <<'PY'
from pathlib import Path
import subprocess
import sys

root, config = map(Path, sys.argv[1:])
config.unlink()
for content in [
    b'[env]\n_.path = "{{ cwd }}/bin"\nCUSTOM = "\xff"\n',
    b'[env]\nCUSTOM = "unterminated\n',
]:
    config.write_bytes(content)
    original = config.stat()
    for _ in range(2):
        result = subprocess.run([
            "/bin/bash", "-euc",
            'source "$1/install/reconcile/mise.sh"; printf "reconciliation-continued\\n"',
            "bash", str(root),
        ], text=True, capture_output=True)
        assert result.returncode == 0, result.stderr
        assert result.stdout == "reconciliation-continued\n"
        assert "Keeping invalid user mise configuration:" in result.stderr
        assert config.read_bytes() == content
        current = config.stat()
        assert (current.st_ino, current.st_mode, current.st_mtime_ns) == (
            original.st_ino, original.st_mode, original.st_mtime_ns,
        )
PY
pass "invalid encoding and TOML preserve custom files without aborting sourced reconciliation"

mkdir -p "$test_tmp/packages" "$test_tmp/node/node-v22.0.0-linux-x64/bin"
printf '%s\n' offline-node >"$test_tmp/node/node-v22.0.0-linux-x64/bin/node"
tar -czf "$test_tmp/packages/node-v22.0.0-linux-x64.tar.gz" -C "$test_tmp/node" node-v22.0.0-linux-x64
sed "s|node_package_dir=/opt/packages|node_package_dir=$test_tmp/packages|" \
  "$ROOT/install/user/mise-work.sh" >"$test_tmp/mise-work.sh"
: >"$MISE_TEST_LOG"
MONARCH_SETUP_CONTEXT=iso-chroot bash "$test_tmp/mise-work.sh"
[[ $(<"$HOME/.local/share/mise/installs/node/22.0.0/bin/node") == offline-node ]] || fail "offline Node is not imported"
[[ $(<"$MISE_TEST_LOG") == "use -g node@22.0.0"$'\n'"config set tools.node latest --file $HOME/.config/mise/config.toml" ]] ||
  fail "offline Node stays pinned instead of allowing later upgrades"
pass "offline Node import requires no network and retains the latest global selector"

python3 - "$ROOT" "$test_tmp/real-home" "$real_mise" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import tomllib

root, home = map(Path, sys.argv[1:3])
mise = sys.argv[3]
project = home / "Work/untrusted-project"
(project / "bin").mkdir(parents=True)
config = home / "Work/.mise.toml"
probe = project / "bin/review-probe"
probe.write_text('#!/bin/sh\nprintf "fixture-project-bin-ran\\n"\n')
probe.chmod(0o755)
environment = {"HOME": str(home), "PATH": f"{Path(mise).parent}:/usr/bin", "USER": os.environ["USER"]}
for prefix in ["XDG", "MISE"]:
    for kind in ["CONFIG", "DATA", "CACHE", "STATE"]:
        suffix = "HOME" if prefix == "XDG" else "DIR"
        environment[f"{prefix}_{kind}_{suffix}"] = str(home / f".{prefix.lower()}-{kind.lower()}")

def run(*command, check=True):
    return subprocess.run(command, cwd=project, env=environment, text=True, capture_output=True, check=check)

for definition in [
    '[env]\n_.path = "{{ cwd }}/bin"\nREVIEW_CUSTOM = "keep"\n',
    '[env]\n"_".path = "{{ cwd }}/bin" # preserved comment\nREVIEW_CUSTOM = "keep"\n',
    '[env]\nREVIEW_CUSTOM = "keep"\n[env._]\npath = \'{{ cwd }}/bin\'\n',
    'env = { REVIEW_CUSTOM = "keep", _ = { path = "{{ cwd }}/bin" } }\n',
    '[env]\n_.path = "\\u007b\\u007b cwd }}/bin"\nREVIEW_CUSTOM = "keep"\n',
    '[env]\n_.path = """{{ cwd }}/bin"""\nREVIEW_CUSTOM = "keep"\n',
    '# "{{ cwd }}/bin" in a comment\r\n[env]\r\n_.path = "{{ cwd }}/bin"\r\nREVIEW_CUSTOM = "keep"\r\n',
]:
    config.write_text(definition)
    run(mise, "trust", str(config))
    assert run(mise, "exec", "--", "review-probe").stdout.strip() == "fixture-project-bin-ran"
    run("/bin/bash", str(root / "install/reconcile/mise.sh"))
    result = tomllib.loads(config.read_text())
    assert result["env"]["_"]["path"] == []
    assert result["env"]["REVIEW_CUSTOM"] == "keep"
    if "# preserved comment" in definition:
        assert "# preserved comment" in config.read_text()
    if "\r\n" in definition:
        assert config.read_bytes().count(b"\r\n") == definition.count("\r\n")
    run(mise, "trust", str(config))
    assert run(mise, "exec", "--", "review-probe", check=False).returncode != 0
    assert run(mise, "exec", "--", "printenv", "REVIEW_CUSTOM").stdout.strip() == "keep"
    inode = config.stat().st_ino
    run("/bin/bash", str(root / "install/reconcile/mise.sh"))
    assert config.stat().st_ino == inode
PY
pass "the real mise blocks project executables across TOML spellings and retains custom environment settings"
