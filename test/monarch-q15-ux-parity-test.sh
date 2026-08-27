#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/home/.config/niri"

cat > "$TMP/bin/xkbcli" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TMP/bin/xkbcli"

cat > "$TMP/home/.config/niri/config.kdl" <<EOF
include "$ROOT/default/niri/binds.kdl"
EOF

output=$(HOME="$TMP/home" PATH="$TMP/bin:$PATH" "$ROOT/bin/monarch-menu-keybindings" --print)
grep -F 'SUPER + Q / SUPER SHIFT + Q' <<<"$output" | grep -Fq 'Close active window'
[[ $(grep -Fc 'Close active window' <<<"$output") == 1 ]]
grep -Fqx 'clipboard_history_max_entries = 500' "$ROOT/config/noctalia/config.toml"

echo "All Q15 UX parity tests passed."
