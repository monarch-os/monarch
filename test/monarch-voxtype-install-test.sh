#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"
export HOME="$TMP/home" MONARCH_PATH="$ROOT" LOG="$TMP/log"
export PATH="$TMP/bin:/usr/bin:/bin"

cat >"$TMP/bin/gum" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$TMP/bin/monarch-pkg-add" <<'EOF'
#!/bin/bash
echo package >>"$LOG"
EOF
cat >"$TMP/bin/sudo" <<'EOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$LOG"
exit "${SUDO_STATUS:-0}"
EOF
cat >"$TMP/bin/voxtype" <<'EOF'
#!/bin/bash
printf 'voxtype %s\n' "$*" >>"$LOG"
if [[ $* == *--download* ]]; then
  mkdir -p "$XDG_CONFIG_HOME/voxtype"
  echo generated >"$XDG_CONFIG_HOME/voxtype/config.toml"
  exit "${DOWNLOAD_STATUS:-0}"
fi
EOF
cat >"$TMP/bin/notify-send" <<'EOF'
#!/bin/bash
echo notify >>"$LOG"
EOF
cat >"$TMP/bin/grep" <<'EOF'
#!/bin/bash
if [[ ${NO_AVX2:-0} == 1 && ${*: -1} == /proc/cpuinfo ]]; then
  exit 1
fi
exec /usr/bin/grep "$@"
EOF
chmod +x "$TMP/bin/"*

if ! grep -qw avx2 /proc/cpuinfo; then
  echo 'Skipping Voxtype installer test: host CPU does not support AVX2'
  exit 0
fi

mkdir -p "$TMP/fallback-home"
HOME="$TMP/fallback-home" NO_AVX2=1 bash "$ROOT/bin/monarch-voxtype-install"
python3 - "$TMP/fallback-home/.config/voxtype/config.toml" <<'PY'
import sys, tomllib
with open(sys.argv[1], 'rb') as f:
    config = tomllib.load(f)
assert config['engine'] == 'whisper'
assert config['whisper']['model'] == 'small'
assert config['whisper']['language'] == 'auto'
PY
grep -q 'voxtype setup --download --model small' "$LOG"
grep -q 'voxtype setup systemd' "$LOG"
! grep -q '^sudo ' "$LOG"
: >"$LOG"

SUDO_STATUS=1 bash "$ROOT/bin/monarch-voxtype-install" && exit 1
[[ ! -e "$HOME/.config/voxtype/config.toml" ]]
! grep -q '^voxtype\|^notify' "$LOG"

: >"$LOG"
DOWNLOAD_STATUS=1 bash "$ROOT/bin/monarch-voxtype-install" && exit 1
[[ ! -e "$HOME/.config/voxtype/config.toml" ]]
! grep -q 'voxtype setup systemd\|^notify' "$LOG"

: >"$LOG"
bash "$ROOT/bin/monarch-voxtype-install"
python3 - "$HOME/.config/voxtype/config.toml" <<'PY'
import sys, tomllib
with open(sys.argv[1], 'rb') as f:
    config = tomllib.load(f)
assert config['engine'] == 'parakeet'
assert config['parakeet']['model'] == 'parakeet-tdt-0.6b-v3-int8'
PY
grep -q 'voxtype setup systemd' "$LOG"
grep -q '^notify$' "$LOG"

: >"$LOG"
bash "$ROOT/bin/monarch-voxtype-install" && exit 1
[[ ! -s "$LOG" ]]
echo 'Voxtype installer tests passed'
