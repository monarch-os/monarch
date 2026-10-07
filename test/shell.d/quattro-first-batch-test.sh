#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export HOME="$test_tmp/home" PATH="$test_tmp/bin:$ROOT/bin:/usr/bin"
export CALL_LOG="$test_tmp/calls"
mkdir -p "$HOME/.config/uwsm" "$test_tmp/bin"

cat >"$test_tmp/bin/sudo" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$CALL_LOG"
[[ ${FAIL_CALL:-} != "$*" ]]
STUB
cat >"$test_tmp/bin/monarch-pkg-missing" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$test_tmp/bin/monarch-pkg-add" <<'STUB'
#!/bin/bash
printf 'pkg %s\n' "$*" >>"$CALL_LOG"
[[ ${FAIL_CALL:-} != "pkg $*" ]]
STUB
cat >"$test_tmp/bin/monarch-install-gaming-gpu-lib32" <<'STUB'
#!/bin/bash
printf '%s\n' drivers >>"$CALL_LOG"
exit "${DRIVER_STATUS:-0}"
STUB
for command in notify-send setsid; do
  printf '#!/bin/bash\nexit 0\n' >"$test_tmp/bin/$command"
done
chmod +x "$test_tmp/bin/"*

key=519BC3D5AEA652C94F89F0AAC13B3766D969CE82
for failed_call in \
  "pacman-key --recv-keys $key --keyserver keys.openpgp.org" \
  "pacman-key --lsign-key $key" 'pacman -Sy' 'pkg monarch-keyring' \
  "pacman-key --list-keys $key" 'pacman -Sy --noconfirm archlinux-keyring' \
  'pacman -Sy --noconfirm cachyos-keyring'; do
  if FAIL_CALL="$failed_call" "$ROOT/bin/monarch-update-keyring" >"$test_tmp/output" 2>&1; then
    fail "a failed signing key repair reports success" "$failed_call"
  fi
  ! grep -q 'Keys are correct' "$test_tmp/output" || fail "a failed signing key repair prints success"
done
"$ROOT/bin/monarch-update-keyring" >"$test_tmp/output" 2>&1
grep -q 'Keys are correct' "$test_tmp/output" || fail "a successful signing key repair reports failure"
pass "keyring repair stops on bootstrap, installation and verification failures"

: >"$CALL_LOG"
"$ROOT/bin/monarch-install-gaming-steam" >/dev/null
[[ $(<"$CALL_LOG") == $'drivers\npkg steam' ]] || fail "Steam installs before its graphics provider"
: >"$CALL_LOG"
if DRIVER_STATUS=1 "$ROOT/bin/monarch-install-gaming-steam" >/dev/null; then
  fail "Steam continues after graphics setup fails"
fi
[[ $(<"$CALL_LOG") == drivers ]] || fail "Steam starts package installation after failed graphics setup"
pass "Steam selects graphics libraries first and stops on failure"

printf '#!/bin/bash\nprintf ran >>"$CALL_LOG"\n' >"$test_tmp/hook"
for name in '' . .. ../outside nested/name; do
  if "$ROOT/bin/monarch-hook-install" "$name" "$test_tmp/hook" >/dev/null 2>&1; then
    fail "hook installation accepts an invalid name" "$name"
  fi
  if "$ROOT/bin/monarch-hook" "$name" >/dev/null 2>&1; then
    fail "hook execution accepts an invalid name" "$name"
  fi
  if "$ROOT/bin/monarch-state" set "$name" >/dev/null 2>&1; then
    fail "state creation accepts an invalid name" "$name"
  fi
done
[[ ! -e $HOME/.config/monarch/hooks && ! -e $HOME/.local/state/monarch ]] ||
  fail "rejected names create directories"
"$ROOT/bin/monarch-hook-install" post-update "$test_tmp/hook" >/dev/null
: >"$CALL_LOG"
"$ROOT/bin/monarch-hook" post-update
[[ $(<"$CALL_LOG") == ran ]] || fail "valid hooks no longer execute"
"$ROOT/bin/monarch-state" set reboot-required
"$ROOT/bin/monarch-state" set logout-required
"$ROOT/bin/monarch-state" clear 're*-required'
[[ ! -e $HOME/.local/state/monarch/reboot-required && -f $HOME/.local/state/monarch/logout-required ]] ||
  fail "state clearing no longer supports patterns"
pass "hooks and state reject traversal while preserving valid hooks and patterns"

printf '%s\n' 'export EDITOR=sublime_text' >"$HOME/.config/uwsm/default"
[[ $("$ROOT/bin/monarch-default-editor") == subl ]] || fail "legacy Sublime selection is not normalized"
"$ROOT/bin/monarch-default-editor" sublime_text
[[ $(<"$HOME/.config/uwsm/default") == 'export EDITOR=subl' ]] || fail "Sublime uses the wrong executable"
pass "Sublime selections keep compatibility and use subl"
