#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export PATH="$TMP/bin:$ROOT/bin:/usr/bin"
export TEST_LOG="$TMP/calls"
mkdir -p "$TMP/bin"

cat > "$TMP/bin/mise" <<'EOF'
#!/bin/bash
printf 'mise %s\n' "$*" >> "$TEST_LOG"
case "$1" in
where) [[ ${MISE_INSTALLED:-false} == "true" ]] ;;
use) exit 0 ;;
x)
  shift 3
  printf 'run %s\n' "$*"
  ;;
esac
EOF

cat > "$TMP/bin/monarch-launch-floating-terminal-with-presentation" <<'EOF'
#!/bin/bash
printf 'launch %s\n' "$*" >> "$TEST_LOG"
EOF

cat > "$TMP/bin/monarch-agent" <<'EOF'
#!/bin/bash
printf 'agent %s\n' "$*" >> "$TEST_LOG"
EOF

cat > "$TMP/bin/monarch-cmd-present" <<'EOF'
#!/bin/bash
exit 1
EOF

cat > "$TMP/bin/notify-send" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "$TMP/bin/"*

"$ROOT/bin/monarch-mise-install" npm:@openai/codex codex
output=$("$HOME/.local/bin/codex" --version)
[[ $output == "run codex --version" ]]
grep -qx 'mise use -g --quiet npm:@openai/codex' "$TEST_LOG"
grep -qx 'mise x npm:@openai/codex -- codex --version' "$TEST_LOG"

: > "$TEST_LOG"
MISE_INSTALLED=false "$ROOT/bin/monarch-default-agent" codex
grep -qx 'launch monarch-default-agent --install codex' "$TEST_LOG"

: > "$TEST_LOG"
MISE_INSTALLED=true "$ROOT/bin/monarch-default-agent" grok
grep -qx 'mise where npm:@xai-official/grok' "$TEST_LOG"
grep -qx 'mise use -g npm:@xai-official/grok' "$TEST_LOG"
grep -qx 'agent ' "$TEST_LOG"
[[ $(<"$HOME/.config/monarch/defaults/agent") == "grok" ]]

for case in \
  "oh-my-pi|omp|github:can1357/oh-my-pi" \
  "openrouter|ori|github:OpenRouterLabs/ori-releases" \
  "gemini|agy|antigravity-cli"; do
  IFS='|' read -r input expected package <<< "$case"
  : > "$TEST_LOG"
  MISE_INSTALLED=true "$ROOT/bin/monarch-default-agent" "$input"
  grep -qx "mise where $package" "$TEST_LOG"
  grep -qx "mise use -g $package" "$TEST_LOG"
  [[ $(<"$HOME/.config/monarch/defaults/agent") == "$expected" ]]
done

echo "All mise agent tests passed."
