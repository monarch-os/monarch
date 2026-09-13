#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/monarch-pkg-add" <<'EOF'
#!/bin/bash
printf 'pkg %s\n' "$*" >>"$CALL_LOG"
EOF
cat >"$stub_bin/monarch-cmd-missing" <<'EOF'
#!/bin/bash
exit 1
EOF
cat >"$stub_bin/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$CALL_LOG"
case "$1 $2" in
  "is-enabled --quiet") [[ ${SSHD_ENABLED:-0} == 1 ]] ;;
  "is-active --quiet") [[ ${SSHD_ACTIVE:-0} == 1 ]] ;;
  "start sshdgenkeys.service") ;;
  "reload sshd.service") [[ ${SSHD_RELOAD_VALID:-1} == 1 ]] ;;
  "enable sshd.service" | "enable --now") ;;
  *) exit 2 ;;
esac
EOF
cat >"$stub_bin/sshd" <<'EOF'
#!/bin/bash
printf 'sshd %s\n' "$*" >>"$CALL_LOG"
case $1 in
  -t) [[ ${SSHD_SYNTAX_VALID:-1} == 1 ]] ;;
  -T)
    password=${SSHD_PASSWORD_AUTH:-}
    [[ -n $password ]] || { [[ -f $TEST_CONFIG ]] && password=no || password=yes; }
    [[ $* != *" -C "* || -z ${SSHD_CONTEXT_PASSWORD:-} ]] || password=$SSHD_CONTEXT_PASSWORD
    if [[ ${SSHD_DUMP_LOWERCASE:-0} == 1 ]]; then
      printf 'passwordauthentication %s\n' "$password"
      printf 'kbdinteractiveauthentication %s\n' "${SSHD_KBD_AUTH:-no}"
      printf 'pubkeyauthentication %s\n' "${SSHD_PUBKEY_AUTH:-yes}"
      printf 'authorizedkeysfile %s\n' "${SSHD_AUTHORIZED_KEYS_FILE:-.ssh/authorized_keys}"
      printf 'authenticationmethods %s\n' "${SSHD_AUTH_METHODS:-any}"
      [[ ${SSHD_REVOKED_KEYS:-omit} == "omit" ]] ||
        printf 'revokedkeys %s\n' "$SSHD_REVOKED_KEYS"
      printf 'permitrootlogin %s\n' "${SSHD_ROOT_LOGIN:-prohibit-password}"
      printf 'pubkeyacceptedalgorithms %s\n' "${SSHD_PUBKEY_ACCEPTED:-ssh-ed25519,ssh-rsa,rsa-sha2-256,rsa-sha2-512}"
      printf 'requiredrsasize %s\n' "${SSHD_REQUIRED_RSA_SIZE:-1024}"
    else
      printf 'PasswordAuthentication %s\n' "$password"
      printf 'KbdInteractiveAuthentication %s\n' "${SSHD_KBD_AUTH:-no}"
      printf 'PubkeyAuthentication %s\n' "${SSHD_PUBKEY_AUTH:-yes}"
      printf 'AuthorizedKeysFile %s\n' "${SSHD_AUTHORIZED_KEYS_FILE:-.ssh/authorized_keys}"
      printf 'AuthenticationMethods %s\n' "${SSHD_AUTH_METHODS:-any}"
      [[ ${SSHD_REVOKED_KEYS:-omit} == "omit" ]] ||
        printf 'RevokedKeys %s\n' "$SSHD_REVOKED_KEYS"
      printf 'PermitRootLogin %s\n' "${SSHD_ROOT_LOGIN:-prohibit-password}"
      printf 'PubkeyAcceptedAlgorithms %s\n' "${SSHD_PUBKEY_ACCEPTED:-ssh-ed25519,ssh-rsa,rsa-sha2-256,rsa-sha2-512}"
      printf 'RequiredRSASize %s\n' "${SSHD_REQUIRED_RSA_SIZE:-1024}"
    fi
    ;;
  *) exit 2 ;;
esac
EOF
cat >"$stub_bin/ufw" <<'EOF'
#!/bin/bash
printf 'ufw %s\n' "$*" >>"$CALL_LOG"
[[ $1 != "limit" || ${UFW_LIMIT_VALID:-1} == 1 ]] || exit 1
if [[ $1 == "status" ]]; then
  echo 'Status: active'
  [[ ${UFW_MARKER:-1} == 1 ]] && echo '22/tcp LIMIT Anywhere # monarch-sshd'
fi
EOF
cat >"$stub_bin/sudo" <<'EOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$CALL_LOG"
exec "$@"
EOF
cat >"$stub_bin/chmod" <<'EOF'
#!/bin/bash
if [[ ${FAIL_KEY_CHMOD:-0} == 1 && ${*: -1} == */authorized_keys ]]; then
  exit 1
fi
if [[ ${FAIL_CONFIG_CHMOD:-0} == 1 && ${*: -1} == */10-monarch-hardening.conf ]]; then
  exit 1
fi
exec /usr/bin/chmod "$@"
EOF
cat >"$stub_bin/chown" <<'EOF'
#!/bin/bash
[[ ${FAIL_CONFIG_CHOWN:-0} != 1 || ${*: -1} != */10-monarch-hardening.conf ]]
EOF
cat >"$stub_bin/getent" <<'EOF'
#!/bin/bash
[[ $1 == "passwd" ]] || exit 2
printf '%s:x:1000:1000::%s:/bin/bash\n' "$TEST_USER" "$HOME"
[[ ${EXTRA_LOGIN_USER:-0} != 1 ]] || printf 'admin:x:999:999::/home/admin:/bin/bash\n'
exit 0
EOF
cat >"$stub_bin/install" <<'EOF'
#!/bin/bash
args=()
while (( $# > 0 )); do
  case $1 in
    -m)
      args+=("$1" "$2")
      shift 2
      ;;
    -o | -g) shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
exec /usr/bin/install "${args[@]}"
EOF
chmod +x "$stub_bin"/*

ssh-keygen -q -t ed25519 -N "" -f "$test_tmp/key"
ssh-keygen -q -t rsa -b 2048 -N "" -f "$test_tmp/rsa_key"
public_key=$(<"$test_tmp/key.pub")
rsa_public_key=$(<"$test_tmp/rsa_key.pub")

prepare_runtime() {
  local scenario=$1 root runtime

  root="$test_tmp/$scenario/root"
  runtime="$test_tmp/$scenario/runtime"

  mkdir -p "$root/etc/ssh/sshd_config.d" "$root/usr/lib/systemd/sshd_config.d" \
    "$runtime/install/helpers"
  printf '%s\n' '# Packaged systemd SSH configuration.' > \
    "$root/usr/lib/systemd/sshd_config.d/20-systemd-userdb.conf"
  [[ -L $root/etc/ssh/sshd_config.d/20-systemd-userdb.conf ]] ||
    ln -s ../../../usr/lib/systemd/sshd_config.d/20-systemd-userdb.conf \
      "$root/etc/ssh/sshd_config.d/20-systemd-userdb.conf"
  if [[ ! -f $root/etc/ssh/sshd_config ]]; then
    printf 'Include %s/*.conf\n' "$root/etc/ssh/sshd_config.d" >"$root/etc/ssh/sshd_config"
  fi
  cp "$ROOT/install/helpers/"{as-root,sshd-hardening}.sh "$runtime/install/helpers/"
  sed -i "s|/etc/ssh|$root/etc/ssh|g" \
    "$runtime/install/helpers/sshd-hardening.sh"
  sed -i "s|/usr/lib/systemd/sshd_config.d|$root/usr/lib/systemd/sshd_config.d|g" \
    "$runtime/install/helpers/sshd-hardening.sh"
}

run_setup() {
  local scenario=$1 home runtime

  home="$test_tmp/$scenario/home"
  runtime="$test_tmp/$scenario/runtime"

  prepare_runtime "$scenario"
  mkdir -p "$home"
  chmod 0755 "$home"
  : >"$test_tmp/$scenario.calls"
  HOME="$home" MONARCH_PATH="$runtime" CALL_LOG="$test_tmp/$scenario.calls" \
    TEST_CONFIG="$test_tmp/$scenario/root/etc/ssh/sshd_config.d/10-monarch-hardening.conf" \
    SSHD_ACTIVE="${SSHD_ACTIVE:-0}" SSHD_ENABLED="${SSHD_ENABLED:-0}" \
    SSHD_SYNTAX_VALID="${SSHD_SYNTAX_VALID:-1}" \
    SSHD_PASSWORD_AUTH="${SSHD_PASSWORD_AUTH:-}" \
    SSHD_CONTEXT_PASSWORD="${SSHD_CONTEXT_PASSWORD:-}" \
    SSHD_KBD_AUTH="${SSHD_KBD_AUTH:-no}" \
    SSHD_PUBKEY_AUTH="${SSHD_PUBKEY_AUTH:-yes}" \
    SSHD_AUTHORIZED_KEYS_FILE="${SSHD_AUTHORIZED_KEYS_FILE:-.ssh/authorized_keys}" \
    SSHD_AUTH_METHODS="${SSHD_AUTH_METHODS:-any}" \
    SSHD_REVOKED_KEYS="${SSHD_REVOKED_KEYS:-omit}" \
    SSHD_ROOT_LOGIN="${SSHD_ROOT_LOGIN:-prohibit-password}" \
    SSHD_PUBKEY_ACCEPTED="${SSHD_PUBKEY_ACCEPTED:-ssh-ed25519,ssh-rsa,rsa-sha2-256,rsa-sha2-512}" \
    SSHD_REQUIRED_RSA_SIZE="${SSHD_REQUIRED_RSA_SIZE:-1024}" \
    SSHD_DUMP_LOWERCASE="${SSHD_DUMP_LOWERCASE:-0}" \
    FAIL_KEY_CHMOD="${FAIL_KEY_CHMOD:-0}" FAIL_CONFIG_CHMOD="${FAIL_CONFIG_CHMOD:-0}" \
    FAIL_CONFIG_CHOWN="${FAIL_CONFIG_CHOWN:-0}" UFW_LIMIT_VALID="${UFW_LIMIT_VALID:-1}" UFW_MARKER=1 \
    PATH="$stub_bin:/usr/bin" \
    bash "$ROOT/bin/monarch-setup-security-sshd" "${2:---key=$public_key}"
}

line_number() {
  grep -n -m1 -F "$2" "$1" | cut -d: -f1
}

output=$(run_setup success)
config="$test_tmp/success/root/etc/ssh/sshd_config.d/10-monarch-hardening.conf"
grep -qxF 'PasswordAuthentication no' "$config" || fail "SSH setup disables password authentication"
grep -qxF 'KbdInteractiveAuthentication no' "$config" || fail "SSH setup disables keyboard-interactive authentication"
calls="$test_tmp/success.calls"
(( $(line_number "$calls" 'sudo mv -fT') < $(line_number "$calls" 'ufw limit 22/tcp') )) ||
  fail "SSH setup opens the firewall before publishing hardening"
(( $(line_number "$calls" 'ufw limit 22/tcp') < $(line_number "$calls" 'systemctl enable --now sshd.service') )) ||
  fail "SSH setup starts sshd before the firewall rule is ready"
[[ $output == *"key-only authentication"* ]] || fail "SSH setup reports its effective policy"
pass "SSH setup publishes key-only policy before exposing the daemon"
[[ -L $test_tmp/success/root/etc/ssh/sshd_config.d/20-systemd-userdb.conf ]] ||
  fail "test fixture did not exercise the packaged systemd SSH symlink"
pass "SSH setup accepts Arch's packaged systemd SSH configuration symlink"

output=$(SSHD_DUMP_LOWERCASE=1 run_setup lowercase)
[[ $output == *"key-only authentication"* ]] || fail "lowercase sshd output rejected valid hardening"
pass "SSH setup accepts OpenSSH keyword casing variants"

if run_setup invalid-key invalid >"$test_tmp/invalid-key.output" 2>&1; then
  fail "SSH setup accepted an invalid key"
fi
! grep -Eq 'ufw (limit|reload)|systemctl (enable|reload).*sshd.service' "$test_tmp/invalid-key.calls" ||
  fail "invalid key setup exposed sshd"
pass "SSH setup leaves the firewall and daemon untouched after invalid input"

if FAIL_KEY_CHMOD=1 run_setup key-write-failure >"$test_tmp/key-write-failure.output" 2>&1; then
  fail "SSH setup masked an authorized_keys publication failure"
fi
! grep -Eq 'ufw (limit|reload)|systemctl (enable|reload).*sshd.service' "$test_tmp/key-write-failure.calls" ||
  fail "failed key publication exposed sshd"
pass "SSH setup propagates authorized_keys publication failures"

if SSHD_CONTEXT_PASSWORD=yes run_setup match-override >"$test_tmp/match-override.output" 2>&1; then
  fail "SSH setup ignored an owner-context password override"
fi
[[ ! -e $test_tmp/match-override/root/etc/ssh/sshd_config.d/10-monarch-hardening.conf ]] ||
  fail "ineffective contextual hardening was retained"
! grep -Eq 'ufw (limit|reload)|systemctl (enable|reload).*sshd.service' "$test_tmp/match-override.calls" ||
  fail "contextually ineffective hardening exposed sshd"
pass "SSH setup validates the owner-context policy"

if SSHD_AUTH_METHODS=publickey,password run_setup chained-auth >"$test_tmp/chained-auth.output" 2>&1; then
  fail "SSH setup accepted authentication methods that still require a password"
fi
pass "SSH setup rejects incompatible authentication method chains"

output=$(SSHD_AUTH_METHODS=publickey run_setup publickey-method)
[[ $output == *"key-only authentication"* ]] || fail "explicit publickey authentication was rejected"
pass "SSH setup accepts an explicit publickey authentication method"

if SSHD_REVOKED_KEYS=/etc/ssh/revoked_keys run_setup revoked-policy \
  >"$test_tmp/revoked-policy.output" 2>&1; then
  fail "SSH setup accepted a key without checking the configured revocation list"
fi
pass "SSH setup fails closed when a key revocation list is configured"

prepare_runtime conditional-config
printf '%s\n' 'Match Address 192.0.2.0/24' '  PasswordAuthentication yes' >> \
  "$test_tmp/conditional-config/root/etc/ssh/sshd_config"
if run_setup conditional-config >"$test_tmp/conditional-config.output" 2>&1; then
  fail "SSH setup accepted a conditional password override"
fi
[[ ! -e $test_tmp/conditional-config/root/etc/ssh/sshd_config.d/10-monarch-hardening.conf ]] ||
  fail "SSH setup retained hardening it could not prove universal"
! grep -Eq 'ufw (limit|reload)|systemctl (enable|reload).*sshd.service' \
  "$test_tmp/conditional-config.calls" || fail "conditional configuration exposed sshd"
pass "SSH setup rejects conditional password-authentication bypasses"

prepare_runtime existing-config
existing="$test_tmp/existing-config/root/etc/ssh/sshd_config.d/10-monarch-hardening.conf"
printf '%s\n' \
  '# Managed by Monarch.' \
  'PasswordAuthentication no' \
  'KbdInteractiveAuthentication no' >"$existing"
if SSHD_SYNTAX_VALID=0 run_setup existing-config >"$test_tmp/existing-config.output" 2>&1; then
  fail "SSH setup ignored an invalid effective configuration"
fi
[[ -f $existing ]] || fail "SSH setup removed a pre-existing managed configuration after validation failed"
grep -qxF 'PasswordAuthentication no' "$existing" ||
  fail "SSH setup changed the pre-existing managed configuration"
pass "SSH setup preserves prior managed policy when validation fails"

prepare_runtime administrator-config
administrator="$test_tmp/administrator-config/root/etc/ssh/sshd_config.d/10-monarch-hardening.conf"
printf '%s\n' 'PasswordAuthentication yes' >"$administrator"
if run_setup administrator-config >"$test_tmp/administrator-config.output" 2>&1; then
  fail "SSH setup replaced an administrator-owned configuration"
fi
grep -qxF 'PasswordAuthentication yes' "$administrator" ||
  fail "SSH setup changed an administrator-owned configuration"
! grep -Eq 'ufw (limit|reload)|systemctl (enable|reload).*sshd.service' \
  "$test_tmp/administrator-config.calls" || fail "configuration conflict exposed sshd"
pass "SSH setup refuses to overwrite an unexpected configuration"

SSHD_ACTIVE=1 run_setup active >/dev/null
grep -qxF 'sudo systemctl reload sshd.service' "$test_tmp/active.calls" ||
  fail "SSH setup did not reload an already-active daemon"
grep -qxF 'sudo systemctl enable sshd.service' "$test_tmp/active.calls" ||
  fail "SSH setup did not preserve startup for an active daemon"
! grep -qF 'systemctl enable --now sshd.service' "$test_tmp/active.calls" ||
  fail "SSH setup restarted an already-active daemon"
pass "SSH setup reloads an existing daemon after hardening"
(( $(line_number "$test_tmp/active.calls" 'systemctl reload sshd.service') <
  $(line_number "$test_tmp/active.calls" 'ufw limit 22/tcp') )) ||
  fail "SSH setup mutated the firewall before reloading an active daemon"
pass "SSH setup hardens an active daemon before firewall mutation"

if SSHD_ACTIVE=1 UFW_LIMIT_VALID=0 run_setup active-firewall-failure \
  >"$test_tmp/active-firewall-failure.output" 2>&1; then
  fail "SSH setup ignored a firewall publication failure"
fi
grep -qF 'systemctl reload sshd.service' "$test_tmp/active-firewall-failure.calls" ||
  fail "firewall failure stranded an active daemon on its old policy"
pass "SSH setup does not strand an active daemon on password policy after firewall failure"

prepare_runtime key-lines
MONARCH_PATH="$test_tmp/key-lines/runtime"
source "$MONARCH_PATH/install/helpers/sshd-hardening.sh"
key_effective=$'PubkeyAcceptedAlgorithms ssh-ed25519,ssh-rsa,rsa-sha2-256,rsa-sha2-512\nRequiredRSASize 1024'
printf '%s\n' "@revoked $public_key" >"$test_tmp/revoked_keys"
! monarch_sshd_has_usable_key "$test_tmp/revoked_keys" test "$key_effective" ||
  fail "revoked authorized_keys markers counted as usable keys"
printf '%s\n' "cert-authority $public_key" >"$test_tmp/cert_authority_keys"
! monarch_sshd_has_usable_key "$test_tmp/cert_authority_keys" test "$key_effective" ||
  fail "a certificate authority counted as a direct login key"
printf '%s\n' "from=192.0.2.1 $public_key" >"$test_tmp/restricted_keys"
! monarch_sshd_has_usable_key "$test_tmp/restricted_keys" test "$key_effective" ||
  fail "a source-constrained key counted as universally usable"
printf '%s\n' "$public_key" >"$test_tmp/plain_keys"
monarch_sshd_has_usable_key "$test_tmp/plain_keys" test "$key_effective" ||
  fail "a plain public key was rejected"
! monarch_sshd_has_usable_key "$test_tmp/key" test "$key_effective" ||
  fail "a private key counted as an authorized public key"
pass "SSH key detection requires a direct, unconstrained public key"

printf '%s\n' "$rsa_public_key" >"$test_tmp/rsa_keys"
rsa_disabled=$'PubkeyAcceptedAlgorithms ssh-ed25519\nRequiredRSASize 1024'
! monarch_sshd_has_usable_key "$test_tmp/rsa_keys" test "$rsa_disabled" ||
  fail "a disabled RSA signature algorithm counted as usable"
rsa_too_small=$'PubkeyAcceptedAlgorithms rsa-sha2-512\nRequiredRSASize 4096'
! monarch_sshd_has_usable_key "$test_tmp/rsa_keys" test "$rsa_too_small" ||
  fail "an undersized RSA key counted as usable"
monarch_sshd_has_usable_key "$test_tmp/rsa_keys" test "$key_effective" ||
  fail "an accepted RSA key was rejected"
pass "SSH key detection enforces the effective algorithm and RSA-size policy"

run_reconcile() {
  local scenario=$1 key_state=$2 marker=$3
  local home runtime

  home="$test_tmp/$scenario/home"
  runtime="$test_tmp/$scenario/runtime"

  prepare_runtime "$scenario"
  mkdir -p "$home/.ssh"
  chmod 0755 "$home"
  chmod 0700 "$home/.ssh"
  if [[ $key_state == "valid" ]]; then
    printf '%s\n' "$public_key" >"$home/.ssh/authorized_keys"
    chmod 0600 "$home/.ssh/authorized_keys"
  fi
  : >"$test_tmp/$scenario.calls"
  HOME="$home" MONARCH_PATH="$runtime" CALL_LOG="$test_tmp/$scenario.calls" \
    TEST_CONFIG="$test_tmp/$scenario/root/etc/ssh/sshd_config.d/10-monarch-hardening.conf" \
    SSHD_ENABLED=1 SSHD_ACTIVE="${SSHD_ACTIVE:-1}" UFW_MARKER="$marker" \
    SSHD_PASSWORD_AUTH="${SSHD_PASSWORD_AUTH:-}" \
    SSHD_CONTEXT_PASSWORD="${SSHD_CONTEXT_PASSWORD:-}" \
    SSHD_KBD_AUTH="${SSHD_KBD_AUTH:-no}" SSHD_PUBKEY_AUTH="${SSHD_PUBKEY_AUTH:-yes}" \
    SSHD_AUTHORIZED_KEYS_FILE="${SSHD_AUTHORIZED_KEYS_FILE:-.ssh/authorized_keys}" \
    SSHD_AUTH_METHODS="${SSHD_AUTH_METHODS:-any}" SSHD_REVOKED_KEYS="${SSHD_REVOKED_KEYS:-omit}" \
    SSHD_ROOT_LOGIN="${SSHD_ROOT_LOGIN:-prohibit-password}" TEST_USER="$(id -un)" \
    SSHD_PUBKEY_ACCEPTED="${SSHD_PUBKEY_ACCEPTED:-ssh-ed25519,ssh-rsa,rsa-sha2-256,rsa-sha2-512}" \
    SSHD_REQUIRED_RSA_SIZE="${SSHD_REQUIRED_RSA_SIZE:-1024}" \
    EXTRA_LOGIN_USER="${EXTRA_LOGIN_USER:-0}" PATH="$stub_bin:/usr/bin" \
    bash "$ROOT/install/reconcile/sshd-hardening.sh"
}

run_reconcile unmarked valid 0 >/dev/null
[[ ! -e $test_tmp/unmarked/root/etc/ssh/sshd_config.d/10-monarch-hardening.conf ]] ||
  fail "reconciliation adopted an SSH server not identified as Monarch-managed"
! grep -qF 'systemctl reload sshd.service' "$test_tmp/unmarked.calls" ||
  fail "reconciliation reloaded an unmarked SSH server"
pass "SSH reconciliation leaves unmarked administrator servers alone"

output=$(run_reconcile missing-key missing 1)
[[ ! -e $test_tmp/missing-key/root/etc/ssh/sshd_config.d/10-monarch-hardening.conf ]] ||
  fail "reconciliation hardened a server without an authorized key"
[[ $output == *"has no usable public key"* ]] || fail "missing key warning was not actionable"
! grep -qF 'systemctl reload sshd.service' "$test_tmp/missing-key.calls" ||
  fail "reconciliation reloaded a server without a key"
pass "SSH reconciliation avoids locking out password-only installations"

output=$(EXTRA_LOGIN_USER=1 run_reconcile multiple-users valid 1)
[[ ! -e $test_tmp/multiple-users/root/etc/ssh/sshd_config.d/10-monarch-hardening.conf ]] ||
  fail "reconciliation globally hardened a multi-user server"
[[ $output == *"other login identities"* ]] || fail "multi-user warning was not actionable"
! grep -qF 'systemctl reload sshd.service' "$test_tmp/multiple-users.calls" ||
  fail "reconciliation reloaded a multi-user server"
pass "SSH reconciliation avoids locking out another login identity"

run_reconcile legacy-server valid 1 >/dev/null
reconciled="$test_tmp/legacy-server/root/etc/ssh/sshd_config.d/10-monarch-hardening.conf"
grep -qxF 'PasswordAuthentication no' "$reconciled" ||
  fail "reconciliation did not install key-only policy"
grep -qxF 'sudo systemctl reload sshd.service' "$test_tmp/legacy-server.calls" ||
  fail "reconciliation did not reload the hardened daemon"
pass "SSH reconciliation hardens a marked legacy server with a usable key"

prepare_runtime already-hardened
already="$test_tmp/already-hardened/root/etc/ssh/sshd_config.d/10-monarch-hardening.conf"
printf '%s\n' \
  '# Managed by Monarch.' \
  'PasswordAuthentication no' \
  'KbdInteractiveAuthentication no' >"$already"
run_reconcile already-hardened valid 0 >/dev/null
! grep -qF 'systemctl reload sshd.service' "$test_tmp/already-hardened.calls" ||
  fail "reconciliation reloaded an already-effective policy"
pass "SSH reconciliation is idempotent"

for failure in CHOWN CHMOD; do
  scenario="existing-${failure,,}-failure"
  prepare_runtime "$scenario"
  existing_failure="$test_tmp/$scenario/root/etc/ssh/sshd_config.d/10-monarch-hardening.conf"
  printf '%s\n' \
    '# Managed by Monarch.' \
    'PasswordAuthentication no' \
    'KbdInteractiveAuthentication no' >"$existing_failure"
  if [[ $failure == "CHOWN" ]]; then
    if FAIL_CONFIG_CHOWN=1 run_setup "$scenario" >"$test_tmp/$scenario.output" 2>&1; then
      fail "SSH setup masked a failed configuration chown"
    fi
  elif FAIL_CONFIG_CHMOD=1 run_setup "$scenario" >"$test_tmp/$scenario.output" 2>&1; then
    fail "SSH setup masked a failed configuration chmod"
  fi
done
pass "SSH setup propagates managed configuration ownership failures"
