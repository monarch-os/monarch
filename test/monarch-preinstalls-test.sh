#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL="$ROOT/bin/monarch-install-preinstalls"
REMOVE="$ROOT/bin/monarch-remove-preinstalls"
REFRESH="$ROOT/bin/monarch-refresh-applications"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

package_list() {
  local command="$1" script="$2"

  awk -v command="$command" '
    $1 == command { reading = 1; next }
    reading && $1 !~ /^[[:alnum:]-]+$/ { exit }
    reading { print $1 }
  ' "$script"
}

install_packages=$(package_list monarch-pkg-add "$INSTALL")
remove_packages=$(package_list monarch-pkg-drop "$REMOVE")

if [[ $install_packages != "$remove_packages" ]]; then
  printf 'Install and remove package lists differ\n' >&2
  diff -u <(printf '%s\n' "$remove_packages") <(printf '%s\n' "$install_packages") >&2 || true
  exit 1
fi

grep -q 'monarch-refresh-applications' "$INSTALL"
grep -q 'monarch-state clear preinstalls-removed' "$INSTALL"
grep -q 'monarch-state set preinstalls-removed' "$REMOVE"

printf 'Preinstall restore matches removal (%s packages)\n' "$(wc -l <<<"$install_packages")"

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

chmod +x "$TMP/bin"/*

marker="$TMP/home/.local/state/monarch/preinstalls-removed"
touch "$marker"

if HOME="$TMP/home" PATH="$TMP/bin:$ROOT/bin:/usr/bin" PKG_ADD_STATUS=23 "$INSTALL" >/dev/null 2>&1; then
  echo "A failed package restore returned success" >&2
  exit 1
fi

if [[ ! -f $marker ]]; then
  echo "A failed package restore cleared the removal marker" >&2
  exit 1
fi

HOME="$TMP/home" PATH="$TMP/bin:$ROOT/bin:/usr/bin" "$INSTALL" >/dev/null

if [[ -f $marker ]]; then
  echo "A successful restore kept the removal marker" >&2
  exit 1
fi

if [[ ! -f $TMP/home/noctalia-restarted ]]; then
  echo "A successful restore did not refresh Noctalia's application index" >&2
  exit 1
fi

echo "Preinstall state changes only after a complete restore"

if rg -q 'install/packaging' "$REFRESH"; then
  echo "Application refresh still invokes the removed packaging pipeline" >&2
  exit 1
fi
grep -qF 'install/user/mise.sh' "$REFRESH"

echo "Application refresh uses packaged launchers and the user mise stage"
