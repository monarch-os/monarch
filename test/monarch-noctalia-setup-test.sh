#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

home="$TMP/home"
mkdir -p "$home/.local/state/noctalia"

settings_pkgbuild="$ROOT/../monarch-pkgs/pkgbuilds/monarch-settings/PKGBUILD"
grep -qF 'default/noctalia/plugins/. "$pkgdir/etc/skel/.local/share/noctalia/plugins/"' \
  "$settings_pkgbuild"
grep -qF 'touch "$pkgdir/etc/skel/.local/state/noctalia/.setup-complete"' \
  "$settings_pkgbuild"

marker="$home/.local/state/noctalia/.setup-complete"
touch "$marker"

echo "Fresh installs skip Noctalia's setup panel"

if ! grep -q 'monarch/theme' "$ROOT/install/user/first-run/enable-noctalia-plugins.sh"; then
  echo "Fresh installs do not enable the Monarch theme plugin" >&2
  exit 1
fi

echo "Fresh installs enable the Monarch theme plugin"
