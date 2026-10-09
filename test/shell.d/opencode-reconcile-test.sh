#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"
REAL_MISE=$(type -P mise)
export REAL_MISE
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export PATH="$test_tmp/bin:$ROOT/bin:/usr/bin"
export TEST_OPENCODE_CALLS="$test_tmp/calls"

cat >"$test_tmp/bin/mise" <<'EOF'
#!/bin/bash
[[ $1 != "unuse" || ${TEST_UNUSE_STATUS:-0} == 0 ]] || exit "$TEST_UNUSE_STATUS"
exec env -i HOME="$HOME" USER="$USER" PATH=/usr/bin \
  MISE_GLOBAL_CONFIG_FILE="$MISE_CONFIG_DIR/config.toml" \
  MISE_CONFIG_DIR="$MISE_CONFIG_DIR" MISE_DATA_DIR="$MISE_DATA_DIR" \
  MISE_CACHE_DIR="$MISE_CACHE_DIR" MISE_STATE_DIR="$MISE_STATE_DIR" \
  "$REAL_MISE" -C "$HOME" "$@"
EOF
cat >"$test_tmp/bin/monarch-pkg-add" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_OPENCODE_CALLS"
[[ ${TEST_PACKAGE_STATUS:-0} == 0 ]] || exit "$TEST_PACKAGE_STATUS"
touch "$HOME/arch-opencode"
EOF
cat >"$test_tmp/bin/monarch-pkg-missing" <<'EOF'
#!/bin/bash
[[ ! -f $HOME/arch-opencode ]]
EOF
chmod +x "$test_tmp/bin/"*

prepare_home() {
  export HOME="$test_tmp/$1"
  export MISE_CONFIG_DIR="$HOME/.config/mise" MISE_DATA_DIR="$HOME/.local/share/mise"
  export MISE_CACHE_DIR="$HOME/.cache/mise" MISE_STATE_DIR="$HOME/.local/state/mise"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export XDG_CACHE_HOME="$HOME/.cache" XDG_STATE_HOME="$HOME/.local/state"
  mkdir -p "$MISE_CONFIG_DIR"
  : >"$TEST_OPENCODE_CALLS"
}

system_reconcile() {
  /bin/bash -euc '
    sudo() { :; }
    bash() { :; }
    export MONARCH_PATH=$1
    source "$1/install/reconcile/system.sh"
  ' bash "$ROOT" >/dev/null
}

user_reconcile() {
  /bin/bash -euc 'source "$1/install/reconcile/mise.sh"' bash "$ROOT" >/dev/null
}

prepare_home absent
system_reconcile
user_reconcile
[[ ! -s $TEST_OPENCODE_CALLS && ! -e $HOME/.local/bin/opencode ]] || fail "reconciliation installed OpenCode by default"

prepare_home unused
"$ROOT/bin/monarch-mise-install" opencode
printf '%s\n' '[tools]' 'opencode = "1.18.35"' >"$MISE_CONFIG_DIR/config.toml"
system_reconcile
user_reconcile
[[ ! -s $TEST_OPENCODE_CALLS && ! -e $HOME/.local/bin/opencode ]] || fail "an unused wrapper or missing version triggered installation"
pass "neither an absent tool, an unused wrapper, nor an uninstalled mise request installs OpenCode"

prepare_home installed
"$ROOT/bin/monarch-mise-install" opencode
printf '%s\n' '[tools]' 'opencode = "1.18.35"' >"$MISE_CONFIG_DIR/config.toml"
mkdir -p "$MISE_DATA_DIR/installs/opencode/1.18.35" "$HOME/.config/monarch/defaults"
touch "$MISE_DATA_DIR/installs/opencode/1.18.35/opencode"
printf '%s\n' opencode >"$HOME/.config/monarch/defaults/agent"
if TEST_PACKAGE_STATUS=23 system_reconcile; then
  fail "a failed Arch installation returned success"
fi
if user_reconcile 2>/dev/null; then
  fail "mise retirement proceeded without the Arch replacement"
fi
[[ -f $HOME/.local/bin/opencode ]] || fail "a failed migration removed the old wrapper"
mise ls --global --installed --json opencode | jq -e 'length > 0' >/dev/null
system_reconcile
if TEST_UNUSE_STATUS=23 user_reconcile; then
  fail "a failed mise retirement returned success"
fi
[[ -f $HOME/.local/bin/opencode ]] || fail "a failed mise retirement removed the wrapper"
user_reconcile
[[ -f $HOME/arch-opencode && ! -e $HOME/.local/bin/opencode ]] || fail "migration did not replace mise with Arch"
[[ -f $MISE_DATA_DIR/installs/opencode/1.18.35/opencode ]] || fail "migration pruned a running session's installation"
[[ $(<"$HOME/.config/monarch/defaults/agent") == "opencode" ]] || fail "migration changed the default agent"
rm "$HOME/arch-opencode"
: >"$TEST_OPENCODE_CALLS"
system_reconcile
user_reconcile
[[ ! -s $TEST_OPENCODE_CALLS ]] || fail "a retired mise cache reinstalled a removed Arch package"
pass "an installed global mise version migrates safely, preserves running sessions, and is not restored from cache"

prepare_home custom
mkdir -p "$HOME/.local/bin"
printf '%s\n' '#!/bin/bash' 'echo custom-opencode' >"$HOME/.local/bin/opencode"
user_reconcile
grep -qx 'echo custom-opencode' "$HOME/.local/bin/opencode" || fail "a custom command was removed"
rm "$HOME/.local/bin/opencode"
ln -s /missing/user-opencode "$HOME/.local/bin/opencode"
user_reconcile
[[ -L $HOME/.local/bin/opencode ]] || fail "a user symlink was removed"
pass "custom commands and symlinks remain user-owned"
