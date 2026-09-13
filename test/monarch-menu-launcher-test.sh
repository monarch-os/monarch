#!/bin/bash

set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

lua "$ROOT/test/fixtures/menu-launcher.lua" "$ROOT/default/noctalia/plugins/monarch-menu/launcher.luau"
