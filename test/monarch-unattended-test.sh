#!/bin/bash

# Guards the unattended install against prompts nobody can answer.
#
# The ISO installs itself with no keyboard when it finds a cidata drive, and it
# runs this installer in a chroot with MONARCH_UNATTENDED=1. Every gum prompt
# reads the TTY, so one added without a guard does not fail the install — it
# hangs it, on a screen no one is watching, forever.
#
# Run: bash test/monarch-unattended-test.sh

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# What install.sh sources, which is what runs inside the chroot. first-run/ is
# excluded on purpose: it runs at the first graphical login, where there is a
# user in front of the screen.
SURFACE=(install.sh install/helpers install/preflight install/packaging
  install/config install/login install/post-install)

# gum verbs that block on the TTY. `gum style`, `format`, `log` and `spin` do not.
INTERACTIVE='gum (confirm|choose|input|filter|file|write|table|pager)|read -p'

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

# Every prompt line, with comments stripped so a mention in prose is not a hit.
prompt_sites() {
  local path
  for path in "${SURFACE[@]}"; do
    find "$ROOT/$path" -type f 2>/dev/null | while read -r file; do
      # Most files match nothing, and a bare non-zero grep would kill the scan
      # under set -e — silently, which is how a scan reports "all clear".
      grep -nE "$INTERACTIVE" "$file" 2>/dev/null |
        grep -vE '^[0-9]+:[[:space:]]*#' |
        sed "s|^|${file#$ROOT/}:|" || true
    done
  done
}

# A prompt is covered when the guard is on its line (the `||` form) or anywhere
# above it (the early-exit form). Deliberately coarse: this is a canary for a
# prompt added without any unattended handling at all, not a proof that the
# guard dominates every path to it.
is_guarded() {
  local file="$1" line="$2"
  sed -n "1,${line}p" "$ROOT/$file" | grep -q 'MONARCH_UNATTENDED'
}

unguarded=()
found=0
while IFS= read -r site; do
  [[ -n $site ]] || continue
  found=$((found + 1))
  file=${site%%:*}
  rest=${site#*:}
  line=${rest%%:*}
  is_guarded "$file" "$line" || unguarded+=("$file:$line")
done < <(prompt_sites)

((found > 0)) || fail "found no prompts at all — the scan is broken, not the code"
pass "scanned $found interactive prompt(s) across the chroot install surface"

if ((${#unguarded[@]} > 0)); then
  printf 'unguarded prompt: %s\n' "${unguarded[@]}" >&2
  fail "every prompt reachable during a chroot install must check MONARCH_UNATTENDED"
fi
pass "every prompt is guarded by MONARCH_UNATTENDED"

# The three known sites, named so that removing a guard fails loudly here rather
# than silently hanging an install six months from now.
for expected in \
  install/preflight/guard.sh \
  install/helpers/errors.sh \
  install/post-install/finished.sh; do
  grep -q 'MONARCH_UNATTENDED' "$ROOT/$expected" ||
    fail "$expected lost its MONARCH_UNATTENDED guard"
  pass "$expected still guards its prompt"
done

# The reboot marker is what tells the ISO the install finished. Skipping the
# prompt must not skip the marker with it.
grep -q 'monarch-install-completed' "$ROOT/install/post-install/finished.sh" ||
  fail "finished.sh no longer creates the reboot marker the ISO waits on"
pass "the unattended path still creates the reboot marker"
