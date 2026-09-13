#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"
LOG="$TMP/calls.log"
export LOG

cat >"$TMP/bin/sudo" <<'EOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$LOG"
exit 0
EOF

cat >"$TMP/bin/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$LOG"
[[ $1 == is-active ]]
EOF

chmod +x "$TMP/bin/"*

PATH="$TMP/bin:/usr/bin" USER=test "$ROOT/bin/monarch-sudo-passwordless" >/dev/null

stop_line=$(grep -nF 'sudo systemctl stop monarch-nopasswd-expire-test.timer' "$LOG" | cut -d: -f1)
remove_line=$(grep -nF 'sudo rm /etc/sudoers.d/99-monarch-nopasswd-test' "$LOG" | cut -d: -f1)

if ((stop_line >= remove_line)); then
  echo "Passwordless sudo is removed before its timer is stopped" >&2
  exit 1
fi

echo "Passwordless sudo stops its timer before revoking access"

rule_file="$ROOT/default/tmpfiles.d/monarch-nopasswd-sudo.conf"
rules=$(grep -vE '^[[:space:]]*(#|$)' "$rule_file")

if (( $(grep -c . <<<"$rules") != 1 )); then
  echo "Passwordless sudo boot cleanup must contain exactly one rule" >&2
  exit 1
fi

read -r rule_type rule_path _ <<<"$rules"
[[ $rule_type == 'r!' ]]

grant_path=$(grep -m1 '^NOPASSWD_FILE=' "$ROOT/bin/monarch-sudo-passwordless" | cut -d'"' -f2)
grant_path=${grant_path/'${USER}'/test}

case $grant_path in
  $rule_path) ;;
  *)
    echo "Passwordless sudo boot cleanup does not match its grant" >&2
    exit 1
    ;;
esac

echo "Passwordless sudo grants are cleared after a reboot"

cat >"$TMP/bin/gum" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$TMP/bin/sudo" <<'EOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$LOG"
case $1 in
  test)
    exit 1
    ;;
  tee)
    cat >"$TEST_GRANT"
    ;;
  chmod)
    chmod "$2" "$TEST_GRANT"
    ;;
  systemd-run)
    exit 1
    ;;
  rm)
    rm -f "$TEST_GRANT"
    ;;
esac
EOF
chmod +x "$TMP/bin/gum" "$TMP/bin/sudo"

TEST_GRANT="$TMP/grant"
export TEST_GRANT
if PATH="$TMP/bin:/usr/bin" USER=test \
  "$ROOT/bin/monarch-sudo-passwordless" >/dev/null 2>&1; then
  echo "Passwordless sudo reports success without an expiry timer" >&2
  exit 1
fi
if [[ -e $TEST_GRANT ]]; then
  echo "Passwordless sudo remains enabled without an expiry timer" >&2
  exit 1
fi

echo "Passwordless sudo fails closed when expiry cannot be scheduled"
