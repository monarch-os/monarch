#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

export HOME="$test_tmp/home"
export T3CODE_HOME="$test_tmp/t3 home"
palette="$test_tmp/palette.json"
theme="$T3CODE_HOME/userdata/themes/monarch.json"

cat >"$palette" <<'JSON'
{
  "dark": {
    "mPrimary": "#7e33ff",
    "mSurface": "#1a1b26",
    "mOnSurface": "#a9b1d6",
    "mSurfaceVariant": "#24283b",
    "mOutline": "#565f89",
    "mError": "#f7768e",
    "terminal": {
      "normal": {"yellow": "#e0af68"},
      "bright": {"white": "#acb0d0"},
      "selectionBg": "#7e33ff"
    }
  }
}
JSON

"$ROOT/bin/monarch-theme-set-t3-code" "$palette" dark
[[ ! -e $T3CODE_HOME ]] || {
  echo "T3 state was created for an app that is not installed" >&2
  exit 1
}

mkdir -p "$T3CODE_HOME/userdata"
printf '%s\n' '{"keep":"settings"}' >"$T3CODE_HOME/userdata/settings.json"
"$ROOT/bin/monarch-theme-set-t3-code" "$palette" dark

jq -e '
  .name == "Monarch" and .appearance == "dark" and
  .canvas == "#1a1b26" and .accent == "#7e33ff" and
  .colors.toolbarForeground == "#a9b1d6" and
  .colors.sidebar == "#24283b" and
  .colors.error == "#f7768e" and
  .colors.warning == "#e0af68" and
  .colors.terminalCursor == "#acb0d0" and
  .colors.terminalSelection == "#7e33ff"
' "$theme" >/dev/null
[[ $(<"$T3CODE_HOME/userdata/settings.json") == '{"keep":"settings"}' ]] || {
  echo "T3 settings were rewritten while publishing the theme" >&2
  exit 1
}
! compgen -G "$theme.*" >/dev/null || {
  echo "T3 theme publication left a staging file" >&2
  exit 1
}
echo "T3 receives an atomic theme generated from the active Noctalia palette"

cp "$theme" "$test_tmp/previous.json"
jq '.dark.mPrimary = "invalid"' "$palette" >"$test_tmp/invalid.json"
"$ROOT/bin/monarch-theme-set-t3-code" "$test_tmp/invalid.json" dark
cmp "$test_tmp/previous.json" "$theme"
echo "Invalid Noctalia colors leave the previous T3 theme intact"

rg -q 'monarch-theme-set-t3-code.*"\$scheme_json".*"\$variant"' \
  "$ROOT/bin/monarch-theme-apply" || {
  echo "Theme application does not synchronize T3 Code" >&2
  exit 1
}
echo "Theme application synchronizes T3 Code"
