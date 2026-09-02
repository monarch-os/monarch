set -euo pipefail

system_root=${MONARCH_RECONCILE_SYSTEM_ROOT:-/}

# These hashes are the supported V4 defaults; anything else is user-owned.
adopt_legacy_pacnew() {
  local relative_path="$1"
  local legacy_hash="$2"
  local target="$system_root/$relative_path"
  local pacnew="$target.pacnew"

  [[ -f $target && ! -L $target && -f $pacnew && ! -L $pacnew ]] || return 1
  [[ $(sha256sum "$target" | cut -d' ' -f1) == "$legacy_hash" ]] || return 1

  install -m 0644 "$pacnew" "$target"
  rm -f "$pacnew"
}

if adopt_legacy_pacnew etc/mkinitcpio.conf.d/monarch_hooks.conf \
  e05dd59ad52a2edc41076123f53f8784fdcbf90124321b66498f801f27028242; then
  mkinitcpio -P
fi

if adopt_legacy_pacnew etc/systemd/resolved.conf.d/10-disable-multicast.conf \
  9e1d19e154bb15464e64c6e3c8be80f39323cefd60124df033fdc6895537be1b; then
  systemctl try-restart systemd-resolved
fi
