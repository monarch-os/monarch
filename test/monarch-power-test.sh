#!/bin/bash

# Exercises what the power widget reads and drives — the battery fields and the
# per-source profile memory — against a fake upower, a fake powerprofilesctl and
# a power-supply tree the test owns, so none of it needs a battery.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STATUS="$ROOT/bin/monarch-battery-status"
MONITOR="$ROOT/bin/monarch-battery-monitor"
LIST="$ROOT/bin/monarch-powerprofiles-list"
SET="$ROOT/bin/monarch-powerprofiles-set"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Deliberately not named BAT: `upower -e | grep BAT` used to be the lookup, and
# it finds nothing for the kernel's own test_power module (battery_test_battery)
# or for a CMB0, which is a real name on shipped hardware.
mkdir -p "$TMP/bin" "$TMP/sys/CMB0" "$TMP/sys/AC"

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

field() { awk -F'\t' -v key="$2" '$1 == key { print $2; exit }' <<<"$1"; }

# The stub answers in whatever decimal separator LC_ALL asks for, which is what
# lets the locale assertion below mean something.
cat >"$TMP/bin/upower" <<'STUB'
#!/bin/bash
if [[ $1 == -e ]]; then
  printf '%s\n' /org/freedesktop/UPower/devices/line_power_AC \
    /org/freedesktop/UPower/devices/battery_CMB0 \
    /org/freedesktop/UPower/devices/DisplayDevice
  exit 0
fi
comma() { [[ ${LC_ALL:-} == C ]] && printf '%s' "$1" || printf '%s' "${1/./,}"; }
cat <<EOF
  native-path:          CMB0
  battery
    state:               $UP_STATE
    energy-full:         $(comma ${UP_FULL:-40.3}) Wh
    energy-rate:         $(comma 15.059) W
    time to full:        $(comma 20.8) minutes
    percentage:          ${UP_PERCENT}%
    charge-cycles:       310
${UP_THRESHOLDS}
EOF
STUB

cat >"$TMP/bin/powerprofilesctl" <<'STUB'
#!/bin/bash
if [[ $1 == list ]]; then
  # The real output is most to least power, with indented driver lines under
  # each name that the parser has to skip.
  cat <<'LIST'
  performance:
    CpuDriver:	amd_pstate
    Degraded:   no

* balanced:
    CpuDriver:	amd_pstate

  power-saver:
    CpuDriver:	amd_pstate
LIST
  exit 0
fi
if [[ $1 == set ]]; then
  [[ -n ${PPD_FAIL:-} ]] && exit 1
  printf '%s\n' "$2" >>"$PPD_CALLS"
  exit 0
fi
STUB

cat >"$TMP/bin/notify-send" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_CALLS"
STUB

cat >"$TMP/bin/monarch-hook" <<'STUB'
#!/bin/bash
exit 0
STUB

cat >"$TMP/bin/busctl" <<'STUB'
#!/bin/bash
printf 'b %s\n' "${ON_BATTERY:-false}"
STUB

chmod +x "$TMP"/bin/*
export PATH="$TMP/bin:$ROOT/bin:$PATH"
export MONARCH_POWER_SUPPLY_PATH="$TMP/sys"
export PPD_CALLS="$TMP/ppd" NOTIFY_CALLS="$TMP/notify"
export XDG_RUNTIME_DIR="$TMP/run"
mkdir -p "$XDG_RUNTIME_DIR"
: >"$PPD_CALLS"
: >"$NOTIFY_CALLS"

printf 'Battery\n' >"$TMP/sys/CMB0/type"
printf '1\n' >"$TMP/sys/CMB0/present"
printf 'Mains\n' >"$TMP/sys/AC/type"
printf '1\n' >"$TMP/sys/AC/online"

export UP_STATE=charging UP_PERCENT=87 UP_THRESHOLDS=""

# ── The battery fields ───────────────────────────────────────────────────────

shell=$("$STATUS" --shell)
[[ -n $shell ]] || fail "finds a battery whatever the firmware named it" \
  "The old lookup was upower -e | grep BAT, which matches neither battery_CMB0" \
  "nor the battery_test_battery the kernel's own test_power module registers."
pass "finds a battery whatever the firmware named it"
assert_equals "reports the percentage" "$(field "$shell" percentage)" "87"
assert_equals "reports the state" "$(field "$shell" state)" "charging"
assert_equals "reports the pack size in Wh" "$(field "$shell" size)" "40"
assert_equals "reports the charge cycles" "$(field "$shell" cycles)" "310"
assert_equals "reports the time remaining" "$(field "$shell" time)" "20m"
assert_equals "reports whether mains is online" "$(field "$shell" ac)" "true"

# upower localises its decimal separator. Without LC_ALL=C its 15.059 W reaches
# awk as 15 on a French desktop, and the fraction is lost without a word.
assert_equals "asks upower in a locale that prints decimal points" \
  "$(LC_ALL=fr_FR.UTF-8 "$STATUS" --shell | awk -F'\t' '$1 == "rate" { print $2 }')" "15.1"

# sysfs is instantaneous; upower's energy-rate lags it by tens of seconds.
printf '9200000\n' >"$TMP/sys/CMB0/power_now"
assert_equals "prefers the instantaneous sysfs rate over upower's" \
  "$(field "$("$STATUS" --shell)" rate)" "9.2"

rm -f "$TMP/sys/CMB0/power_now"
printf '800000\n' >"$TMP/sys/CMB0/current_now"
printf '11500000\n' >"$TMP/sys/CMB0/voltage_now"
assert_equals "falls back to current times voltage" \
  "$(field "$("$STATUS" --shell)" rate)" "9.2"
rm -f "$TMP/sys/CMB0/current_now" "$TMP/sys/CMB0/voltage_now"

# A rate is a magnitude — `state` already says which way it is going, and some
# drivers sign power_now where others do not.
printf -- '-3400000\n' >"$TMP/sys/CMB0/power_now"
assert_equals "a signed draw is reported as a magnitude" \
  "$(field "$("$STATUS" --shell)" rate)" "3.4"
rm -f "$TMP/sys/CMB0/power_now"

# upower prints 0 Wh when it does not know the pack size, which is not a pack
# that holds nothing, and "0Wh" on the notification line is worse than silence.
assert_equals "an unknown pack size is left out rather than printed as zero" \
  "$(UP_FULL=0 "$STATUS" --shell | awk -F'\t' '$1 == "size" { print $2 }')" ""

# ── The charge limit ─────────────────────────────────────────────────────────

printf '0\n' >"$TMP/sys/CMB0/charge_control_start_threshold"
printf '100\n' >"$TMP/sys/CMB0/charge_control_end_threshold"
assert_equals "reads a charge limit out of sysfs when upower has none" \
  "$(field "$("$STATUS" --shell)" threshold)" "0-100%"

# The generic attributes read 0 and 100 on a Lenovo with conservation mode off
# while upower reports the pair the firmware actually holds, so upower wins.
export UP_THRESHOLDS=$'    charge-start-threshold:        75%\n    charge-end-threshold:          80%'
assert_equals "prefers the pair upower reports" \
  "$(field "$("$STATUS" --shell)" threshold)" "75-80%"

# Holding is what a charge limit produces and nothing reports: on mains, not
# charging, not full. Every branch needs the draw to have actually stopped, or a
# battery charging hard at 87% would be called held.
printf '14800000\n' >"$TMP/sys/CMB0/power_now"
assert_equals "a battery still drawing power is not holding" \
  "$(field "$("$STATUS" --shell)" state)" "charging"

printf '40000\n' >"$TMP/sys/CMB0/power_now"
assert_equals "one that stopped at its limit is" \
  "$(field "$("$STATUS" --shell)" state)" "holding"

printf '0\n' >"$TMP/sys/AC/online"
assert_equals "and one off mains never is, whatever the draw" \
  "$(UP_STATE=discharging "$STATUS" --shell | awk -F'\t' '$1 == "state" { print $2 }')" "discharging"
assert_equals "which the ac field says too" \
  "$(field "$("$STATUS" --shell)" ac)" "false"
printf '1\n' >"$TMP/sys/AC/online"

rm -f "$TMP/sys/CMB0/power_now"
export UP_STATE=charging UP_PERCENT=87

assert_equals "and monarch-battery-present agrees, on the type and not the name" \
  "$("$ROOT/bin/monarch-battery-present" && echo yes || echo no)" "yes"

# ── The profile list ─────────────────────────────────────────────────────────

assert_equals "lists least to most power" "$("$LIST" | tr '\n' ' ')" "power-saver balanced performance "
assert_equals "--active-state marks the running profile" \
  "$("$LIST" --active-state | awk -F'\t' '$2 == 1 { print $1 }')" "balanced"

# ── The per-source memory ────────────────────────────────────────────────────

export MONARCH_POWERPROFILES_STATE_DIR="$TMP/state"

: >"$PPD_CALLS"
"$SET" ac performance
assert_equals "an explicit choice is applied" "$(tail -1 "$PPD_CALLS")" "performance"
assert_equals "and remembered against its source" "$(<"$TMP/state/ac")" "performance"

: >"$PPD_CALLS"
"$SET" battery power-saver
assert_equals "the other source keeps its own" "$(<"$TMP/state/ac")" "performance"
assert_equals "and gets what it was given" "$(<"$TMP/state/battery")" "power-saver"

: >"$PPD_CALLS"
"$SET" ac
assert_equals "with no profile it restores what that source remembers" \
  "$(tail -1 "$PPD_CALLS")" "performance"

: >"$PPD_CALLS"
ON_BATTERY=true "$SET"
assert_equals "autodetect follows UPower onto battery" "$(tail -1 "$PPD_CALLS")" "power-saver"
: >"$PPD_CALLS"
ON_BATTERY=false "$SET"
assert_equals "and back onto mains" "$(tail -1 "$PPD_CALLS")" "performance"

# A restore that wrote itself back would erase the other source's pick the first
# time the fallback stood in for a source that had never been chosen.
rm -rf "$TMP/state"
: >"$PPD_CALLS"
"$SET" ac
assert_equals "an unremembered mains falls back to the fastest profile" \
  "$(tail -1 "$PPD_CALLS")" "performance"
[[ -e $TMP/state/ac ]] && fail "a restore does not write itself back"
pass "a restore does not write itself back"

: >"$PPD_CALLS"
"$SET" battery
assert_equals "an unremembered battery falls back to balanced" \
  "$(tail -1 "$PPD_CALLS")" "balanced"

if "$SET" ac turbo 2>"$TMP/err"; then
  fail "a profile this machine does not offer is refused"
fi
pass "a profile this machine does not offer is refused"
assert_equals "and says which one" "$(<"$TMP/err")" \
  "Error: power profile is not available: turbo"

if PPD_FAIL=1 "$SET" ac balanced 2>/dev/null; then
  fail "a failed apply exits non-zero"
fi
pass "a failed apply exits non-zero"
[[ -e $TMP/state/ac ]] && fail "and is not remembered as though it worked"
pass "and is not remembered as though it worked"

# ── The session watcher ──────────────────────────────────────────────────────

# monarch-powerprofiles-set has to be reachable by name, the way the timer runs
# it, and it must write where the assertions look.
export MONARCH_POWERPROFILES_STATE_DIR="$TMP/state"
rm -rf "$TMP/state" "$XDG_RUNTIME_DIR"/monarch_*
mkdir -p "$TMP/state"
printf 'power-saver\n' >"$TMP/state/battery"
printf 'performance\n' >"$TMP/state/ac"

export UP_STATE=charging UP_PERCENT=87
: >"$PPD_CALLS"
"$MONITOR"
assert_equals "the first run only records the supply it found" \
  "$(grep -c . "$PPD_CALLS")" "0"
assert_equals "and records it" "$(<"$XDG_RUNTIME_DIR/monarch_power_source")" "ac"

: >"$PPD_CALLS"
"$MONITOR"
assert_equals "a run with the cable unmoved changes nothing" "$(grep -c . "$PPD_CALLS")" "0"

# udev sees the cable move instantly but runs as root, where the per-source
# memory does not exist. This timer is what carries the switch instead.
printf '0\n' >"$TMP/sys/AC/online"
: >"$PPD_CALLS"
UP_STATE=discharging "$MONITOR"
assert_equals "unplugging restores what battery remembers" \
  "$(tail -1 "$PPD_CALLS")" "power-saver"
assert_equals "and the new supply is recorded" \
  "$(<"$XDG_RUNTIME_DIR/monarch_power_source")" "battery"

printf '1\n' >"$TMP/sys/AC/online"
: >"$PPD_CALLS"
"$MONITOR"
assert_equals "plugging back in restores what mains remembers" \
  "$(tail -1 "$PPD_CALLS")" "performance"

# ── The low-battery warning ──────────────────────────────────────────────────

printf '0\n' >"$TMP/sys/AC/online"
: >"$NOTIFY_CALLS"
UP_STATE=discharging UP_PERCENT=8 "$MONITOR"
assert_equals "a low discharging battery warns" "$(grep -c 'down to 8%' "$NOTIFY_CALLS")" "1"

UP_STATE=discharging UP_PERCENT=8 "$MONITOR"
assert_equals "and warns once, not on every tick" "$(grep -c 'down to 8%' "$NOTIFY_CALLS")" "1"

: >"$NOTIFY_CALLS"
printf '1\n' >"$TMP/sys/AC/online"
UP_STATE=charging UP_PERCENT=42 "$MONITOR"
UP_STATE=discharging UP_PERCENT=8 "$MONITOR"
printf '1\n' >"$TMP/sys/AC/online"
assert_equals "plugging in re-arms it for the next discharge" \
  "$(grep -c 'down to 8%' "$NOTIFY_CALLS")" "1"

echo
echo "All power tests passed."
