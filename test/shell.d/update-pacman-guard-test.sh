#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

run_guard() {
  MONARCH_PACMAN_CMDLINE="$1" "$ROOT/bin/monarch-update-pacman-guard"
}

assert_blocked() {
  local command_line="$1"
  local name="$2"

  if run_guard "$command_line" >"$test_tmp/$name.out" 2>"$test_tmp/$name.err"; then
    fail "pacman guard blocks $name"
  fi
}

assert_blocked "pacman -Syu --noconfirm" "short-system-upgrade"
grep -q 'monarch update' "$test_tmp/short-system-upgrade.err" ||
  fail "pacman guard explains the Monarch update entrypoint"
grep -q 'MONARCH_ALLOW_DIRECT_PACMAN=1' "$test_tmp/short-system-upgrade.err" ||
  fail "pacman guard documents the direct-upgrade escape hatch"
pass "pacman guard blocks direct pacman -Syu with actionable guidance"

assert_blocked "pacman -S --sysupgrade" "mixed-system-upgrade"
assert_blocked "pacman --sync --refresh --sysupgrade" "long-system-upgrade"
assert_blocked "pacman -Syyuu --noconfirm" "repeated-upgrade-flags"
pass "pacman guard recognizes short, mixed and long system-upgrade forms"

MONARCH_UPDATE_PACMAN=1 run_guard "pacman -Syu" 2>"$test_tmp/monarch.err"
[[ ! -s $test_tmp/monarch.err ]] || fail "pacman guard stays quiet for Monarch updates"

MONARCH_ALLOW_DIRECT_PACMAN=1 run_guard "pacman -Syu" 2>"$test_tmp/override.err"
[[ ! -s $test_tmp/override.err ]] || fail "pacman guard stays quiet for explicit overrides"
pass "pacman guard allows official updates and explicit direct overrides"

for command_line in \
  "pacman -S firefox" \
  "pacman -Sy" \
  "pacman -Rns firefox" \
  "pacman -S -- -unusual-package"; do
  run_guard "$command_line" 2>"$test_tmp/ignored.err"
  [[ ! -s $test_tmp/ignored.err ]] || fail "pacman guard stays quiet for $command_line"
done
pass "pacman guard ignores non-system-upgrade transactions"

hook="$ROOT/default/libalpm/hooks/00-monarch-update-guard.hook"
grep -Fxq 'When = PreTransaction' "$hook" || fail "pacman guard hook runs before transactions"
grep -Fxq 'AbortOnFail' "$hook" || fail "pacman guard hook aborts rejected transactions"
grep -Fxq 'Exec = /usr/bin/monarch-update-pacman-guard' "$hook" ||
  fail "pacman guard hook uses the packaged command"

for command in monarch-update-system-pkgs monarch-refresh-pacman monarch-reinstall-pkgs; do
  grep -Fq 'MONARCH_UPDATE_PACMAN=1 pacman -S' "$ROOT/bin/$command" ||
    fail "$command marks its system upgrades as Monarch-owned"
done
pass "every Monarch-owned system-upgrade path opts into the guard"

python3 - "$ROOT" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])


def unmarked_upgrades(path, source):
  source = source.replace("\\\n", " ")
  violations = []

  for segment in re.split(r"[;\n]", source):
    for match in re.finditer(r"\bpacman\b[^|&]*", segment):
      invocation = re.split(r"\s--\s", match.group(0), maxsplit=1)[0]
      options = re.findall(r"(?<!\S)(--[a-z-]+|-[A-Za-z]+)", invocation)
      has_sync = "--sync" in options or any(
        option.startswith("-") and not option.startswith("--") and "S" in option
        for option in options
      )
      has_sysupgrade = "--sysupgrade" in options or any(
        option.startswith("-") and not option.startswith("--") and "u" in option
        for option in options
      )

      marked = "MONARCH_UPDATE_PACMAN=1" in segment
      documented_override = (
        str(path) == "bin/monarch-update-pacman-guard"
        and "MONARCH_ALLOW_DIRECT_PACMAN=1" in segment
      )
      if has_sync and has_sysupgrade and not (marked or documented_override):
        violations.append(f"{path}: {segment.strip()}")

  return violations


violations = []
for directory in (root / "bin", root / "install"):
  for path in directory.rglob("*"):
    if path.is_file():
      try:
        source = path.read_text()
      except UnicodeDecodeError:
        continue
      violations.extend(unmarked_upgrades(path.relative_to(root), source))

assert unmarked_upgrades("fixture", "sudo pacman -Syu")
assert unmarked_upgrades("fixture", "sudo pacman -S \\\n+  --sysupgrade")
assert not unmarked_upgrades(
  "fixture", "sudo env MONARCH_UPDATE_PACMAN=1 pacman --sync --sysupgrade"
)
assert unmarked_upgrades(
  "fixture", "sudo env MONARCH_ALLOW_DIRECT_PACMAN=1 pacman -Syu"
)

if violations:
  print("Unmarked pacman system-upgrade calls:", file=sys.stderr)
  print("\n".join(violations), file=sys.stderr)
  sys.exit(1)
PY
pass "repository audit rejects unmarked pacman system-upgrade calls"
