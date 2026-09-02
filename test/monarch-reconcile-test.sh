#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

bootstrap="$TEST_ROOT/bootstrap"
bootstrap_source="$bootstrap/home/.local/share/monarch"
mkdir -p "$bootstrap/bin" "$bootstrap_source/install/reconcile" \
  "$bootstrap/home/.local/state/monarch/migrations" "$bootstrap/system"
touch "$bootstrap/home/.local/state/monarch/migrations/1787067946.sh"
cp "$ROOT/install/reconcile/packaged-runtime-bootstrap.sh" \
  "$bootstrap_source/install/reconcile/packaged-runtime-bootstrap.sh"
export MONARCH_LEGACY_SYSTEM_ROOT="$bootstrap/system"
cat >"$bootstrap/bin/monarch-pkg-missing" <<'EOF'
#!/bin/bash
[[ ! -f $BOOTSTRAP_ROOT/installed ]]
EOF
cat >"$bootstrap/bin/monarch-pkg-add" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$BOOTSTRAP_ROOT/pkg-add-calls"
if [[ $1 == "monarch" ]]; then
  touch "$BOOTSTRAP_ROOT/installed"
fi
mkdir -p "$BOOTSTRAP_ROOT/runtime/bin" "$BOOTSTRAP_ROOT/runtime/install/reconcile/schema/1-to-2"
touch "$BOOTSTRAP_ROOT/runtime/bin/monarch"
chmod +x "$BOOTSTRAP_ROOT/runtime/bin/monarch"
printf '%s\n' 'printf "required-packages\\n" >>"$BOOTSTRAP_ROOT/steps"' >"$BOOTSTRAP_ROOT/runtime/install/reconcile/required-packages.sh"
printf '%s\n' 'printf "system\\n" >>"$BOOTSTRAP_ROOT/steps"' >"$BOOTSTRAP_ROOT/runtime/install/reconcile/system.sh"
printf '%s\n' 'printf "user\\n" >>"$BOOTSTRAP_ROOT/steps"' >"$BOOTSTRAP_ROOT/runtime/install/reconcile/user.sh"
printf '%s\n' 'printf "transition-system\\n" >>"$BOOTSTRAP_ROOT/steps"' >"$BOOTSTRAP_ROOT/runtime/install/reconcile/schema/1-to-2/system.sh"
printf '%s\n' 'printf "transition-user\\n" >>"$BOOTSTRAP_ROOT/steps"' >"$BOOTSTRAP_ROOT/runtime/install/reconcile/schema/1-to-2/user.sh"
EOF
cat >"$bootstrap/bin/pacman" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$BOOTSTRAP_ROOT/pacman-calls"
exit 1
EOF
cat >"$bootstrap/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
cat >"$bootstrap/bin/monarch-pkg-present" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$bootstrap/bin/"*

BOOTSTRAP_ROOT="$bootstrap" HOME="$bootstrap/home" MONARCH_PATH="$bootstrap_source" \
  MONARCH_RUNTIME_ROOT="$bootstrap/runtime" PATH="$bootstrap/bin:/usr/bin" \
  bash "$ROOT/bin/monarch-reconcile" >/dev/null
[[ $(<"$bootstrap/steps") == $'required-packages\nsystem\ntransition-system\ntransition-user\nuser' ]]
[[ $(<"$bootstrap/home/.local/state/monarch/schema") == 2 ]]

: >"$bootstrap/steps"
BOOTSTRAP_ROOT="$bootstrap" HOME="$bootstrap/home" MONARCH_PATH="$bootstrap_source" \
  MONARCH_RUNTIME_ROOT="$bootstrap/runtime" PATH="$bootstrap/bin:/usr/bin" \
  bash "$ROOT/bin/monarch-reconcile" >/dev/null
[[ $(<"$bootstrap/steps") == $'required-packages\nsystem\nuser' ]]

printf '%s\n' 0 >"$bootstrap/home/.local/state/monarch/schema"
if BOOTSTRAP_ROOT="$bootstrap" HOME="$bootstrap/home" MONARCH_PATH="$bootstrap_source" \
  MONARCH_RUNTIME_ROOT="$bootstrap/runtime" PATH="$bootstrap/bin:/usr/bin" \
  bash "$ROOT/bin/monarch-reconcile" >/dev/null 2>&1; then
  echo "unsupported old schema was accepted" >&2
  exit 1
fi

printf '%s\n' 3 >"$bootstrap/home/.local/state/monarch/schema"
if BOOTSTRAP_ROOT="$bootstrap" HOME="$bootstrap/home" MONARCH_PATH="$bootstrap_source" \
  MONARCH_RUNTIME_ROOT="$bootstrap/runtime" PATH="$bootstrap/bin:/usr/bin" \
  bash "$ROOT/bin/monarch-reconcile" >/dev/null 2>&1; then
  echo "newer schema was downgraded" >&2
  exit 1
fi

rm "$bootstrap/home/.local/state/monarch/schema" \
  "$bootstrap/home/.local/state/monarch/migrations/1787067946.sh"
rm -f "$bootstrap/installed"
rm -rf "$bootstrap/runtime"
mkdir -p "$bootstrap/system/usr/share/sddm/themes/monarch"
touch "$bootstrap/system/usr/share/sddm/themes/monarch/theme.conf"
: >"$bootstrap/pkg-add-calls"
: >"$bootstrap/pacman-calls"
if BOOTSTRAP_ROOT="$bootstrap" HOME="$bootstrap/home" MONARCH_PATH="$bootstrap_source" \
  MONARCH_RUNTIME_ROOT="$bootstrap/runtime" PATH="$bootstrap/bin:/usr/bin" \
  bash "$ROOT/bin/monarch-reconcile" >/dev/null 2>&1; then
  echo "legacy installation below the support floor was accepted" >&2
  exit 1
fi
[[ $(<"$bootstrap/pkg-add-calls") == "monarch" ]]
[[ ! -s $bootstrap/pacman-calls ]]

export HOME="$TEST_ROOT/home"
export MONARCH_PATH="$ROOT"
export MONARCH_SOURCE_ROOT="$HOME/.local/share/monarch"
export MONARCH_RUNTIME_ROOT="$TEST_ROOT/runtime"
export MONARCH_RECONCILE_BIN="$ROOT/bin/monarch-reconcile"
export TEST_LOG="$TEST_ROOT/calls"
export TEST_NOCTALIA=unavailable
export PATH="$TEST_ROOT/bin:/usr/bin"

source "$ROOT/install/reconcile/config-files.sh"
ownership="$TEST_ROOT/ownership"
mkdir -p "$ownership/source-tree" "$ownership/managed-tree" "$ownership/shared"
printf '%s\n' current >"$ownership/source"
printf '%s\n' stale >"$ownership/managed"
printf '%s\n' current >"$ownership/source-tree/current"
printf '%s\n' stale >"$ownership/managed-tree/stale"
printf '%s\n' third-party >"$ownership/shared/plugin"

monarch_reconcile_managed_file "$ownership/source" "$ownership/managed"
[[ $(<"$ownership/managed") == "current" ]]
monarch_reconcile_seeded_file "$ownership/source" "$ownership/seeded"
printf '%s\n' customized >"$ownership/seeded"
monarch_reconcile_seeded_file "$ownership/source" "$ownership/seeded"
[[ $(<"$ownership/seeded") == "customized" ]]
monarch_reconcile_managed_tree "$ownership/source-tree" "$ownership/managed-tree"
[[ -f $ownership/managed-tree/current && ! -e $ownership/managed-tree/stale ]]
[[ $(<"$ownership/shared/plugin") == "third-party" ]]

mkdir -p "$TEST_ROOT/bin" "$HOME/.config/noctalia" "$HOME/.config/uwsm" \
  "$HOME/.local/share/monarch/.git" "$MONARCH_RUNTIME_ROOT/bin" \
  "$HOME/.local/share/noctalia/plugins/third-party" \
  "$HOME/.local/share/noctalia/plugins/monarch-theme"
touch "$MONARCH_RUNTIME_ROOT/bin/monarch"
chmod +x "$MONARCH_RUNTIME_ROOT/bin/monarch"
printf '%s\n' keep >"$HOME/.local/share/noctalia/plugins/third-party/plugin.toml"
printf '%s\n' stale >"$HOME/.local/share/noctalia/plugins/monarch-theme/removed.luau"

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

cat >"$TEST_ROOT/bin/monarch-refresh-noctalia" <<'EOF'
#!/bin/bash
printf '%s\n' monarch-refresh-noctalia >>"$TEST_LOG"
touch "$(dirname "$TEST_LOG")/noctalia-ready"
EOF

cat >"$TEST_ROOT/bin/monarch-provision-first-run" <<'EOF'
#!/bin/bash
printf '%s\n' monarch-provision-first-run >>"$TEST_LOG"
EOF

cat >"$TEST_ROOT/bin/noctalia" <<'EOF'
#!/bin/bash
if [[ $1 == "msg" && $2 == "status" ]]; then
  [[ $TEST_NOCTALIA == "ready" || -f $(dirname "$TEST_LOG")/noctalia-ready ]]
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

bash "$ROOT/install/reconcile/schema/1-to-2/user.sh"
bash "$ROOT/install/reconcile/user.sh"

grep -qx 'monarch-pkg-drop noctalia-shell polkit-gnome monarch-welcome' "$TEST_LOG"
grep -qx 'monarch-refresh-config fastfetch/config.jsonc' "$TEST_LOG"
grep -qx 'monarch-provision-first-run' "$TEST_LOG"
[[ ! -e $HOME/.config/noctalia/settings.json ]]
[[ ! -e $HOME/.config/noctalia/plugins.json ]]
[[ -f $HOME/.local/share/noctalia/plugins/monarch-theme/plugin.toml ]]
[[ ! -e $HOME/.local/share/noctalia/plugins/monarch-theme/removed.luau ]]
[[ -f $HOME/.local/share/noctalia/plugins/third-party/plugin.toml ]]
[[ -f $HOME/.config/noctalia/palettes/Monarch.json ]]
grep -qF '/usr/share/monarch}/default/zsh/rc' "$HOME/.zshrc"
grep -qF '/usr/share/monarch}/default/bash/rc' "$HOME/.bashrc"
grep -qx 'export MONARCH_PATH=${MONARCH_PATH:-/usr/share/monarch}' "$HOME/.config/uwsm/env"

plugin_hook="$HOME/.config/monarch/hooks/post-boot.d/noctalia-v5-plugins"
runtime_hook="$HOME/.config/monarch/hooks/post-boot.d/packaged-runtime"
[[ ! -e $plugin_hook && -x $runtime_hook ]]
[[ ! -e $HOME/.local/state/monarch/schema ]]
grep -qx 'monarch-refresh-noctalia' "$TEST_LOG"
grep -qx 'msg plugins enable monarch/theme' "$TEST_LOG"

export TEST_NOCTALIA=ready
bash "$ROOT/install/reconcile/schema/1-to-2/user.sh"
bash "$ROOT/install/reconcile/user.sh"
[[ ! -e $plugin_hook ]]

bash "$runtime_hook"
[[ -L $HOME/.local/share/monarch ]]
[[ $(readlink "$HOME/.local/share/monarch") == "$MONARCH_RUNTIME_ROOT" ]]
[[ -d $HOME/.local/share/monarch-v4/.git ]]
[[ ! -e $runtime_hook ]]
[[ $(<"$HOME/.local/state/monarch/schema") == 2 ]]

if find "$ROOT/migrations" -type f -name '*.sh' -print -quit 2>/dev/null | grep -q .; then
  echo "historical migrations remain" >&2
  exit 1
fi

grep -q '^  monarch-reconcile$' "$ROOT/bin/monarch-update"
grep -qF 'install/config/enable-services.sh' "$ROOT/install/reconcile/system.sh"

echo "All reconciliation tests passed."
