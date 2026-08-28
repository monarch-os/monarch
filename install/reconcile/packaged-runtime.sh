#!/bin/bash

runtime=${MONARCH_RUNTIME_ROOT:-/usr/share/monarch}
legacy="$HOME/.local/share/monarch"
backup="$HOME/.local/share/monarch-v4"

[[ -x $runtime/bin/monarch ]] || exit 0

if [[ -d $legacy && ! -L $legacy ]]; then
  if [[ -e $backup ]]; then
    echo "Cannot archive $legacy: $backup already exists" >&2
    exit 1
  fi
  mv "$legacy" "$backup"
  ln -s "$runtime" "$legacy"
fi

rm -rf "$HOME/.local/state/monarch/migrations"
rm -f "$0"
"${MONARCH_RECONCILE_BIN:-/usr/bin/monarch-reconcile}" --complete
