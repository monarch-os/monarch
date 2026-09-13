#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
ufw="$TEST_ROOT/ufw"
log="$TEST_ROOT/ufw.log"
legacy_state="$TEST_ROOT/legacy-rule"

cat >"$ufw" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$MONARCH_UFW_LOG"
if [[ $1 == "--force" ]]; then
  if [[ -f $MONARCH_UFW_LEGACY_STATE ]]; then
    rm "$MONARCH_UFW_LEGACY_STATE"
  else
    echo "Could not delete non-existent rule"
  fi
fi
if [[ ${MONARCH_UFW_FAIL_ADD:-false} == "true" && $1 == "allow" ]]; then
  exit 23
fi
EOF
chmod +x "$ufw"

run_reconcile() {
  MONARCH_UFW_COMMAND="$ufw" MONARCH_UFW_LOG="$log" \
    MONARCH_UFW_LEGACY_STATE="$legacy_state" \
    MONARCH_UFW_FAIL_ADD="${MONARCH_UFW_FAIL_ADD:-false}" \
    bash "$ROOT/install/reconcile/schema/1-to-2/legacy-docker-firewall.sh"
}

touch "$legacy_state"
run_reconcile
expected=$'--force delete allow in proto udp from 10.66.0.0/12 to 10.66.0.1 port 53\nallow in proto udp from 10.66.0.0/15 to 10.66.0.1 port 53 comment allow-docker-dns'
[[ $(<"$log") == $expected && ! -e $legacy_state ]]

: >"$log"
run_reconcile >/dev/null
[[ $(<"$log") == $expected ]]

: >"$log"
if MONARCH_UFW_FAIL_ADD=true run_reconcile; then
  echo "Legacy Docker firewall reconciliation hid an add failure" >&2
  exit 1
fi
[[ $(<"$log") == $expected ]]

grep -qF 'schema/1-to-2/legacy-docker-firewall.sh' \
  "$ROOT/install/reconcile/schema/1-to-2/system.sh"
if grep -qF 'legacy-docker-firewall.sh' "$ROOT/install/reconcile/system.sh"; then
  echo "Legacy Docker firewall cleanup escaped its schema transition" >&2
  exit 1
fi

echo "Legacy Docker firewall reconciliation checks pass"
