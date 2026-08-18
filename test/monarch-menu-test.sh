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

output=$("$MENU" --rows trigger.share | cut -f2 | tr '\n' ' ')
assert_equals "a level renders its own children only" "${output% }" "Clipboard File Folder"

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

# ── Navigation ───────────────────────────────────────────────────────────────

# The renderer talks to the picker by running `fuzzel`, so a fake one earlier on
# PATH drives real selections: it reads the rows on stdin and echoes back the
# next scripted choice, or nothing at all to mean the picker was dismissed.
FAKE_BIN="$TMPDIR/bin"
mkdir -p "$FAKE_BIN"
export CHOICES_FILE="$TMPDIR/choices" STEP_FILE="$TMPDIR/step" ACTION_LOG="$TMPDIR/actions"

cat >"$FAKE_BIN/fuzzel" <<'EOF'
#!/bin/bash
rows=$(cat)
step=$(cat "$STEP_FILE" 2>/dev/null || echo 0)
echo $((step + 1)) >"$STEP_FILE"
choice=$(sed -n "$((step + 1))p" "$CHOICES_FILE")
[[ -z $choice || $choice == "<dismiss>" ]] && exit 0
grep -m1 -F -- "$choice" <<<"$rows"
EOF

# Stand-ins for the commands the actions launch, so a selection is observable.
for stub in monarch-launch-webapp monarch-launch-about monarch-notification-send; do
  cat >"$FAKE_BIN/$stub" <<EOF
#!/bin/bash
echo "$stub \$*" >>"\$ACTION_LOG"
EOF
done
chmod +x "$FAKE_BIN"/*
export PATH="$FAKE_BIN:$PATH"

# Runs the menu against a scripted list of choices and returns what it launched.
drive_menu() {
  local route="$1"
  shift
  printf '%s\n' "$@" >"$CHOICES_FILE"
  : >"$STEP_FILE"
  : >"$ACTION_LOG"

  XDG_RUNTIME_DIR="$TMPDIR/run" "$MENU" "$route" >/dev/null 2>&1

  # Actions are detached on purpose, so give the fork a moment to land.
  local waited=0
  while [[ ! -s $ACTION_LOG ]] && ((waited < 50)); do
    sleep 0.1
    waited=$((waited + 1))
  done
  cat "$ACTION_LOG"
}

mkdir -p "$TMPDIR/run"

output=$(drive_menu "" "Learn" "Bash")
assert_contains "walking root into a submenu runs the chosen action" "$output" "devhints.io/bash"

output=$(drive_menu learn "Bash")
assert_contains "a route opens that level directly" "$output" "devhints.io/bash"

# Dismissing a child must return to its parent, not end the menu: the third
# choice is only reachable if the root menu was drawn a second time.
output=$(drive_menu "" "Learn" "<dismiss>" "About")
assert_contains "dismissing a submenu returns to its parent" "$output" "monarch-launch-about"

# Dismissing the level the menu was opened at ends it instead of climbing to a
# parent the user never asked for.
output=$(drive_menu learn "<dismiss>" "About")
refute_contains "dismissing an entered route closes the menu" "$output" "monarch-launch-about"

# A route naming an action runs it rather than opening an empty menu.
output=$(drive_menu about)
assert_contains "a route that names an action runs it" "$output" "monarch-launch-about"

printf '\nAll menu tests passed.\n'
