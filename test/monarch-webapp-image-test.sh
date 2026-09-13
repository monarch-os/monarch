#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
IMAGE_TEST_TMP=$(mktemp -d)
trap 'rm -rf -- "$IMAGE_TEST_TMP"' EXIT
export PATH="$ROOT/bin:/usr/bin:/bin"
IMAGE_TEST_FILE_LOG="$IMAGE_TEST_TMP/file-log"
source "$ROOT/install/helpers/webapps.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
reject() {
  if "$@" > "$IMAGE_TEST_TMP/rejected-output" 2> "$IMAGE_TEST_TMP/rejected-error"; then
    fail "accepted: $*"
  fi
  [[ ! -s $IMAGE_TEST_TMP/rejected-output ]] || fail 'rejected image returned a decoder'
}

file() {
  printf '%s\0' "${!#}" >> "$IMAGE_TEST_FILE_LOG"
  [[ ${!#} != "${IMAGE_TEST_FILE_ERROR:-}" ]] || return 2
  if [[ -n ${IMAGE_TEST_MIME:-} ]]; then
    printf '%s\n' "$IMAGE_TEST_MIME"
    return 0
  fi
  command file "$@"
}

base64 -d > "$IMAGE_TEST_TMP/source.png" <<'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=
EOF

webapp_convert_icon "$IMAGE_TEST_TMP/source.png" "$IMAGE_TEST_TMP/result.png"
mapfile -d '' -t detected < "$IMAGE_TEST_FILE_LOG"
[[ ${#detected[@]} == 2 && ${detected[0]} == "$IMAGE_TEST_TMP/source.png" &&
  ${detected[1]} == "$IMAGE_TEST_TMP/result.png" ]] ||
  fail "conversion should detect each distinct file once; detected ${#detected[@]} files"
[[ $(identify -format '%m %wx%h' "$IMAGE_TEST_TMP/result.png") == "PNG 256x256" ]] ||
  fail 'conversion did not produce a 256x256 PNG'
printf 'PASS: conversion detects its source and result once each\n'

IMAGE_TEST_TOOL=magick
monarch-cmd-present magick || IMAGE_TEST_TOOL=convert
for format in PNG JPEG GIF WEBP BMP ICO; do
  "$IMAGE_TEST_TOOL" "$IMAGE_TEST_TMP/source.png" "$format:$IMAGE_TEST_TMP/format-image"
  [[ $(webapp_image_coder "$IMAGE_TEST_TMP/format-image") == "$format" ]] ||
    fail "wrong decoder for $format"
done
for mime in image/x-icon image/vnd.microsoft.icon; do
  [[ $(IMAGE_TEST_MIME=$mime webapp_image_coder "$IMAGE_TEST_TMP/source.png") == "ICO" ]] ||
    fail "wrong decoder for $mime"
done
printf 'PASS: supported raster formats and both ICO MIME aliases select their decoder\n'

mkdir "$IMAGE_TEST_TMP/directory"
ln -s "$IMAGE_TEST_TMP/source.png" "$IMAGE_TEST_TMP/link.png"
ln -s "$IMAGE_TEST_TMP/missing.png" "$IMAGE_TEST_TMP/dangling.png"
mkfifo "$IMAGE_TEST_TMP/pipe.png"
touch "$IMAGE_TEST_TMP/empty.png"
truncate -s 5242881 "$IMAGE_TEST_TMP/oversized.png"
for path in missing.png directory link.png dangling.png pipe.png empty.png oversized.png; do
  : > "$IMAGE_TEST_FILE_LOG"
  reject webapp_image_coder "$IMAGE_TEST_TMP/$path"
  [[ ! -s $IMAGE_TEST_FILE_LOG ]] || fail "MIME detection ran before rejecting $path"
done
cp "$IMAGE_TEST_TMP/source.png" "$IMAGE_TEST_TMP/bounded.png"
truncate -s 5242880 "$IMAGE_TEST_TMP/bounded.png"
[[ $(webapp_image_coder "$IMAGE_TEST_TMP/bounded.png") == "PNG" ]] ||
  fail 'rejected a valid image at the 5 MiB boundary'
printf 'PASS: rejects unsafe file types and sizes before MIME detection, retaining the 5 MiB boundary\n'

for mime in image/svg+xml image/x-xpixmap text/html application/octet-stream; do
  IMAGE_TEST_MIME=$mime reject webapp_image_coder "$IMAGE_TEST_TMP/source.png"
done
IMAGE_TEST_FILE_ERROR="$IMAGE_TEST_TMP/source.png" reject webapp_image_coder "$IMAGE_TEST_TMP/source.png"
IMAGE_TEST_FILE_ERROR="$IMAGE_TEST_TMP/rejected-result.png" \
  reject webapp_convert_icon "$IMAGE_TEST_TMP/source.png" "$IMAGE_TEST_TMP/rejected-result.png"
[[ -f $IMAGE_TEST_TMP/rejected-result.png ]] || fail 'conversion did not reach result validation'
printf 'PASS: rejects unsupported MIME types and propagates detection failures for source and result\n'

WEBAPP_ICON_DIR="$IMAGE_TEST_TMP/legacy-icons"
mkdir "$WEBAPP_ICON_DIR"
: > "$IMAGE_TEST_FILE_LOG"
webapp_icon_reference "$IMAGE_TEST_TMP/source.png"
cp "$IMAGE_TEST_TMP/source.png" "$IMAGE_TEST_TMP/copied source.png"
webapp_convert_icon "$IMAGE_TEST_TMP/copied source.png" "$IMAGE_TEST_TMP/staged-result.png"
mapfile -d '' -t detected < "$IMAGE_TEST_FILE_LOG"
[[ ${#detected[@]} == 3 && ${detected[0]} == "$IMAGE_TEST_TMP/source.png" &&
  ${detected[1]} == "$IMAGE_TEST_TMP/copied source.png" && ${detected[2]} == "$IMAGE_TEST_TMP/staged-result.png" ]] ||
  fail 'import skipped validation of the original, copied source, or converted result'
truncate -s 0 "$IMAGE_TEST_TMP/copied source.png"
reject webapp_convert_icon "$IMAGE_TEST_TMP/copied source.png" "$IMAGE_TEST_TMP/invalid-stage.png"
[[ ! -e $IMAGE_TEST_TMP/invalid-stage.png ]] || fail 'conversion accepted a damaged staged copy'
printf 'PASS: import validates the original file, its staged copy, and the result separately\n'
