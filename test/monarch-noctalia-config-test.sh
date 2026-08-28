#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

grep -Fqx 'clipboard_history_max_entries = 500' "$ROOT/config/noctalia/config.toml"
echo "Noctalia keeps the extended clipboard history"

grep -q 'monarch/theme' "$ROOT/install/user/first-run/enable-noctalia-plugins.sh"
echo "Fresh installs enable the Monarch theme plugin"
