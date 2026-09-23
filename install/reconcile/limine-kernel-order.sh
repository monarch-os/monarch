set -euo pipefail

limine_conf=${MONARCH_LIMINE_CONF:-/etc/default/limine}
expected_order='BOOT_ORDER="linux-cachyos, linux-cachyos-*, *, *fallback, Snapshots"'

[[ -f $limine_conf ]] || {
  echo "Missing Limine configuration: $limine_conf" >&2
  exit 1
}

candidate=$(mktemp "${limine_conf}.monarch.XXXXXX")
backup=$(mktemp "${limine_conf}.monarch-backup.XXXXXX")
restore=false

cleanup() {
  status=$?
  trap - EXIT
  if ((status != 0)) && $restore; then
    cp --preserve=all -- "$backup" "$limine_conf"
  fi
  rm -f -- "$candidate" "$backup"
  exit "$status"
}
trap cleanup EXIT

awk -v expected="$expected_order" '
  /^[[:space:]]*BOOT_ORDER[[:space:]]*=/ {
    if (!written) print expected
    written = 1
    next
  }
  { print }
  END { if (!written) print expected }
' "$limine_conf" >"$candidate"

if cmp -s "$limine_conf" "$candidate"; then
  exit 0
fi

cp --preserve=all -- "$limine_conf" "$backup"
cp --attributes-only --preserve=all -- "$limine_conf" "$candidate"
mv -- "$candidate" "$limine_conf"
restore=true

echo "Prefer the CachyOS kernel in Limine"
limine-mkinitcpio
limine-entry-tool --tree |
  grep -Eq '(^|[^[:alnum:]_-])linux-cachyos([^[:alnum:]_-]|$)'

restore=false
