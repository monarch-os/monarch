#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

runtime="$test_tmp/runtime"
mkdir -p "$runtime/bin"
ln -s "$ROOT/install" "$runtime/install"
ln -s "$ROOT/default" "$runtime/default"

for command in monarch-provision-first-run monarch-provision-user monarch-done monarch-hook-install; do
  ln -s "$ROOT/bin/$command" "$runtime/bin/$command"
done

for command in monarch-refresh-niri monarch-refresh-noctalia monarch-refresh-applications \
  monarch-theme-apply monarch-mise-install monarch-notification-wait monarch-notification-send \
  xdg-user-dirs-update xdg-settings xdg-mime update-desktop-database git mise \
  systemctl noctalia gsettings nm-online pactl; do
  cat >"$runtime/bin/$command" <<'EOF'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$TEST_PROVISION_LOG"
[[ ${0##*/} != "${TEST_PROVISION_FAIL:-}" ]] || exit 42
EOF
done

for command in monarch-hw-asus-rog monarch-hw-match monarch-battery-present; do
  printf '#!/bin/bash\nexit 1\n' >"$runtime/bin/$command"
done
chmod +x "$runtime/bin/"*

run_for_user() {
  local user_home="$1"
  shift

  env HOME="$user_home" MONARCH_PATH="$runtime" MONARCH_INSTALL="$runtime/install" \
    MONARCH_USER_NAME='Existing User' MONARCH_USER_EMAIL='user@example.invalid' \
    MONARCH_SETUP_CONTEXT=runtime MONARCH_INSTALL_LOG_FILE='' \
    TEST_PROVISION_LOG="$user_home/calls" PATH="$runtime/bin:/usr/bin" \
    bash "$@"
}

seed_customizations() {
  local user_home="$1"

  mkdir -p "$user_home/.local/share/keyrings" "$user_home/Work" "$user_home/.config/niri"
  printf '%s\n' '[keyring]' 'display-name=Existing keyring' '[1]' 'secret=existing-secret' \
    >"$user_home/.local/share/keyrings/Default_keyring.keyring"
  printf '%s\n' Login >"$user_home/.local/share/keyrings/default"
  printf '%s\n' 'include "/custom/compose"' >"$user_home/.XCompose"
  printf '%s\n' '[tools]' 'node = "22"' >"$user_home/Work/.mise.toml"
  printf '%s\n' 'input { keyboard { xkb { layout "de"; }; }; }' >"$user_home/.config/niri/keyboard.kdl"
  mkdir -p "$user_home/expected"
  cp "$user_home/.local/share/keyrings/Default_keyring.keyring" "$user_home/expected/keyring"
  cp "$user_home/.local/share/keyrings/default" "$user_home/expected/default"
  cp "$user_home/.XCompose" "$user_home/expected/compose"
  cp "$user_home/Work/.mise.toml" "$user_home/expected/mise"
  cp "$user_home/.config/niri/keyboard.kdl" "$user_home/expected/keyboard"
}

assert_customizations() {
  local user_home="$1"

  cmp -s "$user_home/expected/keyring" "$user_home/.local/share/keyrings/Default_keyring.keyring" ||
    fail "existing keyring survives provisioning"
  cmp -s "$user_home/expected/default" "$user_home/.local/share/keyrings/default" ||
    fail "existing default keyring selection survives provisioning"
  cmp -s "$user_home/expected/compose" "$user_home/.XCompose" || fail "custom XCompose survives provisioning"
  cmp -s "$user_home/expected/mise" "$user_home/Work/.mise.toml" || fail "custom Work tools survive provisioning"
  cmp -s "$user_home/expected/keyboard" "$user_home/.config/niri/keyboard.kdl" || fail "custom keyboard survives provisioning"
  if grep -Eq '^(xdg-mime|xdg-settings|xdg-user-dirs-update|mise) ' "$user_home/calls"; then
    fail "existing-user provisioning does not reset associations, directories or tools"
  fi
}

case ${1:-all} in
  all | v4)
    for source_state in v4 v4-login transitioning packaged; do
      user_home="$test_tmp/$source_state"
      seed_customizations "$user_home"
      case $source_state in
        v4 | v4-login)
          mkdir -p "$user_home/.local/state/monarch/migrations"
          touch "$user_home/.local/state/monarch/migrations/1787067946.sh"
          ;;
        transitioning)
          mkdir -p "$user_home/.local/state/monarch/reconcile/1-to-2"
          touch "$user_home/.local/state/monarch/reconcile/1-to-2/legacy-noctalia"
          ;;
        packaged)
          mkdir -p "$user_home/.local/state/monarch"
          printf '%s\n' 2 >"$user_home/.local/state/monarch/schema"
          ;;
      esac
      if [[ $source_state == "v4" ]]; then
        run_for_user "$user_home" "$ROOT/install/reconcile/schema/1-to-2/provision-noctalia.sh" >/dev/null
      else
        run_for_user "$user_home" "$ROOT/bin/monarch-provision-first-run" >/dev/null
      fi
      assert_customizations "$user_home"
      [[ -f $user_home/.local/state/monarch/done/finalize-user ]] || fail "existing user finalization is recorded"
      [[ -f $user_home/.local/state/monarch/done/first-run-user ]] || fail "existing user session setup completes"
      [[ -L $user_home/.agents/skills/monarch ]] || fail "existing users receive packaged skill links"
      grep -qF 'noctalia msg plugins enable monarch/menu' "$user_home/calls" || fail "existing users receive the V5 menu"
      grep -qF 'monarch-obsidian-theme.path' "$user_home/calls" || fail "existing users receive V5 user units"
      run_for_user "$user_home" "$ROOT/bin/monarch-provision-first-run" --force >/dev/null
      assert_customizations "$user_home"
      pass "$source_state users retain their data through migration and forced session retries"
    done
    ;;
esac

case ${1:-all} in
  all | stale)
    user_home="$test_tmp/stale"
    seed_customizations "$user_home"
    mkdir -p "$user_home/.local/state/monarch/done"
    printf '%s\n' 2 >"$user_home/.local/state/monarch/schema"
    touch "$user_home/.local/state/monarch/done/first-run-user"
    run_for_user "$user_home" "$ROOT/bin/monarch-provision-first-run" >/dev/null
    [[ -f $user_home/.local/state/monarch/done/finalize-user ]] || fail "a stale first-run marker cannot hide unfinished user provisioning"
    assert_customizations "$user_home"
    pass "a stale first-run marker cannot hide unfinished user provisioning"
    ;;
esac

case ${1:-all} in
  all | retry)
    user_home="$test_tmp/retry"
    mkdir -p "$user_home"
    if TEST_PROVISION_FAIL=monarch-mise-install run_for_user "$user_home" \
      "$ROOT/bin/monarch-provision-first-run" >/dev/null; then
      fail "first-run reports a failed user provisioning step"
    fi
    [[ ! -e $user_home/.local/state/monarch/done/finalize-user ]] || fail "failed provisioning stays pending"
    [[ ! -e $user_home/.local/state/monarch/done/first-run-user ]] || fail "failed first-run stays pending"
    grep -qF 'exit code: 42' "$user_home/.local/state/monarch/first-run.log" || fail "first-run logs provisioning failure"
    grep -qF 'noctalia msg plugins enable monarch/menu' "$user_home/calls" || fail "session setup continues after provisioning failure"
    printf '%s\n' '[keyring]' '[1]' 'secret=added-before-retry' >"$user_home/.local/share/keyrings/Default_keyring.keyring"
    printf '%s\n' Login >"$user_home/.local/share/keyrings/default"
    run_for_user "$user_home" "$ROOT/bin/monarch-provision-first-run" >/dev/null
    [[ -f $user_home/.local/state/monarch/done/finalize-user ]] || fail "next login retries user provisioning"
    [[ -f $user_home/.local/state/monarch/done/first-run-user ]] || fail "successful retry completes first-run"
    grep -qF 'secret=added-before-retry' "$user_home/.local/share/keyrings/Default_keyring.keyring" || fail "initial-install retry preserves existing secrets"
    [[ $(<"$user_home/.local/share/keyrings/default") == Login ]] || fail "initial-install retry preserves the selected keyring"
    pass "failed provisioning retries next login and preserves secrets added before the retry"
    ;;
esac

case ${1:-all} in
  all | fresh)
    user_home="$test_tmp/fresh"
    mkdir -p "$user_home"
    run_for_user "$user_home" "$ROOT/bin/monarch-provision-first-run" >/dev/null
    [[ -f $user_home/.local/state/monarch/done/finalize-user ]] || fail "new users finish provisioning"
    [[ -f $user_home/.local/state/monarch/done/first-run-user ]] || fail "new users finish session setup"
    [[ $(<"$user_home/.local/share/keyrings/default") == Default_keyring ]] || fail "new users receive the initial keyring"
    [[ -f $user_home/.XCompose && -f $user_home/Work/.mise.toml ]] || fail "new users receive initial config"
    grep -qF 'xdg-settings set default-web-browser firefox.desktop' "$user_home/calls" || fail "new users receive MIME defaults"
    grep -qF 'mise use -g node@latest' "$user_home/calls" || fail "new users receive their Node setup"
    cp "$user_home/calls" "$user_home/expected-calls"
    run_for_user "$user_home" "$ROOT/bin/monarch-provision-first-run" >/dev/null
    cmp -s "$user_home/calls" "$user_home/expected-calls" || fail "successful first-run is not repeated"
    pass "new users still receive initial defaults, tools and session integrations exactly once"
    ;;
esac
