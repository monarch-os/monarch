#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
stub_bin="$test_root/bin"
limine_conf="$test_root/limine"
calls="$test_root/calls"
reconciler="$ROOT/install/reconcile/limine-kernel-order.sh"
expected_order='BOOT_ORDER="linux-cachyos, linux-cachyos-*, *, *fallback, Snapshots"'
mkdir -p "$stub_bin"

cat >"$stub_bin/limine-mkinitcpio" <<'EOF'
#!/bin/bash
printf 'limine-mkinitcpio\t%s\n' "$*" >>"$LIMINE_TEST_CALLS"
exit "${LIMINE_TEST_REBUILD_STATUS:-0}"
EOF

cat >"$stub_bin/limine-entry-tool" <<'EOF'
#!/bin/bash
printf 'limine-entry-tool\t%s\n' "$*" >>"$LIMINE_TEST_CALLS"
[[ $* == "--tree" ]] || exit 2
printf '%s\n' "${LIMINE_TEST_TREE:-/Monarch/linux-cachyos}"
EOF

chmod +x "$stub_bin/limine-mkinitcpio" "$stub_bin/limine-entry-tool"

run_reconciler() {
  LIMINE_TEST_CALLS="$calls" \
    MONARCH_LIMINE_CONF="$limine_conf" \
    PATH="$stub_bin:/usr/bin" \
    bash "$reconciler"
}

cat >"$limine_conf" <<'EOF'
TARGET_OS_NAME="Monarch"
BOOT_ORDER="*, *fallback, Snapshots"
KERNEL_CMDLINE[default]+=" root=UUID=example quiet"
BOOT_ORDER="linux, *, *fallback, Snapshots"
EOF
: >"$calls"

run_reconciler
[[ $(grep -cxF "$expected_order" "$limine_conf") == 1 ]] ||
  fail "Limine reconciliation does not leave one canonical boot order"
grep -qxF 'KERNEL_CMDLINE[default]+=" root=UUID=example quiet"' "$limine_conf" ||
  fail "Limine reconciliation changed the kernel command line"
[[ $(<"$calls") == $'limine-mkinitcpio\t\nlimine-entry-tool\t--tree' ]] ||
  fail "Limine reconciliation did not rebuild and verify the boot entries"
pass "legacy Limine order is replaced without changing unrelated settings"

run_reconciler
[[ $(wc -l <"$calls") == 2 ]] || fail "canonical Limine state triggered another rebuild"
pass "canonical Limine state is idempotent"

cat >"$limine_conf" <<'EOF'
TARGET_OS_NAME="Monarch"
KERNEL_CMDLINE[default]+=" root=UUID=example quiet"
EOF
: >"$calls"
run_reconciler
grep -qxF "$expected_order" "$limine_conf" || fail "missing Limine order was not added"
pass "missing Limine order is added"

cat >"$limine_conf" <<'EOF'
TARGET_OS_NAME="Monarch"
BOOT_ORDER="*, *fallback, Snapshots"
KERNEL_CMDLINE[default]+=" root=UUID=retry quiet"
EOF
cp "$limine_conf" "$test_root/original"
: >"$calls"
if LIMINE_TEST_REBUILD_STATUS=42 run_reconciler >/dev/null 2>&1; then
  fail "failed Limine rebuild was ignored"
fi
cmp -s "$limine_conf" "$test_root/original" || fail "failed Limine rebuild did not restore the previous config"
[[ $(<"$calls") == $'limine-mkinitcpio\t' ]] || fail "verification continued after a failed rebuild"
pass "failed Limine rebuild preserves retry state"

: >"$calls"
run_reconciler
grep -qxF "$expected_order" "$limine_conf" || fail "Limine reconciliation could not retry"
pass "Limine reconciliation retries after failure"

cat >"$limine_conf" <<'EOF'
TARGET_OS_NAME="Monarch"
BOOT_ORDER="*, *fallback, Snapshots"
EOF
cp "$limine_conf" "$test_root/original"
: >"$calls"
if LIMINE_TEST_TREE=/Monarch/linux-cachyos-lts run_reconciler >/dev/null 2>&1; then
  fail "missing default CachyOS boot entry was accepted"
fi
cmp -s "$limine_conf" "$test_root/original" ||
  fail "failed Limine verification did not restore the previous config"
[[ $(<"$calls") == $'limine-mkinitcpio\t\nlimine-entry-tool\t--tree' ]] ||
  fail "Limine boot entry was not verified after rebuilding"
pass "Limine reconciliation verifies the default kernel entry"

grep -qF 'sudo bash /usr/share/monarch/install/reconcile/limine-kernel-order.sh' \
  "$ROOT/install/reconcile/system.sh" || fail "system reconciliation does not run the protected Limine repair"
pass "system reconciliation runs the protected Limine repair"
