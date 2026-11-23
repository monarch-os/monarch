#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
lua "$ROOT/test/fixtures/network-panel.lua" "$ROOT/default/noctalia/plugins/monarch-network/panel.luau"
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 "$ROOT/test/fixtures/network-wifi.py"
