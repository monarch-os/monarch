#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fixture="$TMP/fixture"
home="$TMP/home"
mkdir -p "$fixture/config/noctalia" \
  "$fixture/default/noctalia/plugins/test" \
  "$home" "$TMP/bin"
touch "$fixture/config/noctalia/config.toml"
touch "$fixture/default/noctalia/plugins/test/plugin.toml"
touch "$fixture/default/bashrc" "$fixture/default/zshrc"

cat >"$TMP/bin/sudo" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TMP/bin/sudo"

HOME="$home" MONARCH_PATH="$fixture" USER=test PATH="$TMP/bin:/usr/bin" \
  bash "$ROOT/install/config/config.sh"

marker="$home/.local/state/noctalia/.setup-complete"
if [[ ! -f $marker ]]; then
  echo "Fresh installs leave Noctalia's setup panel enabled" >&2
  exit 1
fi

echo "Fresh installs skip Noctalia's setup panel"

rm "$marker"
HOME="$home" bash "$ROOT/migrations/1787598613.sh" >/dev/null

if [[ ! -f $marker ]]; then
  echo "Upgraded installs leave Noctalia's setup panel enabled" >&2
  exit 1
fi

echo "Upgraded installs skip Noctalia's setup panel"

if ! grep -q 'monarch/menu monarch/theme monarch/wifi-qr' "$ROOT/install/first-run/welcome.sh"; then
  echo "Fresh installs do not enable the Monarch theme plugin" >&2
  exit 1
fi

echo "Fresh installs enable the Monarch theme plugin"
