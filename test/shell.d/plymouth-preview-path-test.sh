#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/bin" "$sandbox/work" "$sandbox/runtime/default/plymouth"
printf 'logo' >"$sandbox/work/-logo.png"
for asset in bullet.png entry.png lock.png; do
  printf 'asset' >"$sandbox/runtime/default/plymouth/$asset"
done

cat >"$sandbox/bin/magick" <<'STUB'
#!/bin/bash
if [[ $1 == "identify" ]]; then
  printf '100\n'
elif [[ $1 == "-size" ]]; then
  output=${!#}
  printf 'preview' >"$output"
fi
STUB
chmod +x "$sandbox/bin/magick"

(
  cd "$sandbox/work"
  PATH="$sandbox/bin:/usr/bin" MONARCH_PATH="$sandbox/runtime" MONARCH_PLYMOUTH_PREVIEW_OPEN=0 \
    "$ROOT/bin/monarch-plymouth-preview" '#000000' '#ffffff' -logo.png -preview.png
)

[[ -s $sandbox/work/-preview.png ]] ||
  fail "plymouth preview does not write an option-like output path"
pass "plymouth preview treats option-like paths literally"
