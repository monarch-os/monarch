#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL="$ROOT/bin/monarch-install-preinstalls"
REMOVE="$ROOT/bin/monarch-remove-preinstalls"
REFRESH="$ROOT/bin/monarch-refresh-applications"
PACKAGES="$ROOT/install/monarch-preinstalls.packages"
PROVISION_USER="$ROOT/bin/monarch-provision-user"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

grep -qF 'install/monarch-preinstalls.packages' "$INSTALL"
grep -qF 'install/monarch-preinstalls.packages' "$REMOVE"
grep -qFx bettercap "$PACKAGES"
grep -qFx xournalpp "$PACKAGES"

grep -q 'monarch-refresh-applications' "$INSTALL"
grep -q 'monarch-state clear preinstalls-removed' "$INSTALL"
grep -q 'monarch-state set preinstalls-removed' "$REMOVE"

printf 'Preinstall install and removal share one manifest (%s packages)\n' "$(grep -cvE '^[[:space:]]*(#|$)' "$PACKAGES")"

grep -qF -- '--skip-preinstalls' "$PROVISION_USER"
grep -qF 'monarch-remove-preinstall-artifacts' "$PROVISION_USER"
if rg -q 'user\.kdl|monarch-refresh-niri' "$REMOVE" "$ROOT/bin/monarch-remove-preinstall-artifacts"; then
  echo "Removing preinstalls still overwrites the user's Niri configuration" >&2
  exit 1
fi
echo "Minimal provisioning preserves user.kdl"

mkdir -p "$TMP/bin" "$TMP/home/.local/state/monarch"

cat >"$TMP/bin/gum" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$TMP/bin/monarch-refresh-applications" <<'EOF'
#!/bin/bash
mkdir -p "$HOME/.local/share/applications"
touch "$HOME/.local/share/applications/ChatGPT.desktop"
touch "$HOME/.local/share/applications/Disk Usage.desktop"
EOF

cat >"$TMP/bin/monarch-pkg-add" <<'EOF'
#!/bin/bash
exit "${PKG_ADD_STATUS:-0}"
EOF

cat >"$TMP/bin/monarch-restart-noctalia" <<'EOF'
#!/bin/bash
touch "$HOME/noctalia-restarted"
EOF

cat >"$TMP/bin/monarch-webapp-remove-all" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$TMP/bin/monarch-tui-remove-all" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "$TMP/bin"/*

mkdir -p "$TMP/home/.config/niri" "$TMP/home/.local/bin"
printf 'custom user config\n' >"$TMP/home/.config/niri/user.kdl"
touch "$TMP/home/.local/bin/codex"
HOME="$TMP/home" PATH="$TMP/bin:$ROOT/bin:/usr/bin" "$ROOT/bin/monarch-remove-preinstall-artifacts"
grep -qxF 'custom user config' "$TMP/home/.config/niri/user.kdl"
[[ ! -e $TMP/home/.local/bin/codex ]]
echo "Preinstall artifact cleanup preserves user.kdl"

marker="$TMP/home/.local/state/monarch/preinstalls-removed"
touch "$marker"

if HOME="$TMP/home" MONARCH_PATH="$ROOT" PATH="$TMP/bin:$ROOT/bin:/usr/bin" PKG_ADD_STATUS=23 "$INSTALL" >/dev/null 2>&1; then
  echo "A failed package restore returned success" >&2
  exit 1
fi

if [[ ! -f $marker ]]; then
  echo "A failed package restore cleared the removal marker" >&2
  exit 1
fi

HOME="$TMP/home" MONARCH_PATH="$ROOT" PATH="$TMP/bin:$ROOT/bin:/usr/bin" "$INSTALL" >/dev/null

if [[ -f $marker ]]; then
  echo "A successful restore kept the removal marker" >&2
  exit 1
fi

if [[ ! -f $TMP/home/noctalia-restarted ]]; then
  echo "A successful restore did not refresh Noctalia's application index" >&2
  exit 1
fi

echo "Preinstall state changes only after a complete restore"

if grep -q 'install/packaging' "$REFRESH"; then
  echo "Application refresh still invokes the removed packaging pipeline" >&2
  exit 1
fi
grep -qF 'install/user/mise.sh' "$REFRESH"

echo "Application refresh uses packaged launchers and the user mise stage"
