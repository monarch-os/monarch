#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
lua "$ROOT/test/monarch-agent-plugin-test.lua" "$ROOT/default/noctalia/plugins/monarch-agents"
