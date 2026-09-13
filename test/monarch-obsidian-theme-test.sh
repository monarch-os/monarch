#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export PATH="$TMP/bin:/usr/bin"
export NOCTALIA_CALLS="$TMP/noctalia-calls"
mkdir -p "$HOME/Documents/first/.obsidian" "$HOME/Downloads/second/.obsidian" "$TMP/bin"

cat >"$TMP/bin/noctalia" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOCTALIA_CALLS"
find "$HOME" -maxdepth 4 -name .obsidian -type d | while read -r vault; do
  mkdir -p "$vault/snippets"
  touch "$vault/snippets/noctalia.css"
  printf '{"enabledCssSnippets":["noctalia"]}\n' >"$vault/appearance.json"
done
printf 'ok\n'
EOF
chmod +x "$TMP/bin/noctalia"

"$ROOT/bin/monarch-obsidian-theme"

grep -qx 'msg templates-apply' "$NOCTALIA_CALLS"
[[ -f $HOME/Documents/first/.obsidian/snippets/noctalia.css ]]
[[ -f $HOME/Downloads/second/.obsidian/snippets/noctalia.css ]]
jq -e '.enabledCssSnippets | index("noctalia") != null' \
  "$HOME/Documents/first/.obsidian/appearance.json" >/dev/null

: >"$NOCTALIA_CALLS"
"$ROOT/bin/monarch-obsidian-theme"
[[ ! -s $NOCTALIA_CALLS ]]

grep -Fqx 'PathChanged=%h/.config/obsidian/obsidian.json' \
  "$ROOT/default/systemd/user/monarch-obsidian-theme.path"
grep -Fq 'monarch-obsidian-theme.path' "$ROOT/install/user/first-run/enable-user-units.sh"

echo "Obsidian vault discovery and template watcher checks pass"
