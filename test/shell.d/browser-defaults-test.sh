#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
launch_log="$test_tmp/launch"
mkdir -p "$mock_bin" "$test_home/.local/share/applications" "$test_home/.config"

cat >"$mock_bin/xdg-settings" <<'EOF'
#!/bin/bash
[[ -z ${BROWSER:-} ]] || printf '%s\n' "$BROWSER" >"$TEST_BROWSER_LEAK"
printf '%s\n' "${TEST_SETTINGS_BROWSER:-}"
EOF
cat >"$mock_bin/xdg-mime" <<'EOF'
#!/bin/bash
[[ $* == "query default x-scheme-handler/https" ]] || exit 1
printf '%s\n' "${TEST_MIME_BROWSER:-}"
EOF
cat >"$mock_bin/setsid" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_LAUNCH_LOG"
EOF
cat >"$mock_bin/chromium" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$mock_bin/google-chrome-stable" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$mock_bin"/*

cat >"$test_home/.local/share/applications/chromium.desktop" <<'EOF'
[Desktop Entry]
Exec=chromium %U
EOF
cat >"$test_home/.local/share/applications/google-chrome.desktop" <<'EOF'
[Desktop Entry]
Exec=google-chrome-stable %U
EOF
cat >"$test_home/.local/share/applications/broken.desktop" <<'EOF'
[Desktop Entry]
Exec=missing-browser %U
EOF

run_launcher() {
  HOME="$test_home" PATH="$mock_bin:/usr/bin" MONARCH_PATH="$ROOT" \
    TEST_BROWSER_LEAK="$test_tmp/browser-leak" TEST_LAUNCH_LOG="$launch_log" \
    TEST_SETTINGS_BROWSER="${TEST_SETTINGS_BROWSER:-}" \
    TEST_MIME_BROWSER="${TEST_MIME_BROWSER:-}" BROWSER=monarch-launch-browser \
    bash "$ROOT/bin/$1" "${@:2}"
}

TEST_SETTINGS_BROWSER=""
TEST_MIME_BROWSER=chromium.desktop
run_launcher monarch-launch-browser --private https://example.test
[[ ! -e $test_tmp/browser-leak ]] || fail "BROWSER reached xdg-settings"
grep -qxF 'chromium' "$launch_log" || fail "HTTPS MIME fallback did not launch Chromium"
grep -qxF -- '--incognito' "$launch_log" || fail "private mode was not translated"
grep -qxF 'https://example.test' "$launch_log" || fail "browser URL was not preserved"
pass "browser launch falls back to the HTTPS MIME handler without recursive BROWSER state"

TEST_MIME_BROWSER=google-chrome.desktop
run_launcher monarch-launch-webapp https://app.example.test --class=test
grep -qxF 'google-chrome-stable' "$launch_log" || fail "web app ignored the HTTPS MIME fallback"
grep -qxF -- '--app=https://app.example.test' "$launch_log" || fail "web-app URL was not preserved"
grep -qxF -- '--class=test' "$launch_log" || fail "web-app arguments were not preserved"
pass "web-app launch shares the default-browser fallback"

TEST_SETTINGS_BROWSER=broken.desktop
TEST_MIME_BROWSER=chromium.desktop
if run_launcher monarch-launch-browser https://example.test >"$test_tmp/error" 2>&1; then
  fail "browser launch accepted a missing Exec command"
fi
grep -qF "has no usable desktop launcher" "$test_tmp/error" ||
  fail "browser launch did not explain the invalid desktop launcher"
pass "browser launch rejects unusable desktop Exec commands"

printf '%s' '--ozone-platform=wayland' >"$test_home/.config/chromium-flags.conf"
printf '%s\n' '--enable-features=Test' >"$test_home/.config/brave-flags.conf"
printf '%s\n' '--password-store=basic' >"$test_home/.config/chrome-flags.conf"
printf '%s\n' '  --password-store gnome-libsecret' >"$test_home/.config/microsoft-edge-stable-flags.conf"

HOME="$test_home" bash "$ROOT/install/reconcile/chromium-flags.sh"
HOME="$test_home" bash "$ROOT/install/reconcile/chromium-flags.sh"

[[ $(grep -cFx -- '--password-store=gnome-libsecret' "$test_home/.config/chromium-flags.conf") == 1 ]] ||
  fail "Chromium backend was not reconciled exactly once"
[[ $(grep -cFx -- '--password-store=gnome-libsecret' "$test_home/.config/brave-flags.conf") == 1 ]] ||
  fail "Brave backend was not reconciled exactly once"
[[ $(cat "$test_home/.config/chrome-flags.conf") == '--password-store=basic' ]] ||
  fail "an explicit Chrome backend was replaced"
[[ $(cat "$test_home/.config/microsoft-edge-stable-flags.conf") == '  --password-store gnome-libsecret' ]] ||
  fail "an explicit Edge backend was replaced"
[[ ! -e $test_home/.config/unknown-flags.conf ]]
grep -qFx -- '--password-store=gnome-libsecret' "$ROOT/config/chromium-flags.conf" ||
  fail "new Chromium profiles do not pin the secret backend"
pass "Chromium-family flags converge without overriding explicit backends"
