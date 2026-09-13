#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
stub_bin="$test_dir/bin"
sudo_calls="$test_dir/sudo-calls"
gum_calls="$test_dir/gum-calls"
reboot_called="$test_dir/reboot-called"
mkdir -p "$home" "$stub_bin"

cat >"$stub_bin/id" <<'STUB'
#!/bin/bash
if [[ $1 == -nG ]]; then
  printf '%s\n' "${STUB_GROUPS:-wheel}"
else
  /usr/bin/id "$@"
fi
STUB

cat >"$stub_bin/getent" <<'STUB'
#!/bin/bash
[[ $1 == group && $2 == docker ]]
STUB

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"${SUDO_CALLS:?}"
STUB

cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"${GUM_CALLS:?}"
case "$*" in
  *"Enable sudoless Docker"*) exit "${ENABLE_ANSWER:-0}" ;;
  *"Reboot now"*) exit "${REBOOT_ANSWER:-1}" ;;
esac
exit 1
STUB

cat >"$stub_bin/monarch-system-reboot" <<'STUB'
#!/bin/bash
touch "${REBOOT_CALLED:?}"
STUB

chmod +x "$stub_bin"/*

setup="$ROOT/bin/monarch-setup-security-sudoless-docker"
remove="$ROOT/bin/monarch-remove-security-sudoless-docker"
state="$home/.local/state/monarch/reboot-required"

run_toggle() {
  rm -f "$sudo_calls" "$gum_calls" "$reboot_called" "$state"
  local deferred=()
  [[ ${5:-false} == true ]] && deferred=(MONARCH_DEFER_REBOOT=1)
  env HOME="$home" PATH="$stub_bin:$ROOT/bin:$PATH" STUB_GROUPS="$2" \
    ENABLE_ANSWER="$3" REBOOT_ANSWER="$4" SUDO_CALLS="$sudo_calls" \
    GUM_CALLS="$gum_calls" REBOOT_CALLED="$reboot_called" \
    "${deferred[@]}" "$1" >/dev/null
}

run_toggle "$setup" wheel 1 1
[[ ! -e $sudo_calls && ! -e $state ]] || fail "declined setup changed Docker access"
grep -qF 'Enable sudoless Docker' "$gum_calls" || fail "setup omitted the root-equivalence warning"
pass "declining sudoless Docker leaves the account unchanged"

run_toggle "$setup" wheel 0 1
account=$(/usr/bin/id -un)
grep -qxF "/usr/bin/usermod -aG docker $account" "$sudo_calls" || fail "setup did not add the current account"
[[ -f $state && ! -e $reboot_called ]] || fail "setup did not retain a declined reboot"
pass "setup grants persistent access only after warning and records the reboot"

run_toggle "$setup" wheel 0 0
[[ -e $reboot_called ]] || fail "setup did not honor reboot confirmation"
pass "setup can apply the group change immediately through reboot"

run_toggle "$setup" "wheel docker" 0 0
[[ ! -e $sudo_calls && ! -e $gum_calls && ! -e $state ]] || fail "setup changed an already configured account"
pass "setup is idempotent when persistent access is already enabled"

run_toggle "$remove" "wheel docker" 0 0
grep -qxF "/usr/bin/gpasswd -d $account docker" "$sudo_calls" || fail "removal did not revoke the current account"
[[ -f $state && -e $reboot_called ]] || fail "removal did not apply its recorded reboot"
pass "removal revokes persistent access and records the reboot"

run_toggle "$remove" wheel 0 0
[[ ! -e $sudo_calls && ! -e $gum_calls && ! -e $state ]] || fail "removal changed an account outside docker"
pass "removal is idempotent when persistent access is disabled"

run_toggle "$remove" "wheel docker" 0 0 true
[[ -f $state && ! -e $gum_calls && ! -e $reboot_called ]] || fail "deferred removal prompted or lost reboot state"
pass "deferred callers can revoke access without interrupting their workflow"

tree=$(PATH="$ROOT/bin:$PATH" "$ROOT/bin/monarch-menu" --tree)
setup_row=$(jq -r '.[] | select(.id == "setup.security.sudoless-docker") | [.when, .action] | @tsv' <<<"$tree")
[[ $setup_row == $'monarch-sudo-docker --configured\tmonarch-launch-floating-terminal-with-presentation monarch-setup-security-sudoless-docker' ]] ||
  fail "the setup menu does not expose the safe state transition"
remove_row=$(jq -r '.[] | select(.id == "remove.security.sudoless-docker") | [.when, .action] | @tsv' <<<"$tree")
[[ $remove_row == $'! monarch-sudo-docker --configured\tmonarch-launch-floating-terminal-with-presentation monarch-remove-security-sudoless-docker' ]] ||
  fail "the removal menu does not expose the configured state transition"
pass "the menu exposes only the applicable persistent Docker transition"
