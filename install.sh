#!/bin/bash

set -euo pipefail

script_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export MONARCH_PATH="${MONARCH_PATH:-$script_root}"
export MONARCH_INSTALL="$MONARCH_PATH/install"
export PATH="$MONARCH_PATH/bin:$PATH"

case "${1:-}" in
  --install-user|--defer-provisioning)
    exec monarch-apply-system "$@"
    ;;
  provision-user)
    shift
    exec monarch-provision-user "$@"
    ;;
  provision-owner)
    shift
    exec monarch-provision-owner "$@"
    ;;
  factory-reset)
    shift
    exec monarch-system-factory-reset "$@"
    ;;
  factory-reset-finish)
    shift
    exec monarch-system-factory-reset-finish "$@"
    ;;
  *)
    echo "Usage:" >&2
    echo "  install.sh --install-user USER --first-install" >&2
    echo "  install.sh --defer-provisioning --first-install" >&2
    echo "  install.sh provision-user [--force] [--first-install]" >&2
    echo "  install.sh provision-owner" >&2
    echo "  install.sh factory-reset" >&2
    echo "  install.sh factory-reset-finish" >&2
    exit 2
    ;;
esac
