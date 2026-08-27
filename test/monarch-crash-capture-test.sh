#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/home"
SYSTEMCTL_LOG="$TMP/systemctl.log"
ACTION_LOG="$TMP/action.log"
export SYSTEMCTL_LOG ACTION_LOG

cat >"$TMP/bin/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
EOF

cat >"$TMP/bin/monarch-notification-send" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$TMP/bin/monarch-notification-wait" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$TMP/bin/monarch-notification-action" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$ACTION_LOG"
EOF

cat >"$TMP/bin/monarch-default-agent" <<'EOF'
#!/bin/bash
printf 'codex\n'
EOF

cat >"$TMP/bin/journalctl" <<EOF
#!/bin/bash
printf '%s\n' '{"_UID":"$(id -u)","COREDUMP_COMM":"crasher","COREDUMP_PID":"4242","COREDUMP_EXE":"/usr/bin/crasher","COREDUMP_SIGNAL_NAME":"SIGSEGV"}'
EOF

chmod +x "$TMP/bin/"*

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

PATH="$TMP/bin:$ROOT/bin:/usr/bin" HOME="$TMP/home" MONARCH_PATH="$ROOT" \
  "$ROOT/bin/monarch-crash-watch"

grep -F 'Process crashed: crasher' "$ACTION_LOG" >/dev/null
grep -F 'Click to diagnose with AI. Nothing is sent automatically.' "$ACTION_LOG" >/dev/null
grep -F 'monarch-agent-crash 4242 crasher /usr/bin/crasher SIGSEGV' "$ACTION_LOG" >/dev/null

service="$ROOT/default/systemd/user/monarch-crash-watch.service"
grep -Fx 'ConditionPathExists=!%h/.local/state/monarch/toggles/crash-capture-off' "$service" >/dev/null
grep -F 'monarch-crash-watch.service' "$ROOT/install/user/first-run/enable-user-units.sh" >/dev/null

if grep -Eqi 'upload|send.*core' "$ROOT/bin/monarch-agent-crash"; then
  echo "Crash launcher suggests sending the core dump" >&2
  exit 1
fi

echo "Crash capture toggle, watcher, service and privacy checks pass"
