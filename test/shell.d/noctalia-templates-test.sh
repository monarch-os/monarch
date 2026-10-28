#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"
python3 "$ROOT/test/noctalia-templates-test.py"
