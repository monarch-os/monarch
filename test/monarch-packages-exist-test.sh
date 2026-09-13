#!/bin/bash

# Nothing else connects the package lists to the repositories that must serve
# them, so a stale name surfaces minutes into an ISO build, or in a fresh install.
#
# Run: bash test/monarch-packages-exist-test.sh

set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

failures=0

pass() { printf 'ok - %s\n' "$1"; }

fail() {
  printf 'not ok - %s\n' "$1" >&2
  shift
  (($# == 0)) || printf '  %s\n' "$@" >&2
  ((failures++))
}

fetch() {
  curl -fsS --retry 3 --retry-delay 2 --max-time 120 -o "$2" "$1"
}

# What monarch-iso/configs/pacman-online.conf resolves against, with the Arch
# three taken from upstream's geo mirror: same packages, one less host to need.
repos=(
  "core|https://geo.mirror.pkgbuild.com/core/os/x86_64/core.db"
  "extra|https://geo.mirror.pkgbuild.com/extra/os/x86_64/extra.db"
  "multilib|https://geo.mirror.pkgbuild.com/multilib/os/x86_64/multilib.db"
  "cachyos|https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos.db"
)
MONARCH_DB="https://pkgs.monarchlinux.com/x86_64/monarch.db"

# %PROVIDES% counts — pacman resolves a name a package provides, so must this.
names_from_db() {
  tar -xOf "$1" --wildcards '*/desc' 2>/dev/null | awk '
    /^%NAME%$/     { getline n; print n; next }
    /^%PROVIDES%$/ { while ((getline p) > 0 && p != "") { sub(/[<>=].*/, "", p); print p } }
  '
}

: >"$TMP/available"

# Ours, and the one that broke twice: an outage here is itself worth a red build.
if fetch "$MONARCH_DB" "$TMP/monarch.db" 2>"$TMP/err"; then
  names_from_db "$TMP/monarch.db" >>"$TMP/available"
  pass "the Monarch repository answers"
else
  fail "the Monarch repository answers" "$MONARCH_DB" "$(cat "$TMP/err")"
fi

unreachable=()
for entry in "${repos[@]}"; do
  repo=${entry%%|*}
  url=${entry#*|}
  if fetch "$url" "$TMP/$repo.db" 2>/dev/null; then
    names_from_db "$TMP/$repo.db" >>"$TMP/available"
  else
    unreachable+=("$repo")
  fi
done

sort -u "$TMP/available" -o "$TMP/available"

list_names() {
  grep -v '^#' "$1" | grep -v '^[[:space:]]*$'
}

# No names means no missing names means a pass: the silent success to prevent.
list_is_readable() {
  if [[ -s $1 ]] && [[ -n $(list_names "$1") ]]; then
    return 0
  fi
  fail "$(basename "$1") exists and lists something" "$1"
  return 1
}

if ((${#unreachable[@]})); then
  # Never silently: with a repository missing, everything it serves reads absent.
  printf 'SKIP - pacman lists not checked, unreachable: %s\n' "${unreachable[*]}" >&2
else
  for list in monarch-base.packages monarch-other.packages; do
    list_is_readable "$ROOT/install/$list" || continue

    missing=()
    while read -r pkg; do
      grep -qxF "$pkg" "$TMP/available" || missing+=("$pkg")
    done < <(list_names "$ROOT/install/$list")

    if ((${#missing[@]})); then
      fail "every package in $list is served by a repository" \
        "no repository provides: ${missing[*]}"
    else
      pass "every package in $list is served by a repository ($(list_names "$ROOT/install/$list" | wc -l) names)"
    fi
  done
fi

# pip, not pacman — a different registry with the same failure.
if list_is_readable "$ROOT/install/python.packages"; then
  missing=()
  while read -r pkg; do
    curl -fsS --retry 2 --max-time 30 -o /dev/null "https://pypi.org/pypi/${pkg}/json" ||
      missing+=("$pkg")
  done < <(list_names "$ROOT/install/python.packages")

  if ((${#missing[@]})); then
    fail "every package in python.packages is on PyPI" "PyPI does not know: ${missing[*]}"
  else
    pass "every package in python.packages is on PyPI"
  fi
fi

if ((failures)); then
  printf '\n%s package list check(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll package list checks passed.\n'
