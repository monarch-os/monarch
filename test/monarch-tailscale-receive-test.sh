#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

downloads="$TEST_ROOT/downloads"
mkdir -p "$TEST_ROOT/bin" "$downloads" "$TEST_ROOT/outbox"
printf 'mine' >"$downloads/unrelated.txt"

fail() {
  echo "not ok - $1" >&2
  exit 1
}

pass() {
  echo "ok - $1"
}

cat >"$TEST_ROOT/bin/tailscale" <<EOF
#!/bin/bash
target="\${*: -1}"
[[ -n \${DECOY:-} ]] && printf 'iso' >"$downloads/\$DECOY"
mv "$TEST_ROOT/outbox/"* "\$target/"
EOF

cat >"$TEST_ROOT/bin/notify-send" <<EOF
#!/bin/bash
printf '%s\0' "\$@" >>"$TEST_ROOT/notifications"
printf '\n' >>"$TEST_ROOT/notifications"
printf '%s\n' "\${NOTIFY_ACTION:-}"
EOF

cat >"$TEST_ROOT/bin/xdg-open" <<EOF
#!/bin/bash
printf '%s\n' "\$1" >>"$TEST_ROOT/opened"
EOF

chmod +x "$TEST_ROOT/bin/"*

receive() {
  local expected=$1
  shift

  : >"$TEST_ROOT/notifications"
  PATH="$TEST_ROOT/bin:$PATH" "$@" "$ROOT/bin/monarch-tailscale-receive" --once "$downloads"

  for _ in {1..50}; do
    (($(wc -l <"$TEST_ROOT/notifications") >= expected)) && break
    sleep 0.1
  done
}

printf 'png' >"$TEST_ROOT/outbox/photo.png"
printf 'pdf' >"$TEST_ROOT/outbox/notes with space.pdf"
receive 2 env NOTIFY_ACTION=open

[[ -f $downloads/photo.png && -f "$downloads/notes with space.pdf" ]] || fail "receiver saves incoming files"
pass "receiver saves incoming files"

grep -Fzq -- "--icon=$downloads/photo.png" "$TEST_ROOT/notifications" || fail "receiver previews images"
pass "receiver previews images"

grep -Fzq -- "--urgency=critical" "$TEST_ROOT/notifications" || fail "receiver announces persistent critical notifications"
grep -Fzq -- "--expire-time=0" "$TEST_ROOT/notifications" || fail "receiver keeps notifications available"
pass "receiver keeps notifications available"

for _ in {1..50}; do
  [[ -f $TEST_ROOT/opened ]] && (($(wc -l <"$TEST_ROOT/opened") >= 2)) && break
  sleep 0.1
done
grep -Fx "$downloads/photo.png" "$TEST_ROOT/opened" >/dev/null || fail "notification opens the received image"
grep -Fx "$downloads/notes with space.pdf" "$TEST_ROOT/opened" >/dev/null || fail "notification preserves spaced paths"
pass "notification opens received files safely"

grep -Fzq 'unrelated.txt' "$TEST_ROOT/notifications" && fail "receiver announced an unrelated download"
pass "receiver ignores unrelated downloads"

printf 'png' >"$TEST_ROOT/outbox/photo.png"
receive 1 env DECOY=browser-download.iso

[[ -f $downloads/photo-1.png ]] || fail "receiver overwrote a name collision"
grep -Fzq 'Received photo-1.png' "$TEST_ROOT/notifications" || fail "receiver did not announce renamed collision"
pass "receiver preserves name collisions"

grep -Fzq 'browser-download.iso' "$TEST_ROOT/notifications" && fail "receiver announced a concurrent download"
[[ -z $(ls -A "$downloads/.monarch-taildrop") ]] || fail "receiver left delivered files in staging"
pass "receiver isolates its staging directory"
