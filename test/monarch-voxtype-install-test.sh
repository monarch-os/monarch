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
if [[ $1 == choose ]]; then
  echo "${CHOICE:-Keep}"
fi
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
if [[ $1 == config && $2 == get ]]; then
  case $3 in
    engine) jq -n --arg value "${TEST_ENGINE:-whisper}" '{value:$value}' ;;
    whisper.mode) echo '{"value":"local"}' ;;
    whisper.model|parakeet.model) jq -n --arg value "${TEST_MODEL:-small}" '{value:$value}' ;;
  esac
  exit 0
fi
if [[ $1 == info && $2 == models ]]; then
  echo "{\"engines\":{\"whisper\":{\"models\":[{\"name\":\"small\",\"installed\":${MODEL_INSTALLED:-true}}]}}}"
  exit 0
fi
if [[ $1 == info && $2 == engines ]]; then
  echo '[{"name":"whisper","compiled":true},{"name":"parakeet","compiled":true}]'
  exit 0
fi
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
cat >"$TMP/bin/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$LOG"
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
sed -i -e 's/^engine = "parakeet"$/engine = "whisper"/' -e 's/^model = "base.en"$/model = "small"/' "$HOME/.config/voxtype/config.toml"
before=$(sha256sum "$HOME/.config/voxtype/config.toml")
CHOICE=Cancel bash "$ROOT/bin/monarch-voxtype-install"
[[ $(sha256sum "$HOME/.config/voxtype/config.toml") == "$before" ]]
! grep -q 'voxtype setup systemd\|^sudo\|^notify' "$LOG"

: >"$LOG"
CHOICE=Keep MODEL_INSTALLED=false bash "$ROOT/bin/monarch-voxtype-install" && exit 1
[[ $(sha256sum "$HOME/.config/voxtype/config.toml") == "$before" ]]
! grep -q 'voxtype setup systemd\|^notify' "$LOG"

: >"$LOG"
CHOICE=Keep bash "$ROOT/bin/monarch-voxtype-install"
[[ $(sha256sum "$HOME/.config/voxtype/config.toml") == "$before" ]]
grep -q 'voxtype setup systemd' "$LOG"

mkdir -p "$TMP/parakeet-model"
touch "$TMP/whisper-model.bin"
: >"$LOG"
CHOICE=Keep TEST_ENGINE=parakeet TEST_MODEL="$TMP/parakeet-model" bash "$ROOT/bin/monarch-voxtype-install"
grep -q 'voxtype setup systemd' "$LOG"
: >"$LOG"
CHOICE=Keep TEST_ENGINE=parakeet TEST_MODEL="$TMP/whisper-model.bin" bash "$ROOT/bin/monarch-voxtype-install" && exit 1
! grep -q 'voxtype setup systemd\|^notify' "$LOG"
: >"$LOG"
CHOICE=Keep TEST_ENGINE=whisper TEST_MODEL="$TMP/whisper-model.bin" bash "$ROOT/bin/monarch-voxtype-install"
grep -q 'voxtype setup systemd' "$LOG"
: >"$LOG"
CHOICE=Keep TEST_ENGINE=whisper TEST_MODEL="$TMP/parakeet-model" bash "$ROOT/bin/monarch-voxtype-install" && exit 1
! grep -q 'voxtype setup systemd\|^notify' "$LOG"

: >"$LOG"
mkdir -p "$HOME/.config/systemd/user"
printf 'custom service\n' >"$HOME/.config/systemd/user/voxtype.service"
CHOICE=Keep bash "$ROOT/bin/monarch-voxtype-install"
grep -q '^custom service$' "$HOME/.config/systemd/user/voxtype.service"
grep -q 'systemctl --user enable --now voxtype.service' "$LOG"
! grep -q 'voxtype setup systemd' "$LOG"
rm "$HOME/.config/systemd/user/voxtype.service"

: >"$LOG"
CHOICE=Replace DOWNLOAD_STATUS=1 bash "$ROOT/bin/monarch-voxtype-install" && exit 1
[[ $(sha256sum "$HOME/.config/voxtype/config.toml") == "$before" ]]
! grep -q 'voxtype setup systemd\|^notify' "$LOG"

: >"$LOG"
CHOICE=Replace bash "$ROOT/bin/monarch-voxtype-install"
backup=("$HOME"/.config/voxtype/config.toml.backup.*)
[[ ${#backup[@]} == 1 ]]
[[ $(sha256sum "${backup[0]}" | cut -d ' ' -f1) == "${before%% *}" ]]
grep -q 'voxtype setup systemd' "$LOG"
echo 'Voxtype installer tests passed'
