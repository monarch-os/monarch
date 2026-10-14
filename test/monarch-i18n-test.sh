#!/bin/bash

set -euo pipefail
ROOT=$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd)
python3 -B "$ROOT/test/i18n_test.py"
