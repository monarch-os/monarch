#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export PATH="$test_tmp/bin:$ROOT/bin:/usr/bin"
export TEST_CHATGPT_STATE="$test_tmp/state" TEST_CHATGPT_CALLS="$test_tmp/calls"

cat >"$test_tmp/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
cat >"$test_tmp/bin/pacman" <<'EOF'
#!/bin/bash
set -euo pipefail
case "$1" in
  -Q) [[ ${3:-} == "$(cat "$TEST_CHATGPT_STATE")" ]] ;;
  -S)
    printf '%s\n' "$*" >>"$TEST_CHATGPT_CALLS"
    [[ $* == '-S --needed --noconfirm --ask=4 cachyos/chatgpt-desktop-bin' ]] || exit 2
    [[ ${TEST_PACKAGE_STATUS:-0} == 0 ]] || exit "$TEST_PACKAGE_STATUS"
    echo chatgpt-desktop-bin >"$TEST_CHATGPT_STATE"
    ;;
  *) exit 3 ;;
esac
EOF
chmod +x "$test_tmp/bin/"*

reconcile() {
  bash "$ROOT/install/reconcile/chatgpt.sh"
}

: >"$TEST_CHATGPT_STATE"
: >"$TEST_CHATGPT_CALLS"
reconcile
[[ ! -s $TEST_CHATGPT_CALLS ]] || fail "installed an unrequested application"

echo openai-codex-desktop >"$TEST_CHATGPT_STATE"
if TEST_PACKAGE_STATUS=23 reconcile; then
  fail "a failed replacement returned success"
fi
[[ $(<"$TEST_CHATGPT_STATE") == openai-codex-desktop ]] || fail "removed the legacy package before replacement"

: >"$TEST_CHATGPT_CALLS"
reconcile
[[ $(<"$TEST_CHATGPT_STATE") == chatgpt-desktop-bin ]] || fail "did not replace the legacy package"
reconcile
[[ $(wc -l <"$TEST_CHATGPT_CALLS") == 1 ]] || fail "repeated reconciliation reinstalled the package"
pass "ChatGPT replacement is opt-in, atomic on failure, and idempotent"
