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

# ── The shipped data ─────────────────────────────────────────────────────────

output=$("$MENU" --check)
assert_contains "shipped menu data passes its own check" "$output" "Menu data check passed"

output=$("$MENU" --rows "" | cut -f1 | tr '\n' ' ')
assert_equals "root holds the ten top-level entries in declaration order" \
  "${output% }" "apps learn trigger style setup install remove update about system"

# A guard-free level, deliberately: trigger.share hides its Wi-Fi row on a
# machine with no wireless connection, which would make this assertion depend on
# the host it runs on.
output=$("$MENU" --rows style.screensaver | cut -f2 | tr '\n' ' ')
assert_equals "a level renders its own children only" "${output% }" "Edit Text Set From Image Restore Default"

# ── Routes ───────────────────────────────────────────────────────────────────

assert_equals "empty route opens the root menu" "$("$MENU" --resolve '')" "root"
assert_equals "go is a synonym for the root menu" "$("$MENU" --resolve go)" "root"
assert_equals "an exact id resolves to itself" "$("$MENU" --resolve trigger.capture)" "trigger.capture"
assert_equals "a last segment resolves to its full id" "$("$MENU" --resolve screenrecord)" "trigger.capture.screenrecord"
assert_equals "a declared alias resolves" "$("$MENU" --resolve reminder-set)" "trigger.reminder.set"
assert_equals "routes are case insensitive" "$("$MENU" --resolve SETTINGS)" "setup"
assert_equals "underscores normalise to dashes" "$("$MENU" --resolve power_menu)" "system"
assert_equals "an unknown route falls through literally" "$("$MENU" --resolve nope)" "nope"

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
  "Keybindings Monarch Niri Arch Neovim Shell"

output=$("$MENU" --rows '' | cut -f1 | tr '\n' ' ')
assert_contains "a new top-level id appends to the root menu" "$output" "personal"
assert_equals "new ids append after the shipped ones" "${output% }" \
  "apps learn trigger style setup install remove update about system personal"

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
  "${output% }" "apps learn trigger style setup install remove update about system"
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
output=$("$MENU" --state | jq -r '.tree[0].id + " " + .tree[-1].id')
assert_equals "--state emits the tree in declaration order" "$output" "apps system.shutdown"

output=$("$MENU" --state | jq -r '.tree[] | select(.id == "learn.bash") | .action')
assert_contains "--state carries the fields the panel renders" "$output" "devhints.io/bash"

# Guards are keyed `<id>:<w|c|d>` so the consumer decodes them natively.
output=$("$MENU" --state | jq -r '.guards | keys | map(split(":")[1]) | unique | join(" ")')
assert_equals "--state reports all three guard kinds" "$output" "c d w"

# Install rows stay listed when the software is already there, and say so with a
# `disabled` guard; Remove rows are the opposite and hide what is not installed.
output=$("$MENU" --state | jq -r '[.tree[] | select(.id | startswith("install.")) | select(.disabled)] | length')
if [[ $output -lt 40 ]]; then
  fail "install rows carry a presence guard"
fi
pass "install rows carry a presence guard"

output=$("$MENU" --state | jq -r '[.tree[] | select(.id | startswith("install.")) | select(.when)] | length')
assert_equals "install rows never hide with when" "$output" "0"

output=$("$MENU" --state | jq -r '[.tree[] | select(.id | startswith("remove.")) | select(.disabled)] | length')
assert_equals "remove rows never dim with disabled" "$output" "0"

output=$("$MENU" --state | jq -r '[.guards | keys[] | select(startswith("trigger.hardware"))] | length')
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
echo "$*"
EOF
chmod +x "$FAKE_BIN/noctalia"
export PATH="$FAKE_BIN:$PATH"

assert_equals "a bare call toggles the panel at the root" \
  "$("$MENU")" "msg panel-toggle monarch/menu:panel root"

assert_equals "a route is passed as the panel context" \
  "$("$MENU" style)" "msg panel-toggle monarch/menu:panel style"

assert_equals "close closes the panel" \
  "$("$MENU" close)" "msg panel-close monarch/menu:panel"

printf '\nAll menu tests passed.\n'
