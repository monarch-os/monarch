#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
owner="$ROOT/bin/monarch-provision-owner"
form="$ROOT/install/provisioning/setup-form.sh"

grep -qF 'tagline="A Modern Cybersecurity Desktop powered by Niri"' "$owner"
! grep -q 'setfont' "$owner"
grep -qF 'Alphanumeric without spaces (like alex)' "$form"

echo "first-boot branding and console font: ok"
