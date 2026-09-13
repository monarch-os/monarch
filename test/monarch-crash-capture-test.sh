#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/home"
SYSTEMCTL_LOG="$TMP/systemctl.log"
ACTION_LOG="$TMP/action.log"
JOURNAL_ENTRIES="$TMP/journal.jsonl"
export SYSTEMCTL_LOG ACTION_LOG JOURNAL_ENTRIES

cat >"$TMP/bin/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
EOF

cat >"$TMP/bin/monarch-notification-send" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$ACTION_LOG"
EOF

cat >"$TMP/bin/monarch-notification-wait" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$TMP/bin/monarch-default-agent" <<'EOF'
#!/bin/bash
printf 'codex\n'
EOF

cat >"$TMP/bin/journalctl" <<'EOF'
#!/bin/bash
cat "$JOURNAL_ENTRIES"
EOF

chmod +x "$TMP/bin/"*

crash_entry() {
  local comm=$1 exe=$2 pid=${3:-4242}

  jq -cn --arg uid "$UID" --arg comm "$comm" --arg exe "$exe" --arg pid "$pid" \
    '{_UID: $uid, COREDUMP_COMM: $comm, COREDUMP_PID: $pid,
      COREDUMP_EXE: $exe, COREDUMP_SIGNAL_NAME: "SIGSEGV"}' >>"$JOURNAL_ENTRIES"
}

run_watch() {
  : >"$ACTION_LOG"
  PATH="$TMP/bin:$ROOT/bin:/usr/bin" HOME="$TMP/home" MONARCH_PATH="$ROOT" \
  MONARCH_CRASH_DEDUPE_SECONDS=0 \
    "$ROOT/bin/monarch-crash-watch"
}

crash_mute() {
  HOME="$TMP/home" PATH="$TMP/bin:$ROOT/bin:/usr/bin" \
    "$ROOT/bin/monarch-crash-mute" "$@"
}

PATH="$TMP/bin:$ROOT/bin:/usr/bin" HOME="$TMP/home" \
  "$ROOT/bin/monarch-toggle-crash-capture"

flag="$TMP/home/.local/state/monarch/toggles/crash-capture-off"
[[ -f $flag ]]
grep -Fqx -- '--user stop monarch-crash-watch.service' "$SYSTEMCTL_LOG"
HOME="$TMP/home" PATH="$TMP/bin:$ROOT/bin:/usr/bin" \
  "$ROOT/bin/monarch-menu" --state |
  jq -e '.guards["trigger.toggle.crash-capture:c"] == false' >/dev/null

: >"$SYSTEMCTL_LOG"
PATH="$TMP/bin:$ROOT/bin:/usr/bin" HOME="$TMP/home" \
  "$ROOT/bin/monarch-toggle-crash-capture"
[[ ! -f $flag ]]
grep -Fqx -- '--user start monarch-crash-watch.service' "$SYSTEMCTL_LOG"

HOME="$TMP/home" PATH="$TMP/bin:$ROOT/bin:/usr/bin" \
  "$ROOT/bin/monarch-menu" --state |
  jq -e '.guards["trigger.toggle.crash-capture:c"] == true' >/dev/null

: >"$JOURNAL_ENTRIES"
crash_entry crasher /usr/bin/crasher
run_watch

grep -F 'Process crashed: crasher' "$ACTION_LOG" >/dev/null
grep -F 'Click to diagnose with AI. Nothing is sent automatically.' "$ACTION_LOG" >/dev/null
grep -F 'monarch-agent-crash 4242 crasher /usr/bin/crasher SIGSEGV' "$ACTION_LOG" >/dev/null

crash_mute /usr/bin/crasher on >/dev/null
[[ -f $TMP/home/.local/state/monarch/toggles/crash-ignore/crasher ]]
crash_mute crasher status | grep -Fqx 'Crash notifications for crasher are muted.'
crash_mute | grep -Fqx crasher

: >"$JOURNAL_ENTRIES"
crash_entry crasher /usr/bin/crasher
crash_entry other /usr/bin/other 4243
run_watch
! grep -F 'Process crashed: crasher' "$ACTION_LOG" >/dev/null
grep -F 'Process crashed: other' "$ACTION_LOG" >/dev/null

crash_mute crasher off >/dev/null
if crash_mute crasher status >/dev/null; then
  echo "Unmuted program reports a muted status" >&2
  exit 1
fi

: >"$JOURNAL_ENTRIES"
crash_entry crasher /usr/bin/crasher
run_watch
grep -F 'Process crashed: crasher' "$ACTION_LOG" >/dev/null

for bad_name in '' . .. / -h $'bad\nname' 'bad$name' 'bad;name'; do
  if crash_mute "$bad_name" >/dev/null 2>&1; then
    echo "Accepted invalid program name: $bad_name" >&2
    exit 1
  fi
done

[[ ! -e $TMP/home/.local/state/monarch/toggles/'bad$name' ]]

: >"$JOURNAL_ENTRIES"
crash_entry a/../fallback -
run_watch
grep -F 'Process crashed: fallback' "$ACTION_LOG" >/dev/null

: >"$JOURNAL_ENTRIES"
crash_entry 'bad$name' -
crash_entry '' - 4243
run_watch
unknown_count=$(grep -Fc 'Process crashed: unknown' "$ACTION_LOG")
((unknown_count == 2))

crash_mute unknown on >/dev/null
: >"$JOURNAL_ENTRIES"
crash_entry / -
crash_entry other /usr/bin/other 4243
run_watch
! grep -F 'Process crashed: unknown' "$ACTION_LOG" >/dev/null
grep -F 'Process crashed: other' "$ACTION_LOG" >/dev/null

[[ ! -f $TMP/home/.local/state/monarch/toggles/crash-capture-off ]]

service="$ROOT/default/systemd/user/monarch-crash-watch.service"
grep -Fx 'ConditionPathExists=!%h/.local/state/monarch/toggles/crash-capture-off' "$service" >/dev/null
grep -F 'monarch-crash-watch.service' "$ROOT/install/user/first-run/enable-user-units.sh" >/dev/null

if grep -Eqi 'upload|send.*core' "$ROOT/bin/monarch-agent-crash"; then
  echo "Crash launcher suggests sending the core dump" >&2
  exit 1
fi

grep -Fq 'monarch-crash-mute' "$ROOT/default/agents/skills/diagnose-crash/SKILL.md"
grep -Fq 'GROUP_DESCRIPTIONS[crash]' "$ROOT/bin/monarch"

echo "Crash capture toggle, per-program mute, watcher, service and privacy checks pass"
