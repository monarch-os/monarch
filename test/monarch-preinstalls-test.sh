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

fixture="$TMP/refresh-fixture"
refresh_home="$TMP/refresh-home"
mkdir -p "$fixture/applications/icons" "$fixture/applications/hidden" \
  "$fixture/install/packaging" "$refresh_home/.local/share"
touch "$fixture/applications/icons/test.png"
touch "$fixture/applications/Test.desktop" "$fixture/applications/hidden/Hidden.desktop"
ln -s "$fixture" "$refresh_home/.local/share/monarch"

cat >"$TMP/bin/gtk-update-icon-cache" <<'EOF'
#!/bin/bash
exit 1
EOF

cat >"$TMP/bin/update-desktop-database" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$TMP/bin/monarch-cmd-present" <<'EOF'
#!/bin/bash
exit 1
EOF

for step in icons tuis npx; do
  printf 'touch "$HOME/%s-ran"\n' "$step" >"$fixture/install/packaging/$step.sh"
done

cat >"$fixture/install/packaging/webapps.sh" <<'EOF'
(( ${REFRESH_WEBAPPS_FAIL:-0} == 0 )) || exit "$REFRESH_WEBAPPS_FAIL"
touch "$HOME/webapps-ran"
EOF

chmod +x "$TMP/bin"/*

HOME="$refresh_home" MONARCH_PATH="$fixture" PATH="$TMP/bin:/usr/bin" "$REFRESH"

for step in icons webapps tuis npx; do
  if [[ ! -f $refresh_home/$step-ran ]]; then
    echo "Application refresh skipped $step after a non-critical cache failure" >&2
    exit 1
  fi
done

if HOME="$refresh_home" MONARCH_PATH="$fixture" PATH="$TMP/bin:/usr/bin" \
  REFRESH_WEBAPPS_FAIL=17 "$REFRESH" >/dev/null 2>&1; then
  echo "Application refresh masked a packaging failure" >&2
  exit 1
fi

echo "Application refresh propagates packaging failures"
