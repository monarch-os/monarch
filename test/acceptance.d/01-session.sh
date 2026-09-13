#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base.sh"

outputs=$(niri msg --json outputs) || fail "Niri reports its outputs"
(( $(jq 'length' <<<"$outputs") > 0 )) || fail "Niri reports at least one output"
pass "Niri reports at least one output"

wait_until "Noctalia responds" 60 noctalia msg status
noctalia config validate >/dev/null || fail "Noctalia configuration validates"
pass "Noctalia configuration validates"

monarch-menu --check >/dev/null || fail "installed Monarch menu validates"
monarch commands --check >/dev/null || fail "installed Monarch commands validate"
pass "installed Monarch menu and command routes validate"

wait_until "PipeWire responds" 30 wpctl status
[[ $(findmnt -no FSTYPE /) == "btrfs" ]] || fail "root filesystem is Btrfs"
pass "root filesystem is Btrfs"

monarch-version >/dev/null || fail "installed Monarch version is readable"
pass "installed Monarch version is readable"

failed_units() {
  systemctl "$@" --failed --no-legend --plain | awk '{print $1}' |
    grep -Ev "${MONARCH_ACCEPTANCE_IGNORE_UNITS:-^$}" || true
}

failed_system=$(failed_units --system)
[[ -z $failed_system ]] || fail "no system units failed" "$failed_system"
pass "no system units failed"

failed_user=$(failed_units --user)
[[ -z $failed_user ]] || fail "no user units failed" "$failed_user"
pass "no user units failed"

screenshot success-desktop
