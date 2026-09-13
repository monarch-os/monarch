#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

dns="$ROOT/bin/monarch-dns"
trusted_path=/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

grep -Fq "export PATH=$trusted_path" "$dns" || fail "root DNS helper pins a trusted PATH"
gated=$(grep -A1 -E '^if \(\(EUID == 0\)\); then$' "$dns" || true)
[[ $gated == *"export PATH=$trusted_path"* ]] || fail "DNS PATH pin is gated on root"
pass "root monarch-dns pins system helper resolution to trusted directories"

grep -Fq 'PACKAGED_PATH=/usr/bin/monarch-dns' "$dns" || fail "DNS elevation uses its packaged path"
grep -Fq 'sudo -n -l -l' "$dns" || fail "DNS helper detects the passwordless grant precisely"
pass "unprivileged DNS elevation keeps sudo and pkexec discovery before re-exec"
