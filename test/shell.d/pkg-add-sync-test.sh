#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/db/sync"
export PATH="$tmp/bin:$PATH" TEST_TMP="$tmp" MONARCH_PATH="$root" MONARCH_LANGUAGE=fr

cat >"$tmp/bin/monarch-pkg-missing" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$tmp/bin/pacman-conf" <<'EOF'
#!/bin/bash
[[ ${CONFIG_FAIL:-0} == 0 ]] || exit 1
case "$1" in
  DBPath) echo "$TEST_TMP/db" ;;
  --repo-list) printf '%s\n' core extra ;;
  *) exit 1 ;;
esac
EOF
cat >"$tmp/bin/gum" <<'EOF'
#!/bin/bash
echo confirm >> "$TEST_TMP/calls"
printf '%s\n' "$@" > "$TEST_TMP/confirmation"
exit "${CONFIRM_STATUS:-0}"
EOF
cat >"$tmp/bin/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$TEST_TMP/calls"
EOF
cat >"$tmp/bin/monarch-update-pacman" <<'EOF'
#!/bin/bash
printf 'update %s\n' "$*" >> "$TEST_TMP/calls"
[[ ${UPDATE_STATUS:-0} == 0 ]] || exit "$UPDATE_STATUS"
if [[ ${SKIP_SYNC:-0} == 0 ]]; then
  touch "$TEST_TMP/db/sync/core.db" "$TEST_TMP/db/sync/extra.db"
fi
EOF
cat >"$tmp/bin/pacman" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$tmp/bin/"*

touch "$tmp/db/sync/core.db"
"$root/bin/monarch-pkg-add" example 2>"$tmp/message"
grep -q 'mettre à jour l’ensemble du système' "$tmp/message" || { echo 'system-wide update was not explained' >&2; exit 1; }
grep -q 'Mettre à jour tout le système' "$tmp/confirmation" || { echo 'system-wide update was not confirmed' >&2; exit 1; }
expected=$'confirm\nupdate -Syu\npacman -S --noconfirm --needed -- example'
[[ $(<"$tmp/calls") == "$expected" ]] || { echo 'missing database did not trigger an update before installation' >&2; exit 1; }

: >"$tmp/calls"
"$root/bin/monarch-pkg-add" example
[[ $(<"$tmp/calls") == 'pacman -S --noconfirm --needed -- example' ]] || { echo 'existing databases unexpectedly triggered an update' >&2; exit 1; }

rm "$tmp/db/sync/extra.db"
for scenario in cancelled failed incomplete config; do
  : >"$tmp/calls"
  if [[ $scenario == cancelled ]]; then
    if CONFIRM_STATUS=1 "$root/bin/monarch-pkg-add" example; then exit 1; fi
  elif [[ $scenario == failed ]]; then
    if UPDATE_STATUS=1 "$root/bin/monarch-pkg-add" example; then exit 1; fi
  elif [[ $scenario == incomplete ]]; then
    if SKIP_SYNC=1 "$root/bin/monarch-pkg-add" example; then exit 1; fi
  else
    if CONFIG_FAIL=1 "$root/bin/monarch-pkg-add" example; then exit 1; fi
  fi
  if grep -q 'pacman -S --' "$tmp/calls"; then
    echo "$scenario update did not stop installation" >&2
    exit 1
  fi
done
