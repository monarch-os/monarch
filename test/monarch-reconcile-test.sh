#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

bootstrap="$TEST_ROOT/bootstrap"
mkdir -p "$bootstrap/bin"
cat >"$bootstrap/bin/monarch-pkg-missing" <<'EOF'
#!/bin/bash
[[ ! -f $BOOTSTRAP_ROOT/installed ]]
EOF
cat >"$bootstrap/bin/monarch-pkg-add" <<'EOF'
#!/bin/bash
[[ $1 == "monarch" ]]
touch "$BOOTSTRAP_ROOT/installed"
mkdir -p "$BOOTSTRAP_ROOT/runtime/bin" "$BOOTSTRAP_ROOT/runtime/install/reconcile"
touch "$BOOTSTRAP_ROOT/runtime/bin/monarch"
chmod +x "$BOOTSTRAP_ROOT/runtime/bin/monarch"
printf '%s\n' 'printf "system\\n" >>"$BOOTSTRAP_ROOT/steps"' >"$BOOTSTRAP_ROOT/runtime/install/reconcile/system.sh"
printf '%s\n' 'printf "user\\n" >>"$BOOTSTRAP_ROOT/steps"' >"$BOOTSTRAP_ROOT/runtime/install/reconcile/user.sh"
EOF
chmod +x "$bootstrap/bin/"*

BOOTSTRAP_ROOT="$bootstrap" HOME="$bootstrap/home" MONARCH_PATH="$bootstrap/source" \
  MONARCH_RUNTIME_ROOT="$bootstrap/runtime" PATH="$bootstrap/bin:/usr/bin" \
  bash "$ROOT/bin/monarch-reconcile" >/dev/null
[[ $(<"$bootstrap/steps") == $'system\nuser' ]]

export HOME="$TEST_ROOT/home"
export MONARCH_PATH="$ROOT"
export MONARCH_SOURCE_ROOT="$HOME/.local/share/monarch"
export MONARCH_RUNTIME_ROOT="$TEST_ROOT/runtime"
export TEST_LOG="$TEST_ROOT/calls"
export TEST_NOCTALIA=unavailable
export PATH="$TEST_ROOT/bin:/usr/bin"

mkdir -p "$TEST_ROOT/bin" "$HOME/.config/noctalia" "$HOME/.config/uwsm" \
  "$HOME/.local/share/monarch/.git" "$MONARCH_RUNTIME_ROOT/bin"
touch "$MONARCH_RUNTIME_ROOT/bin/monarch"
chmod +x "$MONARCH_RUNTIME_ROOT/bin/monarch"

cat >"$TEST_ROOT/bin/monarch-pkg-present" <<'EOF'
#!/bin/bash
[[ $1 == "noctalia-shell" ]]
EOF

for command in monarch-pkg-add monarch-pkg-drop monarch-refresh-config monarch-refresh-niri monarch-theme-apply; do
  cat >"$TEST_ROOT/bin/$command" <<'EOF'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$TEST_LOG"
EOF
done

cat >"$TEST_ROOT/bin/noctalia" <<'EOF'
#!/bin/bash
if [[ $1 == "msg" && $2 == "status" ]]; then
  [[ $TEST_NOCTALIA == "ready" ]]
  exit
fi
printf '%s\n' "$*" >>"$TEST_LOG"
EOF

cat >"$TEST_ROOT/bin/pkill" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "$TEST_ROOT/bin/"*

touch "$HOME/.config/noctalia/settings.json" "$HOME/.config/noctalia/plugins.json"
printf '%s\n' 'source ~/.local/share/monarch/default/zsh/rc' >"$HOME/.zshrc"
printf '%s\n' 'source ~/.local/share/monarch/default/bash/rc' >"$HOME/.bashrc"
printf '%s\n' 'export MONARCH_PATH=$HOME/.local/share/monarch' >"$HOME/.config/uwsm/env"

bash "$ROOT/install/reconcile/user.sh"

grep -qx 'monarch-pkg-add noctalia qrencode' "$TEST_LOG"
grep -qx 'monarch-pkg-drop noctalia-shell polkit-gnome' "$TEST_LOG"
[[ ! -e $HOME/.config/noctalia/settings.json ]]
[[ ! -e $HOME/.config/noctalia/plugins.json ]]
[[ -f $HOME/.local/share/noctalia/plugins/monarch-theme/plugin.toml ]]
[[ -f $HOME/.config/noctalia/palettes/Monarch.json ]]
grep -qF '/usr/share/monarch}/default/zsh/rc' "$HOME/.zshrc"
grep -qF '/usr/share/monarch}/default/bash/rc' "$HOME/.bashrc"
grep -qx 'export MONARCH_PATH=${MONARCH_PATH:-/usr/share/monarch}' "$HOME/.config/uwsm/env"

plugin_hook="$HOME/.config/monarch/hooks/post-boot.d/noctalia-v5-plugins"
runtime_hook="$HOME/.config/monarch/hooks/post-boot.d/packaged-runtime"
[[ -x $plugin_hook && -x $runtime_hook ]]

export TEST_NOCTALIA=ready
bash "$ROOT/install/reconcile/user.sh"
[[ ! -e $plugin_hook ]]
grep -qx 'msg plugins enable monarch/theme' "$TEST_LOG"

bash "$runtime_hook"
[[ -L $HOME/.local/share/monarch ]]
[[ $(readlink "$HOME/.local/share/monarch") == "$MONARCH_RUNTIME_ROOT" ]]
[[ -d $HOME/.local/share/monarch-v4/.git ]]
[[ ! -e $runtime_hook ]]

if find "$ROOT/migrations" -type f -name '*.sh' -print -quit 2>/dev/null | grep -q .; then
  echo "historical migrations remain" >&2
  exit 1
fi

grep -q '^  monarch-reconcile$' "$ROOT/bin/monarch-update"

echo "All reconciliation tests passed."
