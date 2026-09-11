#!/bin/bash

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "Source test/acceptance.d/base.sh from an acceptance test" >&2
  exit 1
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
ARTIFACTS="${MONARCH_ACCEPTANCE_DIR:-/tmp/monarch-acceptance}"
mkdir -p "$ARTIFACTS"

pass() {
  printf 'ok - %s\n' "$1"
}

screenshot() {
  timeout 10 grim "$ARTIFACTS/$1.png" 2>/dev/null || true
}

fail() {
  local description=$1 detail=${2:-} artifact=${1,,}

  artifact=${artifact// /-}
  artifact=${artifact//[^a-z0-9-]/}
  [[ -z $detail ]] || printf '%s\n' "$detail" >&2
  screenshot "failure-$artifact"
  printf 'not ok - %s\n' "$description" >&2
  exit 1
}

wait_until() {
  local description=$1 seconds=$2 deadline
  shift 2
  deadline=$((SECONDS + seconds))

  until "$@" >/dev/null 2>&1; do
    ((SECONDS < deadline)) || fail "$description" "timed out after ${seconds}s: $*"
    sleep 1
  done
  pass "$description"
}

assert_root_file() {
  local file=$1 expected_mode=$2 metadata

  [[ -f $file && ! -L $file ]] || fail "$file is a regular file"
  metadata=$(stat -Lc '%U:%G %a' "$file") || fail "$file metadata can be read"
  [[ $metadata == "root:root $expected_mode" ]] ||
    fail "$file has protected metadata" "found: $metadata"
}
