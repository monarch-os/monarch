#!/bin/bash

# The naive check this replaces matched on the package name and found nothing
# on a CachyOS kernel, so every DKMS path asked for "-headers".

set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CMD="$ROOT/bin/monarch-hw-kernel-headers"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

failures=0

assert_equals() {
  local description="$1" actual="$2" expected="$3"

  if [[ $actual == "$expected" ]]; then
    printf 'ok - %s\n' "$description"
  else
    printf 'not ok - %s\n  Expected: %s\n  Actual:   %s\n' "$description" "$expected" "$actual" >&2
    ((failures++))
  fi
}

modules() {
  rm -rf "$TMP/modules"
  for spec in "$@"; do
    mkdir -p "$TMP/modules/${spec%%=*}"
    printf '%s\n' "${spec#*=}" >"$TMP/modules/${spec%%=*}/pkgbase"
  done
  MONARCH_MODULES_PATH="$TMP/modules" "$CMD"
}

assert_equals "names the kernel by its pkgbase, not by the directory" \
  "$(modules 7.1.8-1-cachyos=linux-cachyos)" "linux-cachyos-headers"

# Every kernel update leaves its own module directory behind, so the same
# pkgbase turns up several times and would be asked for several times.
assert_equals "asks for one kernel once" \
  "$(modules 7.1.7-1-cachyos=linux-cachyos 7.1.8-1-cachyos=linux-cachyos)" "linux-cachyos-headers"

assert_equals "asks for every kernel installed" \
  "$(modules 7.1.8-1-cachyos=linux-cachyos 6.18.42-1-lts=linux-cachyos-lts | sort | tr '\n' ' ')" \
  "linux-cachyos-headers linux-cachyos-lts-headers "

# A chroot early in the install can have no module directory at all.
rm -rf "$TMP/empty" && mkdir -p "$TMP/empty"
assert_equals "falls back to the stock kernel when nothing is installed" \
  "$(MONARCH_MODULES_PATH="$TMP/empty" "$CMD")" "linux-headers"

assert_equals "falls back when the directory does not exist" \
  "$(MONARCH_MODULES_PATH="$TMP/absent" "$CMD")" "linux-headers"

if ((failures)); then
  printf '\n%s kernel headers test(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll kernel headers tests passed.\n'
