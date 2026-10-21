#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
[[ -x /usr/bin/nvim ]] || exit 0
runtime=${XDG_RUNTIME_DIR:-/run/user/$UID}
shopt -s nullglob
for socket in "$runtime"/nvim.*.0 "$runtime"/nvim.*/0; do
  [[ -S $socket && -O $socket ]] || continue
  timeout 1 /usr/bin/nvim --server "$socket" --remote-expr \
    'execute("lua package.loaded.matugen = nil; require(\"matugen\").setup()")' >/dev/null 2>&1 || true
done
