#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/provisioning"

cat >"$test_root/bin/getent" <<'STUB'
#!/bin/bash
[[ $1 == group && $2 =~ ^(audio|input)$ ]]
STUB
cat >"$test_root/bin/pacman" <<'STUB'
#!/bin/bash
[[ $1 == -Qq && $2 == ydotool && ${TEST_YDOTOOL:-false} == true ]]
STUB
chmod +x "$test_root/bin/"*

PATH="$test_root/bin:$PATH"
PROVISIONING_DIR="$test_root/provisioning"
eval "$(sed -n '/^user_groups() {/,/^}/p' "$ROOT/bin/monarch-provision-owner")"

printf '%s\n' input docker audio >"$PROVISIONING_DIR/groups"
[[ $(user_groups) == wheel,audio ]] || fail "stale privileged groups were replayed"
pass "deferred provisioning filters stale privileged defaults"

TEST_YDOTOOL=true
export TEST_YDOTOOL
[[ $(user_groups) == wheel,input,audio ]] || fail "ydotool input access was discarded"
pass "deferred provisioning preserves the explicit ydotool opt-in"

if grep -qF 'hardware/input-group.sh' "$ROOT/install/hardware/all.sh" ||
  [[ -e $ROOT/install/hardware/input-group.sh ]]; then
  fail "default hardware setup still owns an input-group grant"
fi
pass "default installation records no input-group grant"
