#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

export HOME="$test_tmp/home"
export T3CODE_HOME="$test_tmp/t3 home"
export TEST_LOG="$test_tmp/calls"
fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/monarch-pkg-add" <<'STUB'
#!/bin/bash
printf 'package %s\n' "$*" >>"$TEST_LOG"
STUB
cat >"$fake_bin/monarch-theme-apply" <<STUB
#!/bin/bash
"$ROOT/bin/monarch-theme-set-t3-code" "$ROOT/config/noctalia/palettes/Monarch.json" dark
STUB
cat >"$fake_bin/t3" <<'STUB'
#!/bin/bash
printf 't3 %s\n' "$*" >>"$TEST_LOG"
[[ $* == "theme set monarch --base-dir $T3CODE_HOME" ]]
[[ -f $T3CODE_HOME/userdata/themes/monarch.json ]]
STUB
cat >"$fake_bin/setsid" <<'STUB'
#!/bin/bash
printf 'launch %s\n' "$*" >>"$TEST_LOG"
STUB
chmod +x "$fake_bin"/*

PATH="$fake_bin:/usr/bin" "$ROOT/bin/monarch-install-ai-t3-code"

grep -qxF 'package t3code-bin' "$TEST_LOG"
grep -qxF "t3 theme set monarch --base-dir $T3CODE_HOME" "$TEST_LOG"
grep -qxF 'launch uwsm-app -- gtk-launch t3code' "$TEST_LOG"
echo "T3 Code is themed before its first launch"
