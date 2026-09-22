#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

runner="$ROOT/test/acceptance"
acceptance_dir="$ROOT/test/acceptance.d"

bash -n "$runner" "$acceptance_dir"/*.sh
grep -qF 'MONARCH_PATH="${MONARCH_PATH:-/usr/share/monarch}"' "$runner" ||
  fail "acceptance defaults to the installed runtime"
grep -qF '[[ $runtime != "$ROOT" ]]' "$acceptance_dir/02-system.sh" ||
  fail "acceptance rejects its synchronized test checkout as runtime"
if grep -R -F '$ROOT/bin' "$acceptance_dir" >/dev/null; then
  fail "acceptance reaches commands through its test checkout"
fi
pass "acceptance is pinned to the installed runtime"

grep -qF '/usr/lib/modules/$release/pkgbase' "$acceptance_dir/02-system.sh" ||
  fail "acceptance does not identify the running kernel package"
grep -qF 'monarch-pkg-present "${kernel}-headers"' "$acceptance_dir/02-system.sh" ||
  fail "acceptance does not require matching kernel headers"
grep -qF 'build/include/config/kernel.release' "$acceptance_dir/02-system.sh" ||
  fail "acceptance does not compare the headers with the running release"
grep -qF 'BOOT_ORDER="linux-cachyos, linux-cachyos-*, *, *fallback, Snapshots"' \
  "$acceptance_dir/02-system.sh" || fail "acceptance does not verify the Limine kernel order"
pass "acceptance enforces the running kernel, headers and boot order"

for boundary in \
  '/etc/sudoers.d/$retired' \
  '/usr/share/plymouth/themes/monarch/monarch.script' \
  '/usr/share/sddm/themes/monarch/theme.conf' \
  'passwordauthentication no' \
  'kbdinteractiveauthentication no' \
  '22/tcp'; do
  grep -R -F "$boundary" "$acceptance_dir" >/dev/null ||
    fail "installed acceptance covers $boundary"
done
pass "acceptance covers installed privileged boundaries"

grep -qF 'MONARCH_ACCEPTANCE_SUDO_PASSWORD' "$acceptance_dir/03-security.sh" ||
  fail "mutating SSH acceptance requires explicit credentials"
pass "SSH acceptance requires explicit credentials"
