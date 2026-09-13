#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

policy="$ROOT/default/chromium/policies.json"
[[ -f $policy ]] || fail "Chromium translation policy is missing"
jq -e '.TranslateEnabled == false and (keys == ["TranslateEnabled"])' "$policy" >/dev/null ||
  fail "Chromium translation policy does not disable built-in translation"
! grep -qFx -- '--disable-features=Translate' "$ROOT/config/chromium-flags.conf" ||
  fail "the obsolete Translate feature flag is still shipped"

grep -qF 'browser_policy_setup_chromium /etc/chromium/policies/managed' \
  "$ROOT/install/config/browser-policy.sh" || fail "fresh installs do not publish the policy"
grep -qF 'browser_policy_setup_chromium "$dir"' \
  "$ROOT/install/reconcile/browser-policy.sh" || fail "existing browsers do not reconcile the policy"
grep -qF 'browser_policy_setup_chromium "$1"' \
  "$ROOT/bin/monarch-install-browser" || fail "optional browsers do not receive the policy"
grep -qF 'as_root install -m 0644 -o root -g root -T "$policies" "$dir/monarch.json"' \
  "$ROOT/install/helpers/browser-policy.sh" || fail "the policy is not published root-owned"
pass "Chromium-family browsers receive the managed translation policy"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/home/.config"
printf '%s\n' '--disable-features=Translate' '--enable-features=Test' \
  >"$test_tmp/home/.config/chromium-flags.conf"
printf '%s\n' '--disable-features=Translate,Other' \
  >"$test_tmp/home/.config/brave-flags.conf"

HOME="$test_tmp/home" bash "$ROOT/install/reconcile/chromium-flags.sh"
HOME="$test_tmp/home" bash "$ROOT/install/reconcile/chromium-flags.sh"

! grep -qFx -- '--disable-features=Translate' "$test_tmp/home/.config/chromium-flags.conf" ||
  fail "the obsolete standalone flag survived reconciliation"
grep -qFx -- '--enable-features=Test' "$test_tmp/home/.config/chromium-flags.conf" ||
  fail "reconciliation removed an unrelated flag"
grep -qFx -- '--disable-features=Translate,Other' "$test_tmp/home/.config/brave-flags.conf" ||
  fail "reconciliation changed a combined user flag"
[[ $(grep -cFx -- '--password-store=gnome-libsecret' "$test_tmp/home/.config/chromium-flags.conf") == 1 ]] ||
  fail "password-store reconciliation stopped being idempotent"
pass "existing flag files drop only Monarch's obsolete standalone flag"
