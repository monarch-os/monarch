#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home with spaces"
export MONARCH_PATH="$ROOT"
export MONARCH_LANGUAGE=en
export TEST_LOG="$TMP/calls"
export TEST_PACKAGES="$TMP/packages"
export PATH="$TMP/bin:$HOME/.local/bin:$ROOT/bin:/usr/bin:/bin"
system="$TMP/system"
mkdir -p "$TMP/bin" "$HOME/.local/bin" "$HOME/.config/monarch/defaults" \
  "$system/usr/bin"
touch "$TEST_PACKAGES"
sed "s|/usr/bin/hermes|$system/usr/bin/hermes|g" \
  "$ROOT/bin/monarch-agent" >"$TMP/bin/monarch-agent"

cat >"$TMP/bin/monarch-pkg-present" <<'EOF'
#!/bin/bash
grep -qxF -- "$1" "$TEST_PACKAGES"
EOF
cat >"$TMP/bin/monarch-pkg-add" <<'EOF'
#!/bin/bash
printf 'pkg-add %s\n' "$*" >>"$TEST_LOG"
[[ ${INSTALL_STATUS:-0} == 0 ]] || exit "$INSTALL_STATUS"
printf '%s\n' "$@" >>"$TEST_PACKAGES"
EOF
cat >"$TMP/bin/monarch-pkg-drop" <<'EOF'
#!/bin/bash
printf 'pkg-drop %s\n' "$*" >>"$TEST_LOG"
[[ ${REMOVE_STATUS:-0} == 0 ]] || exit "$REMOVE_STATUS"
[[ ${1:-} == "--keep-dependencies" ]] && shift
sed -i "/^$1\$/d" "$TEST_PACKAGES"
EOF
cat >"$TMP/bin/monarch-launch-floating-terminal-with-presentation" <<'EOF'
#!/bin/bash
printf 'launch %s\n' "$*" >>"$TEST_LOG"
EOF
cat >"$TMP/bin/setsid" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$TMP/bin/notify-send" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$TMP/bin/monarch-cmd-present" <<'EOF'
#!/bin/bash
command -v "$1" >/dev/null
EOF
cat >"$TMP/bin/monarch-launch-tui" <<'EOF'
#!/bin/bash
printf 'tui %s\n' "$*" >>"$TEST_LOG"
EOF
cat >"$TMP/bin/monarch-refresh-config" <<'EOF'
#!/bin/bash
mkdir -p "$HOME/.config/$(dirname "$1")"
cp "$MONARCH_PATH/config/$1" "$HOME/.config/$1"
EOF
cat >"$system/usr/bin/hermes" <<'EOF'
#!/bin/bash
printf 'hermes %s\n' "$*" >>"$TEST_LOG"
EOF
cat >"$HOME/.local/bin/hermes" <<'EOF'
#!/bin/bash
echo 'foreign-cli' >>"$TEST_LOG"
exit 99
EOF
chmod +x "$TMP/bin/"* "$system/usr/bin/hermes" "$HOME/.local/bin/hermes"
mkdir -p "$HOME/.hermes/hermes-agent"
touch "$HOME/.hermes/config.yaml" "$HOME/.hermes/sessions.db" "$HOME/.hermes/hermes-agent/keep"
foreign_hash=$(sha256sum "$HOME/.local/bin/hermes")

if monarch-install-hermes-cli --check; then exit 1; fi
[[ ! -e $TEST_LOG ]]
printf '%s\n' codex >"$HOME/.config/monarch/defaults/agent"
"$ROOT/bin/monarch-default-agent" hermes
grep -qx 'launch monarch-default-agent --install hermes' "$TEST_LOG"
[[ $(<"$HOME/.config/monarch/defaults/agent") == codex ]]
if INSTALL_STATUS=23 "$ROOT/bin/monarch-default-agent" --install hermes; then exit 1; fi
[[ $(<"$HOME/.config/monarch/defaults/agent") == codex ]]
monarch-install-hermes-cli --now
grep -qx 'pkg-add hermes-agent-bin' "$TEST_LOG"
if grep -q 'hermes-agent-desktop' "$TEST_PACKAGES"; then exit 1; fi
[[ ! -e $HOME/.config/hermes-desktop-flags.conf ]]
monarch-install-hermes-cli --check
[[ $(sha256sum "$HOME/.local/bin/hermes") == "$foreign_hash" ]]
[[ -f $HOME/.hermes/hermes-agent/keep ]]

: >"$TEST_LOG"
"$ROOT/bin/monarch-default-agent" --install hermes
grep -qx 'hermes chat --tui' "$TEST_LOG"
[[ $(<"$HOME/.config/monarch/defaults/agent") == hermes ]]
monarch-agent --inline --prompt 'spaces; $(never execute)'
grep -qxF 'hermes chat --tui --query spaces; $(never execute)' "$TEST_LOG"
monarch-agent
grep -qxF "tui --app-id=org.monarch.agent $system/usr/bin/hermes chat --tui" "$TEST_LOG"
if grep -qE 'yolo|mise|foreign-cli|pkg-add' "$TEST_LOG"; then exit 1; fi

: >"$TEST_LOG"
if INSTALL_STATUS=23 "$ROOT/bin/monarch-install-ai-hermes"; then exit 1; fi
"$ROOT/bin/monarch-install-ai-hermes"
grep -qx 'pkg-add hermes-agent-desktop-bin' "$TEST_LOG"
grep -qx -- '--ozone-platform=wayland' "$HOME/.config/hermes-desktop-flags.conf"
printf '%s\n' '--ozone-platform=x11' >"$HOME/.config/hermes-desktop-flags.conf"
"$ROOT/bin/monarch-install-ai-hermes"
grep -qx -- '--ozone-platform=x11' "$HOME/.config/hermes-desktop-flags.conf"
[[ $(<"$HOME/.config/monarch/defaults/agent") == hermes ]]
[[ ! -d $HOME/.config/noctalia && ! -d $HOME/.hermes/skins ]]

if REMOVE_STATUS=23 "$ROOT/bin/monarch-remove-ai-hermes"; then exit 1; fi
[[ $(<"$HOME/.config/monarch/defaults/agent") == hermes ]]
"$ROOT/bin/monarch-remove-ai-hermes"
grep -qx 'pkg-drop --keep-dependencies hermes-agent-desktop-bin' "$TEST_LOG"
[[ ! -e $HOME/.config/monarch/defaults/agent ]]
grep -qx hermes-agent-bin "$TEST_PACKAGES"
[[ -f $HOME/.hermes/config.yaml && -f $HOME/.hermes/sessions.db && -f $HOME/.hermes/hermes-agent/keep ]]
[[ $(sha256sum "$HOME/.local/bin/hermes") == "$foreign_hash" ]]

printf '%s\n' hermes-agent hermes-agent-desktop >"$TEST_PACKAGES"
printf '%s\n' codex >"$HOME/.config/monarch/defaults/agent"
: >"$TEST_LOG"
monarch-install-hermes-cli --now
monarch-install-hermes-cli --check
"$ROOT/bin/monarch-install-ai-hermes"
if grep -q 'pkg-add' "$TEST_LOG"; then exit 1; fi
"$ROOT/bin/monarch-remove-ai-hermes"
grep -qx 'pkg-drop --keep-dependencies hermes-agent-desktop' "$TEST_LOG"
[[ $(<"$HOME/.config/monarch/defaults/agent") == codex ]]
grep -qx hermes-agent "$TEST_PACKAGES"
echo 'All Hermes integration tests passed.'
