#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home with spaces"
export MONARCH_PATH="$ROOT"
export MONARCH_LANGUAGE=en
export TEST_LOG="$TMP/calls"
export PATH="$TMP/bin:$HOME/.local/bin:$ROOT/bin:/usr/bin:/bin"
mkdir -p "$TMP/bin" "$HOME/.local/bin" "$HOME/.config/monarch/defaults"

cat >"$TMP/bin/monarch-pkg-present" <<'EOF'
#!/bin/bash
[[ ${PACKAGE_PRESENT:-true} == true ]]
EOF
cat >"$TMP/bin/monarch-pkg-add" <<'EOF'
#!/bin/bash
printf 'pkg-add %s\n' "$*" >>"$TEST_LOG"
exit "${INSTALL_STATUS:-0}"
EOF
cat >"$TMP/bin/monarch-pkg-drop" <<'EOF'
#!/bin/bash
printf 'pkg-drop %s\n' "$*" >>"$TEST_LOG"
exit "${REMOVE_STATUS:-0}"
EOF
cat >"$TMP/bin/monarch-theme-hermes" <<'EOF'
#!/bin/bash
printf 'theme %s\n' "$*" >>"$TEST_LOG"
exit "${THEME_STATUS:-0}"
EOF
cat >"$TMP/bin/monarch-launch-floating-terminal-with-presentation" <<'EOF'
#!/bin/bash
printf 'launch %s\n' "$*" >>"$TEST_LOG"
EOF
cat >"$TMP/bin/noctalia" <<'EOF'
#!/bin/bash
printf 'noctalia %s\n' "$*" >>"$TEST_LOG"
if [[ $* == 'msg templates-apply' ]]; then
  grep -qx 'output_path = "~/.hermes/skins/monarch.yaml"' "$HOME/.config/noctalia/monarch-hermes.toml"
  mkdir -p "$HOME/.hermes/skins"
  printf '%s\n' 'name: monarch' >"$HOME/.hermes/skins/monarch.yaml"
fi
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
cat >"$HOME/.local/bin/hermes" <<'EOF'
#!/bin/bash
if [[ $* == 'chat --help' ]]; then
  if [[ ${HELP_READY:-true} == true ]]; then
    printf '%s\n' '  --tui  Interactive TUI' '  --query QUERY  Seed prompt'
  else
    printf '%s\n' 'Old release: --tui and --query are not available here'
  fi
elif [[ $* == 'config get display.skin' ]]; then
  printf '%s\n' "${CURRENT_SKIN:-default}"
else
  printf 'hermes %s\n' "$*" >>"$TEST_LOG"
fi
EOF
chmod +x "$TMP/bin/"* "$HOME/.local/bin/hermes"

runtime="$HOME/.hermes/hermes-agent"
native="$runtime/apps/desktop/release/linux-unpacked"
mkdir -p "$native/resources"
touch "$runtime/.hermes-bootstrap-complete" "$native/Hermes" "$native/resources/app.asar" "$native/resources/install-stamp.json"
chmod +x "$native/Hermes"

"$ROOT/bin/monarch-install-hermes-cli" --check
[[ ! -e $TEST_LOG ]]
if PACKAGE_PRESENT=false "$ROOT/bin/monarch-install-hermes-cli" --check; then exit 1; fi
if HELP_READY=false "$ROOT/bin/monarch-install-hermes-cli" --check; then exit 1; fi
mv "$native/resources/app.asar" "$native/resources/kept.asar"
if "$ROOT/bin/monarch-install-hermes-cli" --check; then exit 1; fi
mv "$native/resources/kept.asar" "$native/resources/app.asar"
cp "$HOME/.local/bin/hermes" "$TMP/bin/hermes"
if "$ROOT/bin/monarch-install-hermes-cli" --check; then exit 1; fi
rm "$TMP/bin/hermes"

package="$TMP/package"
mkdir -p "$package/resources"
printf '%s\n' '{"branch":"main","commit":"2237be355906fbe6065ce1815711eee52b2d646e"}' >"$package/resources/install-stamp.json"
touch "$package/Hermes" "$package/chrome-sandbox" "$package/resources/app.asar"
chmod +x "$package/Hermes"
cp "$HOME/.local/bin/hermes" "$TMP/fixture-cli"
export FIXTURE_CLI="$TMP/fixture-cli"
cat >"$TMP/upstream-install.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'upstream %s\n' "$*" >>"$TEST_LOG"
runtime="$HERMES_HOME/hermes-agent"
mkdir -p "$runtime/venv/bin" "$HOME/.local/bin"
touch "$runtime/.hermes-bootstrap-complete"
cp "$FIXTURE_CLI" "$HOME/.local/bin/hermes"
cat >"$runtime/venv/bin/python" <<'PYTHON'
#!/bin/bash
grep -q '_write_desktop_build_stamp' || exit 1
printf 'stamp\n' >>"$TEST_LOG"
PYTHON
chmod +x "$runtime/venv/bin/python"
EOF
sed -e "s|/opt/hermes-desktop|$package|g" \
  -e "s|/usr/share/hermes-desktop/install.sh|$TMP/upstream-install.sh|g" \
  "$ROOT/bin/monarch-install-hermes-cli" >"$TMP/installer"
(
  export HOME="$TMP/fresh home"
  export HERMES_HOME="$HOME/.hermes"
  export PATH="$TMP/bin:$HOME/.local/bin:$ROOT/bin:/usr/bin:/bin"
  THEME_STATUS=1 bash "$TMP/installer" --now
  [[ -f $HOME/.hermes/hermes-agent/apps/desktop/release/linux-unpacked/resources/app.asar ]]
  grep -q 'upstream --skip-setup --branch main --commit .* --force-commit' "$TEST_LOG"
  [[ $(grep -c '^upstream ' "$TEST_LOG") == 1 ]]
  bash "$TMP/installer" --now
  [[ $(grep -c '^upstream ' "$TEST_LOG") == 1 ]]
)
(
  export HOME="$TMP/foreign home"
  export HERMES_HOME="$HOME/.hermes"
  mkdir -p "$HOME/.local/bin"
  printf '%s\n' 'keep this foreign command' >"$HOME/.local/bin/hermes"
  if bash "$TMP/installer" --now; then exit 1; fi
  [[ $(<"$HOME/.local/bin/hermes") == 'keep this foreign command' ]]
  [[ ! -e $HOME/.hermes/hermes-agent ]]
)
(
  export HOME="$TMP/incomplete home"
  export HERMES_HOME="$HOME/.hermes"
  mkdir -p "$HERMES_HOME/hermes-agent"
  touch "$HERMES_HOME/hermes-agent/keep"
  if bash "$TMP/installer" --now; then exit 1; fi
  [[ -f $HERMES_HOME/hermes-agent/keep ]]
  [[ $(grep -c '^upstream ' "$TEST_LOG") == 1 ]]
)

printf '%s\n' codex >"$HOME/.config/monarch/defaults/agent"
HELP_READY=false "$ROOT/bin/monarch-default-agent" hermes
grep -qx 'launch monarch-default-agent --install hermes' "$TEST_LOG"
[[ $(<"$HOME/.config/monarch/defaults/agent") == codex ]]

# Stub only provisioning; exercise default-agent selection and the real launcher.
cat >"$TMP/bin/monarch-install-hermes-cli" <<'EOF'
#!/bin/bash
printf 'install-cli %s\n' "$*" >>"$TEST_LOG"
exit "${INSTALL_STATUS:-0}"
EOF
chmod +x "$TMP/bin/monarch-install-hermes-cli"
if INSTALL_STATUS=23 "$ROOT/bin/monarch-default-agent" --install hermes; then exit 1; fi
[[ $(<"$HOME/.config/monarch/defaults/agent") == codex ]]
"$ROOT/bin/monarch-default-agent" --install hermes
grep -qx 'hermes chat --tui' "$TEST_LOG"
"$ROOT/bin/monarch-agent" --inline --prompt 'spaces; $(never execute)'
grep -qxF 'hermes chat --tui --query spaces; $(never execute)' "$TEST_LOG"
"$ROOT/bin/monarch-agent"
grep -qxF 'tui --app-id=org.monarch.agent hermes chat --tui' "$TEST_LOG"
if grep -qE 'yolo|mise' "$TEST_LOG"; then exit 1; fi

cat >"$TMP/bin/monarch-refresh-config" <<'EOF'
#!/bin/bash
mkdir -p "$HOME/.config/$(dirname "$1")"
cp "$MONARCH_PATH/config/$1" "$HOME/.config/$1"
EOF
chmod +x "$TMP/bin/monarch-refresh-config"
"$ROOT/bin/monarch-theme-hermes" --activate
grep -qx 'noctalia msg config-reload' "$TEST_LOG"
grep -qx 'hermes config set display.skin monarch' "$TEST_LOG"
printf '%s\n' '# User template' >>"$HOME/.config/noctalia/templates/hermes.yaml"
template_hash=$(sha256sum "$HOME/.config/noctalia/templates/hermes.yaml")
: >"$TEST_LOG"
CURRENT_SKIN=custom "$ROOT/bin/monarch-theme-hermes" --activate
[[ $(sha256sum "$HOME/.config/noctalia/templates/hermes.yaml") == "$template_hash" ]]
if grep -q 'config set' "$TEST_LOG"; then exit 1; fi
printf '%s\n' work >"$HOME/.hermes/active_profile"
"$ROOT/bin/monarch-theme-hermes" --activate
if grep -q 'config set' "$TEST_LOG"; then exit 1; fi
rm "$HOME/.hermes/active_profile"

touch "$HOME/.hermes/config.yaml" "$HOME/.hermes/sessions.db"
if REMOVE_STATUS=23 "$ROOT/bin/monarch-remove-ai-hermes"; then exit 1; fi
[[ $(<"$HOME/.config/monarch/defaults/agent") == hermes ]]
"$ROOT/bin/monarch-remove-ai-hermes"
[[ ! -e $HOME/.config/monarch/defaults/agent ]]
[[ -f $HOME/.hermes/config.yaml && -f $HOME/.hermes/sessions.db && -x $HOME/.local/bin/hermes ]]
printf '%s\n' codex >"$HOME/.config/monarch/defaults/agent"
"$ROOT/bin/monarch-remove-ai-hermes"
[[ $(<"$HOME/.config/monarch/defaults/agent") == codex ]]
echo 'All Hermes integration tests passed.'
