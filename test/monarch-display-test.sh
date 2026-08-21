#!/bin/bash

# Exercises the display commands against a stub niri: the output list, the scale
# and on-off writes, the guard that refuses to blank the last screen, and the
# text-size knob — none of which needs a compositor or a second monitor.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
LIST="$ROOT/bin/monarch-display-list"
SCALE="$ROOT/bin/monarch-display-scale"
TOGGLE="$ROOT/bin/monarch-display-toggle"
TEXT="$ROOT/bin/monarch-display-text-size"
RUNTIME="$ROOT/bin/monarch-niri-runtime"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home/.config/niri" "$TMP/cfg"

pass() { printf 'ok - %s\n' "$1"; }

fail() {
  printf 'not ok - %s\n' "$1" >&2
  shift
  (($# == 0)) || printf '%b\n' "$@" >&2
  exit 1
}

assert_equals() {
  local description="$1" actual="$2" expected="$3"
  [[ $actual == "$expected" ]] || fail "$description" "Expected: $expected" "Actual:   $actual"
  pass "$description"
}

# One eDP on at 1.25 and one DP off, which is the shape both the guard and the
# list have to read correctly.
cat >"$TMP/outputs.json" <<'JSON'
{
  "eDP-1": {
    "name": "eDP-1", "make": "Lenovo", "model": "0x41A6",
    "current_mode": 0,
    "modes": [{"width": 1920, "height": 1200, "refresh_rate": 60026, "is_preferred": true}],
    "logical": {"x": 0, "y": 0, "width": 1536, "height": 960, "scale": 1.25, "transform": "Normal"}
  },
  "DP-1": {
    "name": "DP-1", "make": "Dell", "model": "U2720Q",
    "current_mode": null,
    "modes": [{"width": 3840, "height": 2160, "refresh_rate": 60000, "is_preferred": true}],
    "logical": null
  }
}
JSON

cat >"$TMP/bin/niri" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$NIRI_CALLS"
if [[ $* == *"--json outputs"* ]]; then
  cat "$OUTPUTS_JSON"
  exit 0
fi
if [[ $* == *"--json focused-output"* ]]; then
  printf '{"name": "%s"}\n' "${FOCUSED:-eDP-1}"
  exit 0
fi
exit "${NIRI_STATUS:-0}"
STUB

cat >"$TMP/bin/monarch-hw-niri-socket" <<'STUB'
#!/bin/bash
[[ -n ${NIRI_ABSENT:-} ]] && exit 1
echo /run/stub/niri.sock
STUB

cat >"$TMP/bin/gsettings" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$GS_CALLS"
[[ $1 == get ]] && echo 1.0
exit 0
STUB

cat >"$TMP/bin/monarch-cmd-present" <<'STUB'
#!/bin/bash
command -v "$1" >/dev/null
STUB

# The runtime writer nudges niri; the stub above answers for it, and pgrep must
# not find the host's own compositor and make this test depend on it.
cat >"$TMP/bin/pgrep" <<'STUB'
#!/bin/bash
exit 1
STUB

chmod +x "$TMP"/bin/*
export PATH="$TMP/bin:$ROOT/bin:$PATH"
export OUTPUTS_JSON="$TMP/outputs.json" NIRI_CALLS="$TMP/niri" GS_CALLS="$TMP/gs"
export HOME="$TMP/home"
# Set here and not further down: these commands resolve their files under
# XDG_CONFIG_HOME when it is set, and a shell that exports it — every Monarch
# desktop does — would otherwise point them at the author's own niri config.
export XDG_CONFIG_HOME="$TMP/home/.config"
: >"$NIRI_CALLS"
: >"$GS_CALLS"

# ── The list ─────────────────────────────────────────────────────────────────

listing=$("$LIST")
assert_equals "reports the lit output with its mode and scale" \
  "$(awk -F'\t' '$1 == "eDP-1" { print $2, $3, $4 }' <<<"$listing")" "on 1.25 1920x1200@60"
assert_equals "and names it" \
  "$(awk -F'\t' '$1 == "eDP-1" { print $6 }' <<<"$listing")" "Lenovo 0x41A6"

# niri reports focus separately from the output list, and it is what says which
# screen a scale change lands on.
assert_equals "marks the focused output" \
  "$(awk -F'\t' '$5 == "focused" { print $1 }' <<<"$listing")" "eDP-1"
assert_equals "and only that one" \
  "$(awk -F'\t' '$5 == "focused"' <<<"$listing" | grep -c .)" "1"

# A disabled output keeps its row: it is the only way to name it to turn it on.
assert_equals "a disabled output is listed as off" \
  "$(awk -F'\t' '$1 == "DP-1" { print $2 }' <<<"$listing")" "off"
assert_equals "with no scale and no mode" \
  "$(awk -F'\t' '$1 == "DP-1" { print "[" $3 "][" $4 "]" }' <<<"$listing")" "[][]"

# Noctalia's PATH is /usr/local/sbin:/usr/local/bin:/usr/bin, so a sibling called
# by name is not found when the shell runs these: the panel got "niri is not
# running" with a perfectly live socket sitting in its own environment.
#
# Asserted by reading the source rather than by running it. Exercising the
# fallback needs a PATH where the sibling is reachable *only* through it, which
# would mean planting the stub in the repository's own bin/ — and the whole
# point of the line is that it resolves against wherever the script itself is.
for command in "$LIST" "$SCALE" "$TOGGLE" "$TEXT"; do
  grep -qF 'PATH="$PATH:$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"' "$command" ||
    fail "each display command can find its siblings without Monarch's bin on PATH" \
      "Missing from: $command"
done
pass "each display command can find its siblings without Monarch's bin on PATH"

NIRI_ABSENT=1 "$LIST" 2>"$TMP/err" && fail "no compositor is an error, not an empty list"
assert_equals "and says so" "$(<"$TMP/err")" "Error: niri is not running."

# ── The scale ────────────────────────────────────────────────────────────────

: >"$NIRI_CALLS"
"$SCALE" eDP-1 1.5
assert_equals "a scale is applied live" \
  "$(grep -c 'msg output eDP-1 scale 1.5' "$NIRI_CALLS")" "1"
assert_equals "and persisted where a reload will find it" \
  "$(awk '/output "eDP-1"/{f=1} f && /scale/{print $2; exit}' "$HOME/.config/niri/runtime.kdl")" "1.5"

for bad in 0.2 5 abc; do
  "$SCALE" eDP-1 "$bad" 2>/dev/null && fail "an out-of-range scale is refused: $bad"
done
pass "an out-of-range or non-numeric scale is refused"

"$SCALE" NOPE 1.5 2>"$TMP/err" && fail "an unknown output is refused"
assert_equals "and names it" "$(<"$TMP/err")" "Error: no display named NOPE."

# niri refusing the scale must not leave a file that re-offers it at every start.
rm -f "$HOME/.config/niri/runtime.kdl"
NIRI_STATUS=1 "$SCALE" eDP-1 2 2>/dev/null && fail "a scale niri rejects exits non-zero"
[[ -f $HOME/.config/niri/runtime.kdl ]] && fail "a scale niri rejects is not persisted"
pass "a scale niri rejects is neither kept nor reported as applied"

# ── The on-off ───────────────────────────────────────────────────────────────

: >"$NIRI_CALLS"
"$TOGGLE" DP-1 on
assert_equals "turning a dark output on reaches niri" \
  "$(grep -c 'msg output DP-1 on' "$NIRI_CALLS")" "1"

: >"$NIRI_CALLS"
"$TOGGLE" eDP-1 on
assert_equals "asking for the state it is already in does nothing" \
  "$(grep -c 'msg output' "$NIRI_CALLS" || true)" "0"

# Turning one off needs a second lit screen, or the guard below fires first.
sed 's/"logical": null/"logical": {"scale": 2.0}/; s/"current_mode": null/"current_mode": 0/' \
  "$TMP/outputs.json" >"$TMP/outputs-both.json"

: >"$NIRI_CALLS"
OUTPUTS_JSON="$TMP/outputs-both.json" "$TOGGLE" eDP-1 off
assert_equals "turning a lit one off reaches niri" \
  "$(grep -c 'msg output eDP-1 off' "$NIRI_CALLS")" "1"
assert_equals "and is persisted" \
  "$(awk '/output "eDP-1"/{f=1} f && /^ *off$/{print "off"; exit}' "$HOME/.config/niri/runtime.kdl")" "off"

# The last screen standing is refused: niri would have nothing to draw on, and
# there would be nothing on screen to turn it back with.
cat >"$TMP/outputs-single.json" <<'JSON'
{ "eDP-1": { "name": "eDP-1", "make": "Lenovo", "model": "0x41A6", "current_mode": 0,
  "modes": [{"width": 1920, "height": 1200, "refresh_rate": 60026}],
  "logical": {"scale": 1.0} } }
JSON
OUTPUTS_JSON="$TMP/outputs-single.json" "$TOGGLE" eDP-1 off 2>"$TMP/err" &&
  fail "blanking the only screen is refused"
pass "blanking the only screen is refused"
assert_equals "and says why" "$(<"$TMP/err")" "Error: eDP-1 is the only display that is on."

# ── The runtime file ─────────────────────────────────────────────────────────

# Two properties in one block: turning an output off must not lose its scale,
# which an earlier parser dropped by forgetting the name after the first match.
rm -f "$HOME/.config/niri/runtime.kdl"
"$RUNTIME" output-scale DP-1 2
"$RUNTIME" output DP-1 off >/dev/null
assert_equals "a disabled output keeps its scale" \
  "$(awk '/output "DP-1"/{f=1} f && /scale/{print $2; exit}' "$HOME/.config/niri/runtime.kdl")" "2"
"$RUNTIME" output DP-1 on >/dev/null
assert_equals "and gets it back when it is turned on" \
  "$(awk '/output "DP-1"/{f=1} f && /scale/{print $2; exit}' "$HOME/.config/niri/runtime.kdl")" "2"
assert_equals "with the off gone" \
  "$(grep -c '^ *off$' "$HOME/.config/niri/runtime.kdl" || true)" "0"

# Read back through the front door the properties always come out in the order
# the writer put them, so the parser is fed a block in the other order here.
# Losing the name after the first property is what an earlier one did, and it
# would drop everything below it silently.
cat >"$HOME/.config/niri/runtime.kdl" <<'KDL'
// GENERATED by Monarch — niri runtime overrides. Do not edit.

output "DP-1" {
    scale 2
    off
}
KDL
"$RUNTIME" output-scale eDP-1 1 >/dev/null
assert_equals "a property below another in the same block is not lost" \
  "$(awk '/output "DP-1"/{f=1} f && /^ *off$/{print "off"; exit}' "$HOME/.config/niri/runtime.kdl")" "off"
assert_equals "nor is the one above it" \
  "$(awk '/output "DP-1"/{f=1} f && /scale/{print $2; exit}' "$HOME/.config/niri/runtime.kdl")" "2"

# ── Sharing the outputs with nwg-displays ────────────────────────────────────

# nwg-displays puts `include "monitor.kdl"` at the very top of config.kdl and
# Monarch's runtime.kdl is included further down, so Monarch won every key both
# set — silently undoing whatever scale had been arranged over there. When that
# file exists it is the owner, and Monarch writes into it instead.

SET="$ROOT/bin/monarch-niri-output-set"
monitors="$XDG_CONFIG_HOME/niri/monitor.kdl"

write_monitors() {
  cat >"$monitors" <<'KDL'
// Generated by nwg-displays on 2026-08-18 at 08:44:46. Do not edit manually.

output "eDP-1" {
    mode "1920x1200@60.026"
    scale 1.25
    position x=1214 y=1080
}

output "DP-1" {
    mode "1920x1080@60.0"
    scale 1.0
    position x=1920 y=0
}
KDL
}

block() {
  awk -v name="$1" '$0 ~ "^output \"" name "\" \\{" { inside = 1 } inside { print } /^\}/ { inside = 0 }' "$monitors"
}

rm -f "$HOME/.config/niri/runtime.kdl"
write_monitors
"$SET" eDP-1 scale 2
assert_equals "a scale lands in the file nwg-displays owns" \
  "$(block eDP-1 | awk '/^ *scale/ { print $2 }')" "2"
[[ -f $HOME/.config/niri/runtime.kdl ]] && fail "and not in runtime.kdl, which would win over it"
pass "and not in runtime.kdl, which would win over it"

# Only ever one line: the arrangement the user made over there is the whole
# reason for writing here rather than beside it.
assert_equals "the mode it wrote survives" \
  "$(block eDP-1 | awk '/^ *mode/ { print $2 }')" '"1920x1200@60.026"'
assert_equals "and so does the position" \
  "$(block eDP-1 | awk '/^ *position/ { print $2, $3 }')" "x=1214 y=1080"

# nwg-displays writes a bare `output "X" { off }` for a dark screen, dropping
# its mode, scale and position. Doing that here would erase where the monitor
# sat, and turning it back on would land it wherever niri felt like.
"$SET" DP-1 power off >/dev/null
assert_equals "off is added to the block" \
  "$(block DP-1 | grep -c '^ *off$')" "1"
assert_equals "and takes nothing with it" \
  "$(block DP-1 | awk '/^ *position/ { print $2, $3 }')" "x=1920 y=0"

"$SET" DP-1 power off >/dev/null
assert_equals "asking twice does not write it twice" \
  "$(block DP-1 | grep -c '^ *off$')" "1"

"$SET" DP-1 power on >/dev/null
assert_equals "turning it back on removes only that line" \
  "$(block DP-1 | grep -c '^ *off$' || true)" "0"
assert_equals "leaving the position it had" \
  "$(block DP-1 | awk '/^ *position/ { print $2, $3 }')" "x=1920 y=0"

# A file whose header says "Generated by nwg-displays" is not ours to invent,
# so with none of it there Monarch owns the outputs as it did before.
rm -f "$monitors" "$HOME/.config/niri/runtime.kdl"
"$SET" eDP-1 scale 1.6
assert_equals "with no such file, runtime.kdl is still the owner" \
  "$(awk '/output "eDP-1"/{f=1} f && /scale/ { print $2; exit }' "$HOME/.config/niri/runtime.kdl")" "1.6"

# Same when the file exists but has never heard of this output.
write_monitors
rm -f "$HOME/.config/niri/runtime.kdl"
"$SET" HDMI-A-1 scale 2
assert_equals "an output it does not carry falls back too" \
  "$(awk '/output "HDMI-A-1"/{f=1} f && /scale/ { print $2; exit }' "$HOME/.config/niri/runtime.kdl")" "2"
rm -f "$monitors" "$HOME/.config/niri/runtime.kdl"

# ── The text size ────────────────────────────────────────────────────────────

XDG_CONFIG_HOME="$TMP/cfg"
export XDG_CONFIG_HOME
assert_equals "starts at the Monarch default" \
  "$("$TEXT" | awk -F'\t' '$1 == "percent" { print $2 }')" "100"

# Two bars, so the "every bar the user declared" branch is the one exercised.
mkdir -p "$XDG_CONFIG_HOME/noctalia"
printf '[bar]\norder = ["default", "second"]\n\n  [bar.default]\n  position = "top"\n' \
  >"$XDG_CONFIG_HOME/noctalia/config.toml"

"$TEXT" 115 >/dev/null
assert_equals "drives the Noctalia shell" \
  "$(awk -F= '/^ui_scale[[:space:]]*=/ { gsub(/ /, "", $2); print $2 }' "$XDG_CONFIG_HOME/noctalia/monarch-text-size.toml")" "1.15"
# ui_scale reaches the panels, the OSD, the toasts and the lock screen, and
# nothing in the bar: a shell restarted with it at 1.4 drew the same clock, so
# the bar's own scale has to be written too, for every bar there is.
assert_equals "drives the bar, which has a scale of its own" \
  "$(awk '/^\[bar\.default\]/{f=1} f && /^scale/ { gsub(/[^0-9.]/, ""); print; exit }' "$XDG_CONFIG_HOME/noctalia/monarch-text-size.toml")" "1.15"
assert_equals "and a second bar is not left behind at 1.0" \
  "$(awk '/^\[bar\.second\]/{f=1} f && /^scale/ { gsub(/[^0-9.]/, ""); print; exit }' "$XDG_CONFIG_HOME/noctalia/monarch-text-size.toml")" "1.15"

assert_equals "drives GTK" \
  "$(grep -c 'set org.gnome.desktop.interface text-scaling-factor 1.15' "$GS_CALLS")" "1"
assert_equals "drives the terminal, off the shipped size of 9" \
  "$(awk -F= '/^size[[:space:]]*=/ { gsub(/ /, "", $2); print $2 }' "$XDG_CONFIG_HOME/alacritty/monarch-text-size.toml")" "10.3"

# %d on 1.15 * 100 reads back 114: the product is 114.999… in binary floating
# point, so the round trip has to round rather than truncate.
for percent in 75 95 115 145 175; do
  "$TEXT" "$percent" >/dev/null
  read_back=$("$TEXT" | awk -F'\t' '$1 == "percent" { print $2 }')
  [[ $read_back == "$percent" ]] || fail "the size reads back as it was set" \
    "Expected: $percent" "Actual:   $read_back"
done
pass "the size reads back as it was set, across the range"

for bad in 113 50 200 abc; do
  "$TEXT" "$bad" 2>/dev/null && fail "a size off the grid or out of range is refused: $bad"
done
pass "a size off the grid or out of range is refused"

"$TEXT" reset >/dev/null
assert_equals "reset goes back to the default" \
  "$("$TEXT" | awk -F'\t' '$1 == "percent" { print $2 }')" "100"

# The menu hands a row straight back as the argument, so every row it is offered
# has to be one the command takes — including the % it is labelled with.
while read -r row; do
  "$TEXT" "$row" >/dev/null 2>&1 || fail "every row the menu lists is a size the command takes" \
    "Rejected: $row"
done < <("$TEXT" --list)
pass "every row the menu lists is a size the command takes"

assert_equals "and --current answers in the same shape" \
  "$("$TEXT" --current)" "175%"
"$TEXT" reset >/dev/null

# ── The brightness ───────────────────────────────────────────────────────────

# Noctalia reads the same two sources and refuses to print what it read, so the
# mapping from a connector to its backlight is ours to get right: a laptop with
# two backlight devices and one lit panel is where a wrong answer drives the
# wrong hardware.
BRIGHTNESS="$ROOT/bin/monarch-display-brightness"
export MONARCH_SYS_DRM="$TMP/sys/drm"
export MONARCH_SYS_BACKLIGHT="$TMP/sys/backlight"
export MONARCH_BRIGHTNESS_CACHE="$TMP/cache"
export NOCTALIA_CALLS="$TMP/noctalia" DDC_CALLS="$TMP/ddc"

mkdir -p "$TMP/sys/drm/card1-eDP-1" "$TMP/sys/drm/card1-DP-1" "$TMP/sys/drm/card0-HDMI-A-1"
echo connected >"$TMP/sys/drm/card1-eDP-1/status"
echo connected >"$TMP/sys/drm/card1-DP-1/status"
echo disconnected >"$TMP/sys/drm/card0-HDMI-A-1/status"

mkdir -p "$TMP/sys/backlight/amdgpu_bl1"
printf '60\n' >"$TMP/sys/backlight/amdgpu_bl1/brightness"
printf '100\n' >"$TMP/sys/backlight/amdgpu_bl1/max_brightness"
printf 'raw\n' >"$TMP/sys/backlight/amdgpu_bl1/type"
ln -sfn "$TMP/sys/drm/card1-eDP-1" "$TMP/sys/backlight/amdgpu_bl1/device"

cat >"$TMP/bin/noctalia" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$NOCTALIA_CALLS"
[[ -n ${NOCTALIA_FAILS:-} ]] && { echo "error: brightness control unavailable"; exit 1; }
echo ok
STUB

cat >"$TMP/bin/ddcutil" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$DDC_CALLS"
[[ -n ${DDC_ABSENT:-} ]] && exit 1
if [[ $* == *detect* ]]; then
  printf 'Display 1\n   I2C bus:  /dev/i2c-7\n   DRM connector:  card1-DP-1\n'
  exit 0
fi
if [[ $* == *getvcp* ]]; then
  [[ -n ${DDC_MUTE:-} ]] && exit 1
  printf 'VCP 10 C %s 255\n' "${DDC_RAW:-128}"
  exit 0
fi
exit 0
STUB
chmod +x "$TMP/bin/noctalia" "$TMP/bin/ddcutil"
: >"$NOCTALIA_CALLS"
: >"$DDC_CALLS"

# No bus in this half: a temporary assignment on assert_equals would not reach
# the command substitutions in its own arguments, which are expanded first.
backlight_only() { DDC_ABSENT=1 "$BRIGHTNESS" "$@"; }

assert_equals "a backlight is read straight from sysfs" \
  "$(backlight_only --list | grep '^eDP-1')" "$(printf 'eDP-1\t60\tbacklight')"
assert_equals "and answers for one output on its own" \
  "$(backlight_only eDP-1)" "60"

# A raw scale is rarely a round hundredth: 7 of 8 steps is 88%, and truncating
# it shows 87% for a panel that is one step below full.
printf '7\n' >"$TMP/sys/backlight/amdgpu_bl1/brightness"
printf '8\n' >"$TMP/sys/backlight/amdgpu_bl1/max_brightness"
assert_equals "the percentage is rounded, not truncated" \
  "$(backlight_only eDP-1)" "88"
printf '60\n' >"$TMP/sys/backlight/amdgpu_bl1/brightness"
printf '100\n' >"$TMP/sys/backlight/amdgpu_bl1/max_brightness"

# A disconnected connector has nothing to light and must not be offered.
assert_equals "a disconnected output is not listed" \
  "$(backlight_only --list | grep -c 'HDMI' || true)" "0"

# Noctalia prefers a raw device over firmware, and penalises acpi_video: the
# firmware one here would answer 10%, and it is the wrong panel.
mkdir -p "$TMP/sys/backlight/acpi_video0"
printf '1\n' >"$TMP/sys/backlight/acpi_video0/brightness"
printf '10\n' >"$TMP/sys/backlight/acpi_video0/max_brightness"
printf 'firmware\n' >"$TMP/sys/backlight/acpi_video0/type"
ln -sfn "$TMP/sys/drm/card1-eDP-1" "$TMP/sys/backlight/acpi_video0/device"
assert_equals "the raw backlight wins over the firmware one" \
  "$(backlight_only eDP-1)" "60"
rm -rf "$TMP/sys/backlight/acpi_video0"

# Hardware that hangs the backlight off the GPU rather than the connector still
# has exactly one internal panel to mean.
mkdir -p "$TMP/sys/backlight/odd_bl" "$TMP/sys/elsewhere"
printf '20\n' >"$TMP/sys/backlight/odd_bl/brightness"
printf '100\n' >"$TMP/sys/backlight/odd_bl/max_brightness"
printf 'raw\n' >"$TMP/sys/backlight/odd_bl/type"
ln -sfn "$TMP/sys/elsewhere" "$TMP/sys/backlight/odd_bl/device"
assert_equals "an unmatched backlight falls back to the internal panel" \
  "$(backlight_only --list | grep -c '^eDP-1')" "1"
assert_equals "and loses the tie to the one that matched exactly" \
  "$(backlight_only eDP-1)" "60"
rm -rf "$TMP/sys/backlight/odd_bl"

# ── The brightness over DDC/CI ───────────────────────────────────────────────

rm -rf "$TMP/cache"
: >"$DDC_CALLS"
assert_equals "a screen with no backlight is read over the bus" \
  "$("$BRIGHTNESS" --list | grep '^DP-1')" "$(printf 'DP-1\t50\tddc')"
assert_equals "which costs one detect" "$(grep -c detect "$DDC_CALLS")" "1"

# The panel polls while it is open; a bus round-trip per second is exactly what
# the cache is for.
: >"$DDC_CALLS"
assert_equals "a second read inside the window answers from the cache" \
  "$("$BRIGHTNESS" --list | grep '^DP-1')" "$(printf 'DP-1\t50\tddc')"
assert_equals "without touching the bus" "$(wc -l <"$DDC_CALLS")" "0"

# A monitor that does not answer must not be asked again every second either.
rm -rf "$TMP/cache"
: >"$DDC_CALLS"
assert_equals "a bus that answers nothing drops the screen from the list" \
  "$(DDC_MUTE=1 "$BRIGHTNESS" --list | grep -c '^DP-1' || true)" "0"
before=$(wc -l <"$DDC_CALLS")
assert_equals "and is not retried on the next read" \
  "$(DDC_MUTE=1 "$BRIGHTNESS" --list | grep -c '^DP-1' || true)" "0"
assert_equals "which is the point of remembering the failure" \
  "$(wc -l <"$DDC_CALLS")" "$before"

rm -rf "$TMP/cache"

# ── Setting the brightness ───────────────────────────────────────────────────

# Every write goes through Noctalia: it holds the logind handle for sysfs and a
# worker with cooldowns for the bus, and a second writer would fight both.
: >"$NOCTALIA_CALLS"
backlight_only eDP-1 40
assert_equals "a set is handed to noctalia" \
  "$(<"$NOCTALIA_CALLS")" "msg brightness-set eDP-1 40"

set +e
out=$(NOCTALIA_FAILS=1 backlight_only eDP-1 40 2>&1)
status=$?
set -e
assert_equals "a refusal from noctalia is a failure here too" "$status" "1"
assert_equals "and it is noctalia's own words that surface" \
  "$out" "error: brightness control unavailable"

for value in 120 -5 abc 50.5; do
  set +e
  out=$(backlight_only eDP-1 "$value" 2>&1)
  status=$?
  set -e
  assert_equals "$value is not a percentage" "$status" "1"
  assert_equals "and says so" "${out%%:*}" "Error"
done

# The value just written beats a cached read of a bus that answers slowly, or
# the slider snaps back to where it was for as long as the cache lives.
"$BRIGHTNESS" --list >/dev/null
: >"$DDC_CALLS"
"$BRIGHTNESS" DP-1 30
assert_equals "setting over the bus refreshes what the cache holds" \
  "$("$BRIGHTNESS" --list | grep '^DP-1')" "$(printf 'DP-1\t30\tddc')"
assert_equals "without a round-trip to ask" "$(wc -l <"$DDC_CALLS")" "0"

# ── The migration ────────────────────────────────────────────────────────────

# The riskiest thing in this change is the sed that moves an existing size out
# of alacritty.toml, because it runs against a file the user may have edited.

cat >"$TMP/bin/sudo" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SUDO_CALLS"
STUB
cat >"$TMP/bin/id" <<'STUB'
#!/bin/bash
[[ $1 == -nG ]] && { echo "users wheel"; exit 0; }
exec /usr/bin/id "$@"
STUB
chmod +x "$TMP/bin/sudo" "$TMP/bin/id"
export SUDO_CALLS="$TMP/sudo" MONARCH_PATH="$ROOT" USER=tester
MIGRATION="$ROOT/migrations/1787306395.sh"

run_migration() {
  rm -f "$HOME/.config/alacritty/monarch-text-size.toml" "$SUDO_CALLS"
  : >"$SUDO_CALLS"
  bash "$MIGRATION" >/dev/null
}

mkdir -p "$HOME/.config/alacritty" "$HOME/.config/noctalia"

# The shipped shape: one line, one import.
cat >"$HOME/.config/alacritty/alacritty.toml" <<'TOML'
general.import = [ "~/.config/alacritty/themes/noctalia.toml" ]

[font]
size = 9
TOML
run_migration
assert_equals "the size leaves alacritty.toml" \
  "$(grep -c '^[[:space:]]*size[[:space:]]*=' "$HOME/.config/alacritty/alacritty.toml" || true)" "0"
assert_equals "the import is added beside the theme" \
  "$(grep -c 'themes/noctalia.toml".*monarch-text-size.toml' "$HOME/.config/alacritty/alacritty.toml")" "1"
assert_equals "and the size it had is what lands in the override" \
  "$(awk -F= '/^size[[:space:]]*=/ { gsub(/ /, "", $2); print $2 }' "$HOME/.config/alacritty/monarch-text-size.toml")" "9"

# A hand-edited shape: several lines, and a size that is not the default. The
# point of moving rather than resetting is that this survives.
cat >"$HOME/.config/alacritty/alacritty.toml" <<'TOML'
general.import = [
  "~/.config/alacritty/themes/noctalia.toml",
]

[font]
size = 14
TOML
run_migration
assert_equals "a multi-line import list is handled too" \
  "$(grep -c 'monarch-text-size.toml' "$HOME/.config/alacritty/alacritty.toml")" "1"
assert_equals "and the user's own size is carried over, not reset" \
  "$(awk -F= '/^size[[:space:]]*=/ { gsub(/ /, "", $2); print $2 }' "$HOME/.config/alacritty/monarch-text-size.toml")" "14"

# Re-running must not add the import twice.
before=$(cat "$HOME/.config/alacritty/alacritty.toml")
bash "$MIGRATION" >/dev/null
assert_equals "re-running changes nothing" "$(cat "$HOME/.config/alacritty/alacritty.toml")" "$before"

printf '[bar]\norder = ["default"]\n' >"$HOME/.config/noctalia/config.toml"
: >"$SUDO_CALLS"
bash "$MIGRATION" >/dev/null
assert_equals "the DDC backend is turned on" \
  "$(grep -c '^enable_ddcutil = true' "$HOME/.config/noctalia/config.toml")" "1"
assert_equals "and the user joins the group that rule needs" \
  "$(grep -c 'usermod -aG i2c tester' "$SUDO_CALLS")" "1"

bash "$MIGRATION" >/dev/null
assert_equals "turning it on twice does not write it twice" \
  "$(grep -c '^enable_ddcutil = true' "$HOME/.config/noctalia/config.toml")" "1"

echo
echo "All display tests passed."
