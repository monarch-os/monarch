#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
sudoers="$TEST_ROOT/sudoers"
mkdir -p "$sudoers"

run_reconcile() {
  MONARCH_SUDOERS_DIR="$sudoers" bash "$ROOT/install/reconcile/retired-sudoers.sh"
}

cat >"$sudoers/first-run" <<'EOF'
Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run
Cmnd_Alias SYMLINK_RESOLVED = /usr/bin/ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
y0no ALL=(ALL) NOPASSWD: /usr/bin/systemctl
y0no ALL=(ALL) NOPASSWD: /usr/bin/ufw
y0no ALL=(ALL) NOPASSWD: /usr/bin/ufw-docker
y0no ALL=(ALL) NOPASSWD: /usr/bin/gtk-update-icon-cache
y0no ALL=(ALL) NOPASSWD: SYMLINK_RESOLVED
y0no ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP
EOF
printf '%s\n' 'y0no ALL=(ALL) NOPASSWD: /home/y0no/.local/bin/tsui' >"$sudoers/tsui"
run_reconcile
[[ ! -e $sudoers/first-run && ! -e $sudoers/tsui ]]

cat >"$sudoers/first-run" <<'EOF'
Cmnd_Alias FIRST_RUN_CLEANUP = /usr/bin/rm -f /etc/sudoers.d/first-run, /bin/rm -f /etc/sudoers.d/first-run
Cmnd_Alias SYMLINK_RESOLVED = /usr/bin/ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
renamed ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/udev/rules.d/*
renamed ALL=(ALL) NOPASSWD: /usr/bin/udevadm
renamed ALL=(ALL) NOPASSWD: /usr/bin/systemctl
renamed ALL=(ALL) NOPASSWD: /usr/bin/ufw
renamed ALL=(ALL) NOPASSWD: /usr/bin/ufw-docker
renamed ALL=(ALL) NOPASSWD: /usr/bin/gtk-update-icon-cache
renamed ALL=(ALL) NOPASSWD: SYMLINK_RESOLVED
renamed ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP
EOF
run_reconcile
[[ ! -e $sudoers/first-run ]]

cat >"$sudoers/first-run" <<'EOF'
Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run
y0no ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP
y0no ALL=(ALL) NOPASSWD: /usr/bin/vim
EOF
printf '%s\n' 'y0no ALL=(ALL) NOPASSWD: /usr/bin/tsui, /usr/bin/vim' >"$sudoers/tsui"
run_reconcile
[[ -f $sudoers/first-run && -f $sudoers/tsui ]]

printf '%s\n' '%wheel ALL=(ALL) NOPASSWD: /usr/bin/tsui' >"$sudoers/tsui"
cat >"$sudoers/first-run" <<'EOF'
Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run
Cmnd_Alias SYMLINK_RESOLVED = /usr/bin/ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
%wheel ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP
EOF
run_reconcile
[[ -f $sudoers/first-run && -f $sudoers/tsui ]]

cat >"$sudoers/first-run" <<'EOF'
#includedir /etc/sudoers.d/local
Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run
y0no ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP
EOF
run_reconcile
[[ -f $sudoers/first-run ]]

rm "$sudoers/tsui"
ln -s /tmp/admin-sudoers "$sudoers/tsui"
run_reconcile
[[ -L $sudoers/tsui ]]

echo "Retired sudoers reconciliation checks pass"
