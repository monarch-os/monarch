#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export PATH="$TMP/bin:$ROOT/bin:/usr/bin"
mkdir -p "$HOME/.local/bin" "$TMP/bin" "$TMP/node/bin"

cat > "$TMP/bin/mise" <<EOF
#!/bin/bash
[[ \$1 == "where" ]] && printf '%s\n' "$TMP/node"
EOF

cat > "$TMP/node/bin/node" <<'EOF'
#!/bin/bash
exec "$@"
EOF

cat > "$TMP/node/bin/npx" <<'EOF'
#!/bin/bash
if [[ $* == *"-- true" ]]; then
  exit 0
fi
if [[ $* == *"-- which codex" ]]; then
  command -v codex
  exit
fi
if [[ $* == *"-- codex --version" ]]; then
  echo "codex launched"
  exit
fi
exit 2
EOF

chmod +x "$TMP/bin/mise" "$TMP/node/bin/node" "$TMP/node/bin/npx"
"$ROOT/bin/monarch-npx-install" @openai/codex codex
export PATH="$HOME/.local/bin:$PATH"

output=$(timeout 2 "$HOME/.local/bin/codex" --version) || {
  echo "npx wrapper recursed into itself instead of launching the package" >&2
  exit 1
}

[[ $output == "codex launched" ]] || {
  echo "unexpected wrapper output: $output" >&2
  exit 1
}

echo "All npx install tests passed."
