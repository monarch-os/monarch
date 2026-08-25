#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
MENU="$ROOT/bin/monarch-menu"
SETUP="$ROOT/bin/monarch-setup-security-sshd"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_equals() {
  local description=$1 actual=$2 expected=$3
  [[ $actual == "$expected" ]] || fail "$description (expected '$expected', got '$actual')"
  printf 'ok - %s\n' "$description"
}

export MONARCH_PATH="$ROOT"
export PATH="$ROOT/bin:$PATH"

output=$("$MENU" --state | jq -r '.tree[] | select(.id == "setup.security.sshd") | .action')
assert_equals "setup exposes SSHD" "$output" \
  "monarch-launch-floating-terminal-with-presentation monarch-setup-security-sshd"

output=$("$MENU" --state | jq -r '.tree[] | select(.id == "remove.security.sshd") | .when')
assert_equals "removal is shown only for an enabled service" "$output" \
  "systemctl is-enabled --quiet sshd"

set +e
output=$("$SETUP" --gh-keys 2>&1)
status=$?
set -e
assert_equals "missing GitHub username is rejected before setup" "$status" "2"
[[ $output == *"needs a GitHub username"* ]] || fail "missing username explains the error"
printf 'ok - missing username explains the error\n'

set +e
output=$("$SETUP" --key=one --gh-keys=two 2>&1)
status=$?
set -e
assert_equals "conflicting key sources are rejected before setup" "$status" "2"
[[ $output == *"either --key or --gh-keys"* ]] || fail "conflicting sources explain the error"
printf 'ok - conflicting sources explain the error\n'

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat >"$TMP/bin/monarch-cmd-missing" <<'EOF'
#!/bin/bash
exit 1
EOF
cat >"$TMP/bin/sudo" <<'EOF'
#!/bin/bash
if [[ $* == *"ufw status"* ]]; then
  printf '%s\n' "${TEST_UFW_STATUS:-Status: inactive}"
fi
exit 0
EOF
chmod +x "$TMP/bin/monarch-cmd-missing" "$TMP/bin/sudo"

set +e
output=$(PATH="$TMP/bin:$PATH" "$SETUP" --key=invalid 2>&1)
status=$?
set -e
assert_equals "inactive UFW aborts setup" "$status" "1"
[[ $output == *"UFW is inactive"* ]] || fail "inactive UFW explains the refusal"
printf 'ok - inactive UFW explains the refusal\n'
