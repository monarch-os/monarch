#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/home/.ssh"
printf 'saved key\n' >"$test_tmp/home/.ssh/authorized_keys"

cat >"$test_tmp/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
cat >"$test_tmp/bin/systemctl" <<'EOF'
#!/bin/bash
[[ $* == "disable --now sshd.service" ]] || exit 2
printf 'stop\n' >>"$CALL_LOG"
EOF
cat >"$test_tmp/bin/monarch-cmd-present" <<'EOF'
#!/bin/bash
[[ $1 == "ufw" && ${UFW_AVAILABLE:-1} == 1 ]]
EOF
cat >"$test_tmp/bin/gum" <<'EOF'
#!/bin/bash
exit 1
EOF
cat >"$test_tmp/bin/ufw" <<'EOF'
#!/bin/bash
printf 'ufw %s\n' "$*" >>"$CALL_LOG"
case "$*" in
  "--force delete limit 22/tcp" | "--force delete allow 22/tcp" | "--force delete allow 22" | \
    "--force delete allow ssh" | "--force delete limit ssh" | \
    "--force delete allow to any app SSH" | "--force delete limit to any app SSH" | \
    "--force delete allow log "* | "--force delete allow log-all "* | \
    "--force delete limit log "* | "--force delete limit log-all "*)
    rule=${*:3}
    if [[ $rule == "${UFW_DELETE_FAIL:-}" ]]; then
      echo "ERROR: could not delete SSH rule" >&2
      exit 1
    fi
    if ! grep -qxF "$rule" "$RULES"; then
      echo "Could not delete non-existent rule"
      exit 0
    fi
    awk -v rule="$rule" '$0 != rule' "$RULES" >"$RULES.next"
    mv "$RULES.next" "$RULES"
    ;;
  reload) [[ ${UFW_RELOAD_VALID:-1} == 1 ]] ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$test_tmp/bin/"*

run_removal() {
  HOME="$test_tmp/home" PATH="$test_tmp/bin:$PATH" \
    CALL_LOG="$test_tmp/calls" RULES="$test_tmp/rules" \
    bash "$ROOT/bin/monarch-remove-security-sshd"
}

plain_rules=('limit 22/tcp' 'allow 22/tcp' 'allow 22' 'allow ssh' 'limit ssh'
  'allow to any app SSH' 'limit to any app SSH')
standard_rules=()
for rule in "${plain_rules[@]}"; do
  standard_rules+=("$rule" "${rule%% *} log ${rule#* }" "${rule%% *} log-all ${rule#* }")
done
custom_rules=$'allow from 192.0.2.0/24 to any port 22 proto tcp\nallow from 192.0.2.0/24 to any app SSH\nallow log from 192.0.2.0/24 to any port 22 proto tcp\nlimit log-all from 192.0.2.0/24 to any app SSH\nallow from 2001:db8::/32 to any port 22 proto tcp\nallow 2222/tcp\nallow log 2222/tcp\nlimit log-all 2222/tcp\nallow 443/tcp\nallow log-all 443/tcp'
for rule in "${standard_rules[@]}" mixed absent; do
  printf '%s\n' "$custom_rules" >"$test_tmp/rules"
  case $rule in
    mixed) printf '%s\n' "${standard_rules[@]}" >>"$test_tmp/rules" ;;
    absent) ;;
    *) printf '%s\n' "$rule" >>"$test_tmp/rules" ;;
  esac
  : >"$test_tmp/calls"
  run_removal >"$test_tmp/output" 2>&1 || fail "removal failed for $rule"
  [[ $(cat "$test_tmp/rules") == "$custom_rules" ]] ||
    fail "standard SSH rule remains or custom rules changed for $rule"
  [[ $(head -n 1 "$test_tmp/calls") == "stop" ]] ||
    fail "firewall changed before stopping sshd"
  [[ $(tail -n 1 "$test_tmp/calls") == "ufw reload" ]] ||
    fail "firewall not reloaded after deletion"
  [[ $(cat "$test_tmp/home/.ssh/authorized_keys") == "saved key" ]] ||
    fail "declined key removal changed authorized keys"
  grep -qF 'Review custom firewall rules separately.' "$test_tmp/output" ||
    fail "removal does not explain the scope of firewall cleanup"
  ! grep -qF 'firewall port closed' "$test_tmp/output" ||
    fail "removal claims custom SSH rules cannot leave the port open"
  pass "SSH removal handles $rule and preserves custom rules and keys"
done

: >"$test_tmp/calls"
UFW_AVAILABLE=0 run_removal >"$test_tmp/output" 2>&1 ||
  fail "missing UFW prevents disabling sshd"
[[ $(cat "$test_tmp/calls") == "stop" ]] || fail "missing UFW still called the firewall"
! grep -qF 'Standard SSH firewall rules removed.' "$test_tmp/output" ||
  fail "missing UFW still reports firewall cleanup"
pass "SSH removal works without UFW"

for rule in "${standard_rules[@]}"; do
  printf '%s\n' "$custom_rules" "$rule" >"$test_tmp/rules"
  : >"$test_tmp/calls"
  if UFW_DELETE_FAIL="$rule" run_removal >"$test_tmp/output" 2>&1; then
    fail "failed deletion reported success for $rule"
  fi
  grep -qxF "$rule" "$test_tmp/rules" || fail "failed deletion removed $rule"
  grep -qF 'ERROR: could not delete SSH rule' "$test_tmp/output" ||
    fail "failed deletion hid its error for $rule"
  ! grep -qF 'Standard SSH firewall rules removed.' "$test_tmp/output" ||
    fail "failed deletion reported successful cleanup for $rule"
  ! grep -qF 'The SSH server has been disabled' "$test_tmp/output" ||
    fail "failed deletion printed completion for $rule"
  ! grep -qF 'ufw reload' "$test_tmp/calls" ||
    fail "failed deletion still reloaded the firewall for $rule"
done
pass "SSH removal propagates errors for all standard rule variants"

if UFW_RELOAD_VALID=0 run_removal >"$test_tmp/output" 2>&1; then
  fail "failed firewall reload reported success"
fi
! grep -qF 'The SSH server has been disabled' "$test_tmp/output" ||
  fail "failed firewall reload printed completion"
! grep -qF 'Standard SSH firewall rules removed.' "$test_tmp/output" ||
  fail "failed firewall reload reported successful cleanup"
pass "SSH removal fails when the firewall cannot reload"
