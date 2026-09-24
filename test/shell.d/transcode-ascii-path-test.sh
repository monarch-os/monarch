#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/bin" "$sandbox/work"
printf 'image' >"$sandbox/work/-logo.png"

cat >"$sandbox/bin/magick" <<'STUB'
#!/bin/bash
printf '<%s>\n' "$@" >>"$MAGICK_ARGS"
case $* in
  *'%[fx:minima]'*) printf '0\n' ;;
  *'%[fx:maxima]'*) printf '1\n' ;;
  *) printf 'P1\n1 2\n1\n0\n' ;;
esac
STUB
chmod +x "$sandbox/bin/magick"

(
  cd "$sandbox/work"
  MAGICK_ARGS="$sandbox/magick-args" PATH="$sandbox/bin:$ROOT/bin:/usr/bin" \
    "$ROOT/bin/monarch-transcode-ascii" --block --width 1 --height 1 -- -logo.png -logo.txt
)

[[ -s $sandbox/work/-logo.txt ]] ||
  fail "transcode ascii does not write an option-like output path"
grep -Fxq "<$sandbox/work/-logo.png>" "$sandbox/magick-args" ||
  fail "transcode ascii does not normalize its option-like input path"
pass "transcode ascii treats option-like paths literally"
