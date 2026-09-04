#!/bin/bash

# Exercises the menu's data layer — loading, the user overlay, route resolution
# and guards — through monarch-menu's inspection modes, so none of it needs a
# compositor or a picker.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
MENU="$ROOT/bin/monarch-menu"
TMPDIR=""

export PATH="$ROOT/bin:$PATH"
export MONARCH_PATH="$ROOT"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_equals() {
  local description="$1" actual="$2" expected="$3"

  if [[ $actual != "$expected" ]]; then
    printf 'Expected: %s\n' "$expected" >&2
    printf 'Actual:   %s\n' "$actual" >&2
    fail "$description"
  fi

  pass "$description"
}

assert_contains() {
  local description="$1" haystack="$2" needle="$3"

  if [[ $haystack != *"$needle"* ]]; then
    printf 'Expected output to contain: %s\n' "$needle" >&2
    printf 'Actual output:\n%s\n' "$haystack" >&2
    fail "$description"
  fi

  pass "$description"
}

refute_contains() {
  local description="$1" haystack="$2" needle="$3"

  if [[ $haystack == *"$needle"* ]]; then
    printf 'Expected output NOT to contain: %s\n' "$needle" >&2
    printf 'Actual output:\n%s\n' "$haystack" >&2
    fail "$description"
  fi

  pass "$description"
}

TMPDIR=$(mktemp -d)
cleanup() {
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

# The user overlay lives under $HOME, so every case that exercises it runs with
# HOME pointed at a scratch directory.
export HOME="$TMPDIR/home"
mkdir -p "$HOME/.config/monarch/extensions"
USER_MENU="$HOME/.config/monarch/extensions/monarch-menu.jsonc"
SHIPPED_TREE=$("$MENU" --tree)

# ── The shipped data ─────────────────────────────────────────────────────────

output=$("$MENU" --check)
assert_contains "shipped menu data passes its own check" "$output" "Menu data check passed"

output=$("$MENU" --rows "" | cut -f1 | tr '\n' ' ')
assert_equals "root holds the eight top-level families in declaration order" \
  "${output% }" "apps trigger setup style install update system learn"

# A guard-free level, deliberately: trigger.share hides its Wi-Fi row on a
# machine with no wireless connection, which would make this assertion depend on
# the host it runs on.
output=$("$MENU" --rows style.screensaver | cut -f2 | tr '\n' ' ')
assert_equals "a level renders its own children only" "${output% }" "Edit Text Set From Image Restore Default"

output=$(jq -r '.[] | select(.id | test("^style\\.bar\\.position\\.[^.]+$")) | [.label, .checked, .action] | join("|")' <<<"$SHIPPED_TREE")
assert_equals "bar position exposes four stateful choices" "$output" \
  $'Top|[[ $(monarch-bar-position) == top ]]|monarch-bar-position top\nBottom|[[ $(monarch-bar-position) == bottom ]]|monarch-bar-position bottom\nLeft|[[ $(monarch-bar-position) == left ]]|monarch-bar-position left\nRight|[[ $(monarch-bar-position) == right ]]|monarch-bar-position right'

output=$(jq -r '.[] | select(.id == "style.backgrounds") | .action' <<<"$SHIPPED_TREE")
assert_equals "Backgrounds opens the Monarch selector directly" "$output" "noctalia msg panel-toggle monarch/theme:background"

output=$(jq -r '.[0] | [.id, .label] | join("|")' <<<"$SHIPPED_TREE")
assert_equals "--tree exposes menu data without guards" "$output" "apps|Apps"

output=$("$MENU" --initial style.backgrounds | jq -r 'map(.id) | join(" ")')
assert_equals "--initial limits data to the requested level" "$output" \
  "style style.backgrounds"

if ! grep -q 'onImportClicked() importBackground()' "$ROOT/default/noctalia/plugins/monarch-theme/background.luau" ||
  ! grep -q 'ctrl+i.*importBackground' "$ROOT/default/noctalia/plugins/monarch-theme/background.luau"; then
  echo "Background selector does not expose import from pointer and keyboard" >&2
  exit 1
fi
echo "ok - Background selector exposes import from pointer and keyboard"

output=$(jq -r '.[] | select(.id | test("^setup\\.network\\.dns\\.[^.]+$")) | .label' <<<"$SHIPPED_TREE" | tr '\n' ' ')
assert_equals "DNS exposes each provider directly" "${output% }" "DHCP Cloudflare Google Custom"

output=$(jq -r '.[] | select(.id | test("^setup\\.network\\.dns\\.[^.]+$")) | .action' <<<"$SHIPPED_TREE" | tr '\n' ' ')
assert_contains "DNS provider rows bypass the old chooser" "$output" "/usr/bin/monarch-dns Cloudflare"

output=$("$MENU" --rows setup.network | cut -f2 | tr '\n' ' ')
assert_equals "network groups overview, Wi-Fi and DNS" "${output% }" "Overview Wi-Fi DNS"

output=$(jq -r '.[] | select(.id | test("^setup\\.defaults\\.agent\\.[^.]+$")) | .label' <<<"$SHIPPED_TREE" | tr '\n' ' ')
assert_equals "default agents follow Monarch's supported catalog" "${output% }" \
  "Antigravity Claude Codex Copilot Crush Grok omp OpenCode Ori Pi"

output=$(jq -r '.[] | select(.id == "setup.plugins") | .action' <<<"$SHIPPED_TREE")
assert_equals "plugin setup opens Noctalia's native plugin manager" "$output" \
  "noctalia msg settings-open plugins"

output=$(jq -r '.[] | select(.id | test("^system\\.[^.]+$")) | .label' <<<"$SHIPPED_TREE" | tr '\n' ' ')
assert_equals "system contains only session and power actions" "${output% }" \
  "Lock Screensaver Suspend Hibernate Logout Restart Shutdown"

output=$("$MENU" --rows learn | cut -f2 | tr '\n' ' ')
assert_contains "documentation contains About" "$output" "About"

output=$("$MENU" --rows install | cut -f2 | tr '\n' ' ')
assert_contains "software links to the removal catalog" "$output" "Remove software"
assert_equals "software follows the install workflow" "${output% }" \
  "Package AUR Web App TUI Theme Browser Editor Terminal Development AI Cyber Gaming Services Fonts Windows Preinstalls Remove software"

output=$(jq -r '.[] | select(.id | test("^install\\.ai\\.[^.]+$")) | .label' <<<"$SHIPPED_TREE" | tr '\n' ' ')
assert_equals "AI follows Monarch's supported catalog" "${output% }" \
  "ChatGPT Desktop Dictation LM Studio Ollama T3 Code"
refute_contains "AI no longer lists Crush as a desktop app" "$output" "Crush"

if ! grep -q '^local WINDOW_ROWS = 10$' "$ROOT/default/noctalia/plugins/monarch-menu/panel.luau"; then
  fail "menu viewport keeps its last row above the footer"
fi
pass "menu viewport keeps its last row above the footer"

output=$(jq -r '.[] | select(.id | test("^remove\\.ai\\.[^.]+$")) | .label' <<<"$SHIPPED_TREE" | tr '\n' ' ')
assert_equals "AI removal mirrors the install catalog" "${output% }" \
  "ChatGPT Desktop Dictation LM Studio Ollama T3 Code"

output=$(jq -r '.[] | select(.id | test("^remove\\.service\\.[^.]+$")) | .label' <<<"$SHIPPED_TREE" | tr '\n' ' ')
assert_equals "specialized service removals are grouped" "${output% }" "Tailscale LazyVPN Displaylink"

output=$(jq -r '.[] | select(.id == "install.service.signal") | [.label, .disabled, .action] | join("|")' <<<"$SHIPPED_TREE")
assert_equals "Signal is available in the service catalog" "$output" \
  "Signal|monarch-pkg-present signal-desktop|monarch-launch-floating-terminal-with-presentation monarch-install-service-signal"

output=$(jq -r '.[] | select(.id == "setup.config.input") | .action' <<<"$SHIPPED_TREE")
assert_contains "input settings edit the user-owned Niri override" "$output" ".config/niri/user.kdl"
assert_contains "input settings validate and reload Niri" "$output" "monarch-refresh-niri"

assert_equals "the Input route resolves inside Config" "$("$MENU" --resolve input)" "setup.config.input"

output=$(jq -r '.[] | select(.id == "setup.security.sshd") | .checked' <<<"$SHIPPED_TREE")
assert_equals "SSH server exposes its enabled state" "$output" "systemctl is-enabled --quiet sshd"

output=$(jq -r '.[] | select(.id == "setup.security.fingerprint") | .checked' <<<"$SHIPPED_TREE")
assert_equals "fingerprint setup reflects successful enrollment" "$output" \
  '[[ -f $HOME/.local/state/monarch/fingerprint-enabled ]]'

output=$(jq -r '.[] | select(.id == "remove.security.fingerprint") | .when' <<<"$SHIPPED_TREE")
assert_equals "fingerprint removal requires configured authentication" "$output" \
  '[[ -f $HOME/.local/state/monarch/fingerprint-enabled ]]'

output=$(jq -r '.[] | select(.id == "setup.security.fido2") | .checked' <<<"$SHIPPED_TREE")
assert_equals "FIDO2 setup reflects its auth file and PAM stack" "$output" \
  '[[ -s /etc/fido2/fido2 ]] && grep -q pam_u2f.so /etc/pam.d/sudo'

output=$(jq -r '.[] | select(.id == "remove.security.fido2") | .when' <<<"$SHIPPED_TREE")
assert_equals "FIDO2 removal requires configured authentication" "$output" \
  '[[ -s /etc/fido2/fido2 ]] && grep -q pam_u2f.so /etc/pam.d/sudo'

output=$(jq '[.[] | select(.id | test("^trigger\\.toggle\\.[^.]+$")) | select(.checked)] | length' <<<"$SHIPPED_TREE")
assert_equals "every toggle exposes its active state" "$output" "9"

output=$(jq -r '.[] | select(.id == "trigger.toggle.notifications") | .checked' <<<"$SHIPPED_TREE")
assert_equals "notifications check represents active DND" "$output" \
  "monarch-toggle-notification-silencing status | jq -e '.enabled'"

output=$(jq -r '.[] | select(.id == "trigger.toggle.idle-lock") | .checked' <<<"$SHIPPED_TREE")
assert_equals "idle lock check represents active caffeine" "$output" \
  "monarch-toggle-idle status | jq -e '.enabled'"

output=$(jq -r '.[] | select(.id == "trigger.toggle.battery-percentage") | .when' <<<"$SHIPPED_TREE")
assert_equals "battery percentage uses the battery presence guard" "$output" "monarch-battery-present"

output=$(jq -r '.[] | select(.id == "trigger.capture.screenrecord.webcam") | .when' <<<"$SHIPPED_TREE")
assert_equals "webcam recording is hardware guarded" "$output" "monarch-hw-webcam"
output=$(jq -r '.[] | select(.id == "trigger.capture.screenrecord.webcam") | .action' <<<"$SHIPPED_TREE")
assert_equals "circle webcam recording is exposed" "$output" "monarch-capture-screenrecording-with-webcam --webcam-shape=circle"
output=$(jq -r '.[] | select(.id == "trigger.capture.screenrecord.webcam-rectangle") | [.when, .action] | @tsv' <<<"$SHIPPED_TREE")
assert_equals "rectangle webcam recording is exposed and guarded" "$output" $'monarch-hw-webcam\tmonarch-capture-screenrecording-with-webcam --webcam-shape=rectangle'

output=$(jq -r '.[] | select(.id == "setup.security.fingerprint") | .when' <<<"$SHIPPED_TREE")
assert_equals "fingerprint setup is hardware guarded" "$output" "monarch-hw-fingerprint"

for device in touchpad touchscreen; do
  output=$(jq -r --arg id "trigger.hardware.$device" '.[] | select(.id == $id) | .checked' <<<"$SHIPPED_TREE")
  assert_equals "$device exposes its active state" "$output" \
    "monarch-toggle-$device status | jq -e '.enabled'"
done

# ── Routes ───────────────────────────────────────────────────────────────────

assert_equals "empty route opens the root menu" "$("$MENU" --resolve '')" "root"
assert_equals "go is a synonym for the root menu" "$("$MENU" --resolve go)" "root"
assert_equals "an exact id resolves to itself" "$("$MENU" --resolve trigger.capture)" "trigger.capture"
assert_equals "a last segment resolves to its full id" "$("$MENU" --resolve screenrecord)" "trigger.capture.screenrecord"
assert_equals "a declared alias resolves" "$("$MENU" --resolve wifi-qr)" "trigger.share.wifi"
assert_equals "the Wi-Fi route resolves inside Network" "$("$MENU" --resolve wifi)" "setup.network.wifi"
assert_equals "the DNS route resolves inside Network" "$("$MENU" --resolve dns)" "setup.network.dns"
assert_equals "a hidden legacy category remains routable" "$("$MENU" --resolve remove)" "remove"
assert_equals "routes are case insensitive" "$("$MENU" --resolve SETTINGS)" "setup"
assert_equals "underscores normalise to dashes" "$("$MENU" --resolve power_menu)" "system"
assert_equals "an unknown route falls through literally" "$("$MENU" --resolve nope)" "nope"

if "$MENU" --initial nope >/dev/null 2>&1; then
  fail "an unknown initial route is rejected before the panel loads it"
fi
pass "an unknown initial route is rejected before the panel loads it"

mkdir -p "$HOME/.config/niri" "$TMPDIR/keybindings-bin"
cat >"$TMPDIR/keybindings-bin/xkbcli" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TMPDIR/keybindings-bin/xkbcli"
cat >"$HOME/.config/niri/config.kdl" <<EOF
include "$ROOT/default/niri/binds.kdl"
EOF
output=$(PATH="$TMPDIR/keybindings-bin:$PATH" "$ROOT/bin/monarch-menu-keybindings" --print)
assert_contains "keybindings list the close-window aliases together" "$output" \
  "SUPER + Q / SUPER SHIFT + Q"
assert_equals "keybindings list close-window once" \
  "$(grep -Fc 'Close active window' <<<"$output")" "1"

# An exact id must beat an alias that names something else.
cat >"$USER_MENU" <<'EOF'
{
  "decoy": {"label":"Decoy","aliases":["style"],"action":"true"}
}
EOF
assert_equals "an exact id wins over another entry's alias" "$("$MENU" --resolve style)" "style"
rm -f "$USER_MENU"

# ── The user overlay ─────────────────────────────────────────────────────────

cat >"$USER_MENU" <<'EOF'
{
  // Overriding a shipped id replaces only the fields declared here.
  "learn.bash": {"label":"Shell"},
  "personal": {"icon":"P","label":"Personal"},
  "personal.notes": {"label":"Notes","action":"true"},
}
EOF

output=$("$MENU" --rows learn | cut -f2 | tr '\n' ' ')
assert_contains "an overridden label is used" "$output" "Shell"
assert_equals "an overridden entry keeps its position" "${output% }" \
  "Keybindings Monarch Niri Noctalia Arch Neovim Shell Herdr About"

output=$("$MENU" --rows '' | cut -f1 | tr '\n' ' ')
assert_contains "a new top-level id appends to the root menu" "$output" "personal"
assert_equals "new ids append after the shipped ones" "${output% }" \
  "apps trigger setup style install update system learn personal"

output=$("$MENU" --rows personal | cut -f2)
assert_equals "a new submenu renders its children" "$output" "Notes"

output=$("$MENU" --check)
assert_contains "user entries are checked too" "$output" "Menu data check passed"

# A shipped entry keeps the fields the overlay does not mention: learn.bash was
# retitled above and must still carry its original action.
cat >"$USER_MENU" <<'EOF'
{
  "learn.bash": {"label":"Shell"}
}
EOF
output=$(MONARCH_PATH="$ROOT" jq -r '.["learn.bash"].action' < <(
  python - "$ROOT/default/monarch/monarch-menu.jsonc" "$USER_MENU" <<'PY'
import json, re, sys
def load(path):
    raw = open(path, encoding="utf-8").read()
    raw = "\n".join("" if l.lstrip().startswith("//") else l for l in raw.splitlines())
    return json.loads(re.sub(r",(\s*[}\]])", r"\1", raw))
defaults = load(sys.argv[1])
for key, entry in load(sys.argv[2]).items():
    if key in defaults:
        defaults[key].update(entry)
    else:
        defaults[key] = entry
json.dump(defaults, sys.stdout)
PY
))
assert_contains "an override keeps the fields it does not declare" "$output" "devhints.io/bash"

# ── Broken input ─────────────────────────────────────────────────────────────

cat >"$USER_MENU" <<'EOF'
{ "broken": {"label": }
EOF
output=$("$MENU" --rows '' 2>/dev/null | cut -f1 | tr '\n' ' ')
assert_equals "an unparseable user file drops every user entry, not the menu" \
  "${output% }" "apps trigger setup style install update system learn"
refute_contains "an unparseable user file contributes nothing" "$output" "broken"
rm -f "$USER_MENU"

# ── Guards ───────────────────────────────────────────────────────────────────

cat >"$USER_MENU" <<'EOF'
{
  "guarded": {"label":"Guarded"},
  "guarded.always": {"label":"Always","when":"true","action":"true"},
  "guarded.never": {"label":"Never","when":"false","action":"true"},
  "guarded.exit-code": {"label":"ExitCode","when":"[[ 1 == 2 ]]","action":"true"},
}
EOF

output=$("$MENU" --rows guarded | cut -f2 | tr '\n' ' ')
assert_equals "a when guard hides the rows that fail it" "${output% }" "Always"
rm -f "$USER_MENU"

# ── Data integrity ───────────────────────────────────────────────────────────

cat >"$USER_MENU" <<'EOF'
{
  "dangling": {"label":"Dangling","target":"does.not.exist"}
}
EOF
if "$MENU" --check >/dev/null 2>&1; then
  fail "check rejects a target that does not exist"
fi
pass "check rejects a target that does not exist"

cat >"$USER_MENU" <<'EOF'
{
  "bogus": {"label":"Bogus","provider":"not-a-provider"}
}
EOF
if "$MENU" --check >/dev/null 2>&1; then
  fail "check rejects an unknown provider"
fi
pass "check rejects an unknown provider"

cat >"$USER_MENU" <<'EOF'
{
  "orphan.child": {"label":"Orphan","action":"true"}
}
EOF
if "$MENU" --check >/dev/null 2>&1; then
  fail "check rejects an entry whose parent is missing"
fi
pass "check rejects an entry whose parent is missing"

rm -f "$USER_MENU"

# ── The payloads the panel consumes ──────────────────────────────────────────

# One payload feeds both the panel and the launcher: the tree in declaration
# order, and every guard already evaluated.
STATE=$("$MENU" --state)
output=$(jq -r '.tree[0].id + " " + .tree[-1].id' <<<"$STATE")
assert_equals "--state emits the tree in declaration order" "$output" "apps system.shutdown"

output=$(jq -r '.tree[] | select(.id == "learn.bash") | .action' <<<"$STATE")
assert_contains "--state carries the fields the panel renders" "$output" "devhints.io/bash"

output=$(jq -r '.tree[] | select(.id == "trigger.capture.screenshot") | [.description, (.keywords | join(" "))] | join(" ")' <<<"$STATE")
assert_contains "--state carries search descriptions" "$output" "Capture the screen"
assert_contains "--state carries search keywords" "$output" "snip"

output=$(jq -r '.tree[] | select(.id == "setup.network.wifi") | .searchText' <<<"$STATE")
assert_contains "--state prepares search text outside the plugin" "$output" "wireless"

if ! grep -q 'query ~= "" and isCategory' "$ROOT/default/noctalia/plugins/monarch-menu/model.luau"; then
  fail "search includes matching categories"
fi
pass "search includes matching categories"

if ! grep -q 'labelLower == queryLower' "$ROOT/default/noctalia/plugins/monarch-menu/model.luau" ||
  ! grep -q 'a.matchRank > b.matchRank' "$ROOT/default/noctalia/plugins/monarch-menu/model.luau"; then
  fail "search ranks exact labels before fuzzy matches"
fi
pass "search ranks exact labels before fuzzy matches"

if ! grep -q 'groupLeaders' "$ROOT/default/noctalia/plugins/monarch-menu/model.luau" ||
  ! grep -q 'a.group ~= b.group' "$ROOT/default/noctalia/plugins/monarch-menu/model.luau"; then
  fail "search keeps result groups contiguous"
fi
pass "search keeps result groups contiguous"

# Guards are keyed `<id>:<w|c|d>` so the consumer decodes them natively.
output=$(jq -r '.guards | keys | map(split(":")[1]) | unique | join(" ")' <<<"$STATE")
assert_equals "--state reports all three guard kinds" "$output" "c d w"

# Install rows stay listed when the software is already there, and say so with a
# `disabled` guard; Remove rows are the opposite and hide what is not installed.
output=$(jq -r '[.tree[] | select(.id | startswith("install.")) | select(.disabled)] | length' <<<"$STATE")
if [[ $output -lt 40 ]]; then
  fail "install rows carry a presence guard"
fi
pass "install rows carry a presence guard"

output=$(jq -r '[.tree[] | select(.id | startswith("install.cyber.")) | select(.disabled)] | length' <<<"$STATE")
assert_equals "every Cyber install row carries a presence guard" "$output" "3"

output=$(jq -r '[.tree[] | select(.id | startswith("install.")) | select(.when)] | length' <<<"$STATE")
assert_equals "install rows never hide with when" "$output" "0"

output=$(jq -r '[.tree[] | select(.id | startswith("remove.")) | select(.disabled)] | length' <<<"$STATE")
assert_equals "remove rows never dim with disabled" "$output" "0"

output=$(jq -r '[.guards | keys[] | select(startswith("trigger.hardware"))] | length' <<<"$STATE")
if [[ $output -lt 1 ]]; then
  fail "--state evaluates the hardware guards"
fi
pass "--state evaluates the hardware guards"

# Providers are resolved by id, and only for entries that declare one. What a
# provider lists depends on the machine — a CI runner has no power profiles — so
# the shape is only asserted when there is a row to assert it on.
output=$("$MENU" --provider setup.power | jq -r 'type')
assert_equals "--provider emits a JSON array" "$output" "array"

if [[ $("$MENU" --provider setup.power | jq 'length') -gt 0 ]]; then
  output=$("$MENU" --provider setup.power | jq -r '.[0] | has("label"), has("value"), has("current")' | tr '\n' ' ')
  assert_equals "--provider rows carry label/value/current" "${output% }" "true true true"
else
  pass "--provider rows carry label/value/current (no rows on this machine)"
fi

if "$MENU" --provider learn >/dev/null 2>&1; then
  fail "--provider rejects an entry with no provider"
fi
pass "--provider rejects an entry with no provider"

# ── Routing to the panel ─────────────────────────────────────────────────────

# The menu itself is a Noctalia panel now, so the command only dispatches. A
# fake `noctalia` on PATH records what it was asked to do.
FAKE_BIN="$TMPDIR/bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/noctalia" <<'EOF'
#!/bin/bash
if [[ ${1:-} == msg && ${2:-} == panel-open && ${3:-} == monarch/menu:* ]]; then
  payload=${4:-}
  selection_file=$(jq -r '.selectionFile' <<<"$payload")
  done_file=$(jq -r '.doneFile' <<<"$payload")
  printf '%s\n' "${NOCTALIA_TEST_SELECTION:-}" >"$selection_file"
  : >"$done_file"
  exit 0
fi
echo "$*"
EOF
chmod +x "$FAKE_BIN/noctalia"
export PATH="$FAKE_BIN:$PATH"

assert_equals "native select returns the chosen option" \
  "$(NOCTALIA_TEST_SELECTION=medium "$ROOT/bin/monarch-menu-select" Resolution high medium low)" "medium"

if ! grep -q 'panel-open monarch/menu:select' "$ROOT/bin/monarch-menu-select"; then
  fail "native select uses the compact panel"
fi
pass "native select uses the compact panel"

assert_equals "native input returns the submitted text" \
  "$(NOCTALIA_TEST_SELECTION='Ship it' "$ROOT/bin/monarch-menu-input" Reminder)" "Ship it"

if ! grep -q 'panel-open monarch/menu:input' "$ROOT/bin/monarch-menu-input"; then
  fail "native input uses the compact panel"
fi
pass "native input uses the compact panel"

if ! grep -q 'mode == "menu" and not menu' "$ROOT/default/noctalia/plugins/monarch-menu/panel.luau"; then
  fail "native input handles keys without loading the menu tree"
fi
pass "native input handles keys without loading the menu tree"

if ! grep -A4 'refreshInitial(context, function(loaded)' \
  "$ROOT/default/noctalia/plugins/monarch-menu/panel.luau" | grep -q 'if not loaded then'; then
  fail "a rejected initial route does not start a full state callback"
fi
pass "a rejected initial route does not start a full state callback"

assert_equals "a bare call toggles the panel at the root" \
  "$("$MENU")" "msg panel-toggle monarch/menu:panel root"

assert_equals "a route is passed as the panel context" \
  "$("$MENU" style)" "msg panel-toggle monarch/menu:panel style"

assert_equals "close closes the panel" \
  "$("$MENU" close)" "msg panel-close monarch/menu:panel"

printf '\nAll menu tests passed.\n'
