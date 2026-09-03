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
printf '%s\n' 'printf "transition-system-after-user\\n" >>"$BOOTSTRAP_ROOT/steps"' >"$BOOTSTRAP_ROOT/runtime/install/reconcile/schema/1-to-2/system-after-user.sh"
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
[[ $(<"$bootstrap/steps") == $'required-packages\nsystem\ntransition-system\ntransition-user\ntransition-system-after-user\nuser' ]]
[[ $(<"$bootstrap/home/.local/state/monarch/schema") == "2" ]]

: >"$bootstrap/steps"
BOOTSTRAP_ROOT="$bootstrap" HOME="$bootstrap/home" MONARCH_PATH="$bootstrap_source" \
  MONARCH_RUNTIME_ROOT="$bootstrap/runtime" PATH="$bootstrap/bin:/usr/bin" \
  bash "$ROOT/bin/monarch-reconcile" >/dev/null
[[ $(<"$bootstrap/steps") == $'required-packages\nsystem\nuser' ]]

rm "$bootstrap/home/.local/state/monarch/schema"
: >"$bootstrap/steps"
BOOTSTRAP_ROOT="$bootstrap" HOME="$bootstrap/home" MONARCH_PATH="$bootstrap/runtime" \
  MONARCH_RUNTIME_ROOT="$bootstrap/runtime" PATH="$bootstrap/bin:/usr/bin" \
  bash "$ROOT/bin/monarch-reconcile" >/dev/null
[[ $(<"$bootstrap/steps") == $'required-packages\nsystem\ntransition-system\ntransition-user\ntransition-system-after-user\nuser' ]]

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
export MONARCH_RUNTIME_ROOT="$TEST_ROOT/runtime"
export MONARCH_RECONCILE_BIN="$ROOT/bin/monarch-reconcile"
export MONARCH_NVIM_CONFIG_DIR="$TEST_ROOT/monarch-nvim/config"
export TEST_LOG="$TEST_ROOT/calls"
export TEST_NOCTALIA=unavailable
export PATH="$TEST_ROOT/bin:$ROOT/bin:/usr/bin"

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

mkdir -p "$TEST_ROOT/bin" "$HOME/.config/noctalia/templates" "$HOME/.config/uwsm" \
  "$HOME/.config/noctalia/colorschemes/User" "$HOME/.config/noctalia/plugins/user" \
  "$HOME/.local/share/monarch/.git" "$MONARCH_RUNTIME_ROOT/bin" \
  "$HOME/.local/bin" "$HOME/.config/monarch/defaults" \
  "$HOME/.config/nvim/lua/config" "$HOME/.config/nvim/lua/plugins" \
  "$MONARCH_NVIM_CONFIG_DIR/lua/config" \
  "$HOME/.local/share/noctalia/plugins/third-party" \
  "$HOME/.local/share/noctalia/plugins/monarch-theme" "$HOME/dotfiles"
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

cat >"$TEST_ROOT/bin/monarch-notification-wait" <<'EOF'
#!/bin/bash
[[ ${TEST_NOTIFICATION_READY:-false} == "true" ]]
EOF

cat >"$TEST_ROOT/bin/monarch-notification-send" <<'EOF'
#!/bin/bash
printf 'notification %s\n' "$*" >>"$TEST_LOG"
EOF

cat >"$TEST_ROOT/bin/monarch-refresh-noctalia" <<'EOF'
#!/bin/bash
printf '%s\n' monarch-refresh-noctalia >>"$TEST_LOG"
printf '%s\n' v5-default >"$HOME/.config/noctalia/config.toml"
EOF

cat >"$TEST_ROOT/bin/sha256sum" <<'EOF'
#!/bin/bash
if [[ $(<"$1") == "legacy-default" ]]; then
  case "${1##*/}" in
    fuzzel.ini) checksum=12df7f9bd7310c133ce96caaf51dd2f81fe4ac2894cdbd8ab5421012152d3733 ;;
    herdr.toml) checksum=3959426bdc72aab761291e1c6e8d571fb11af7f3e41c2b294769cf6ae0069075 ;;
    nvim-base16.lua) checksum=4970133a9d79f3f9c24c1fd4c5071b7c11ef14da89be2ba4412591ccfc5f3365 ;;
    obsidian.css) checksum=36dfd6e3b1dc4c98f9a5234815ea09a204fab4ef9d297a3ac6cb6013240548be ;;
    sddm.conf) checksum=41255868a7fdc8a634e0b9e8315afd9647518637c9014f50e725b8b46c5e3e79 ;;
    zed.json) checksum=fe03f8557debc88434732e786b5c5c149c992be7982a159f12a7b532aefaf015 ;;
  esac
fi

if [[ -n ${checksum:-} ]]; then
  printf '%s  %s\n' "$checksum" "$1"
else
  exec /usr/bin/sha256sum "$@"
fi
EOF

cat >"$TEST_ROOT/bin/monarch-provision-first-run" <<'EOF'
#!/bin/bash
printf '%s\n' monarch-provision-first-run >>"$TEST_LOG"
EOF

cat >"$TEST_ROOT/bin/noctalia" <<'EOF'
#!/bin/bash
if [[ $1 == "msg" && $2 == "status" ]]; then
  if [[ -n ${TEST_NOCTALIA_READY_AFTER:-} ]]; then
    count_file=$(dirname "$TEST_LOG")/noctalia-status-count
    count=0
    [[ ! -f $count_file ]] || count=$(<"$count_file")
    ((++count))
    printf '%s\n' "$count" >"$count_file"
    ((count >= TEST_NOCTALIA_READY_AFTER))
    exit
  fi
  [[ $TEST_NOCTALIA == "ready" || -f $(dirname "$TEST_LOG")/noctalia-ready ]]
  exit
fi
printf '%s\n' "$*" >>"$TEST_LOG"
EOF

cat >"$TEST_ROOT/bin/pkill" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$TEST_ROOT/bin/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$TEST_ROOT/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF

chmod +x "$TEST_ROOT/bin/"*

system_transition="$TEST_ROOT/system-transition"
mkdir -p "$system_transition/install/reconcile/schema/1-to-2"
printf '%s\n' true >"$system_transition/install/reconcile/retired-sudoers.sh"
printf '%s\n' true >"$system_transition/install/reconcile/schema/1-to-2/legacy-docker-firewall.sh"
printf '%s\n' true >"$system_transition/install/reconcile/schema/1-to-2/legacy-udev-rules.sh"
printf '%s\n' true >"$system_transition/install/reconcile/schema/1-to-2/legacy-settings-pacnew.sh"
MONARCH_PATH="$system_transition" bash "$ROOT/install/reconcile/schema/1-to-2/system.sh"

printf '%s\n' legacy-settings >"$HOME/.config/noctalia/settings.json"
printf '%s\n' legacy-settings-backup >"$HOME/.config/noctalia/settings.json.bak.1"
printf '%s\n' legacy-plugins >"$HOME/.config/noctalia/plugins.json"
printf '%s\n' user-palette >"$HOME/.config/noctalia/colorschemes/User/palette.json"
printf '%s\n' user-plugin >"$HOME/.config/noctalia/plugins/user/plugin.qml"
for template_file in fuzzel.ini nvim-base16.lua obsidian.css sddm.conf zed.json; do
  printf '%s\n' legacy-default >"$HOME/.config/noctalia/templates/$template_file"
done
printf '%s\n' user-herdr >"$HOME/.config/noctalia/templates/herdr.toml"
printf '%s\n' custom >"$HOME/.config/noctalia/templates/custom.tpl"
printf '%s\n' legacy >"$HOME/.config/noctalia/user-templates.toml"
ln -s "$HOME/.config/monarch/current/theme/neovim.lua" \
  "$HOME/.config/nvim/lua/plugins/theme.lua"
touch "$HOME/.config/nvim/lua/plugins/omarchy-theme-hotreload.lua"
printf '%s\n' 'vim.opt.relativenumber = false' >"$HOME/dotfiles/nvim-options.lua"
ln -s "$HOME/dotfiles/nvim-options.lua" "$HOME/.config/nvim/lua/config/options.lua"
printf '%s\n' 'return {}' >"$MONARCH_NVIM_CONFIG_DIR/lua/config/remote_clipboard.lua"
printf '%s\n' 'source ~/.local/share/monarch/default/zsh/rc' >"$HOME/dotfiles/zshrc"
ln -s "$HOME/dotfiles/zshrc" "$HOME/.zshrc"
printf '%s\n' 'source ~/.local/share/monarch/default/bash/rc' >"$HOME/.bashrc"
printf '%s\n' 'export MONARCH_PATH=$HOME/.local/share/monarch' >"$HOME/dotfiles/uwsm-env"
ln -s "$HOME/dotfiles/uwsm-env" "$HOME/.config/uwsm/env"
cat >"$HOME/.local/bin/gemini" <<'EOF'
#!/bin/bash
package="@google/gemini-cli"
command="gemini"
EOF
printf '%s\n' gemini >"$HOME/.config/monarch/defaults/agent"

bash "$ROOT/install/reconcile/schema/1-to-2/user.sh"

runtime_hook="$HOME/.config/monarch/hooks/post-boot.d/packaged-runtime"
[[ -x $runtime_hook ]]
bash "$runtime_hook"
[[ -d $HOME/.local/share/monarch && -x $runtime_hook ]]

bash "$ROOT/install/reconcile/schema/1-to-2/system-after-user.sh"
bash "$ROOT/install/reconcile/user.sh"

grep -qx 'monarch-pkg-drop noctalia-shell polkit-gnome monarch-welcome' "$TEST_LOG"
grep -qx 'monarch-pkg-drop claude-code openai-codex opencode' "$TEST_LOG"
grep -qx 'monarch-refresh-config fastfetch/config.jsonc' "$TEST_LOG"
if grep -qx 'monarch-provision-first-run' "$TEST_LOG"; then
  echo "First-run provisioning ran before Noctalia became ready" >&2
  exit 1
fi
[[ ! -e $HOME/.config/noctalia/settings.json ]]
[[ ! -e $HOME/.config/noctalia/settings.json.bak.1 ]]
[[ ! -e $HOME/.config/noctalia/plugins.json ]]
[[ ! -e $HOME/.config/noctalia/user-templates.toml ]]
[[ ! -e $HOME/.config/noctalia/colorschemes ]]
[[ ! -e $HOME/.config/noctalia/plugins ]]
legacy_noctalia_archive="$HOME/.local/state/monarch/reconcile/1-to-2/legacy-noctalia-config"
[[ $(<"$legacy_noctalia_archive/settings.json") == "legacy-settings" ]]
[[ $(<"$legacy_noctalia_archive/settings.json.bak.1") == "legacy-settings-backup" ]]
[[ $(<"$legacy_noctalia_archive/user-templates.toml") == "legacy" ]]
[[ $(<"$legacy_noctalia_archive/colorschemes/User/palette.json") == "user-palette" ]]
[[ $(<"$legacy_noctalia_archive/plugins/user/plugin.qml") == "user-plugin" ]]
for template_file in fuzzel.ini nvim-base16.lua obsidian.css sddm.conf zed.json; do
  [[ ! -e $HOME/.config/noctalia/templates/$template_file ]]
done
[[ $(<"$HOME/.config/noctalia/templates/herdr.toml") == "user-herdr" ]]
[[ $(<"$HOME/.config/noctalia/templates/custom.tpl") == "custom" ]]
[[ -f $HOME/.local/state/monarch/reconcile/1-to-2/legacy-noctalia ]]
[[ ! -e $HOME/.config/nvim/lua/plugins/theme.lua ]]
[[ ! -e $HOME/.config/nvim/lua/plugins/omarchy-theme-hotreload.lua ]]
cmp "$MONARCH_NVIM_CONFIG_DIR/lua/config/remote_clipboard.lua" \
  "$HOME/.config/nvim/lua/config/remote_clipboard.lua"
[[ $(head -1 "$HOME/.config/nvim/lua/config/options.lua") == 'require("config.remote_clipboard").setup()' ]]
[[ -L $HOME/.config/nvim/lua/config/options.lua ]]
[[ -f $HOME/.local/share/noctalia/plugins/monarch-theme/plugin.toml ]]
[[ ! -e $HOME/.local/share/noctalia/plugins/monarch-theme/removed.luau ]]
[[ -f $HOME/.local/share/noctalia/plugins/third-party/plugin.toml ]]
[[ -f $HOME/.config/noctalia/palettes/Monarch.json ]]
grep -qF '/usr/share/monarch}/default/zsh/rc' "$HOME/.zshrc"
grep -qF '/usr/share/monarch}/default/bash/rc' "$HOME/.bashrc"
grep -qx 'export MONARCH_PATH=${MONARCH_PATH:-/usr/share/monarch}' "$HOME/.config/uwsm/env"
[[ -L $HOME/.zshrc && -L $HOME/.config/uwsm/env ]]
grep -qx 'command="gemini"' "$HOME/.local/bin/gemini"
[[ $(<"$HOME/.config/monarch/defaults/agent") == "agy" ]]
[[ -x $HOME/.local/bin/codex && -x $HOME/.local/bin/agy ]]

plugin_hook="$HOME/.config/monarch/hooks/post-boot.d/noctalia-v5-plugins"
[[ -x $plugin_hook && -x $runtime_hook ]]
[[ ! -e $HOME/.local/state/monarch/schema ]]
grep -qx 'monarch-refresh-noctalia' "$TEST_LOG"

rm "$runtime_hook"
bash "$ROOT/install/reconcile/schema/1-to-2/runtime-hook.sh"
[[ -x $runtime_hook ]]

export TEST_NOCTALIA=ready
printf '%s\n' '#!/bin/bash' 'echo user-gemini' >"$HOME/.local/bin/gemini"
rm "$HOME/.config/nvim/lua/config/remote_clipboard.lua"
printf '%s\n' 'return { custom = true }' >"$HOME/dotfiles/remote_clipboard.lua"
ln -s "$HOME/dotfiles/remote_clipboard.lua" \
  "$HOME/.config/nvim/lua/config/remote_clipboard.lua"
printf '%s\n' user-config >"$HOME/.config/noctalia/config.toml"
printf '%s\n' current >"$HOME/.config/noctalia/user-templates.toml"
printf '%s\n' newer >"$HOME/.config/noctalia/templates/newer.tpl"
bash "$ROOT/install/reconcile/schema/1-to-2/user.sh"
bash "$ROOT/install/reconcile/schema/1-to-2/system-after-user.sh"
bash "$ROOT/install/reconcile/user.sh"
[[ ! -e $plugin_hook ]]
grep -qx 'monarch-provision-first-run' "$TEST_LOG"
grep -qx 'msg plugins enable monarch/theme' "$TEST_LOG"
grep -qx 'echo user-gemini' "$HOME/.local/bin/gemini"
[[ -L $HOME/.config/nvim/lua/config/remote_clipboard.lua ]]
[[ $(<"$HOME/.config/nvim/lua/config/remote_clipboard.lua") == 'return { custom = true }' ]]
[[ $(<"$HOME/.config/noctalia/config.toml") == "user-config" ]]
[[ $(<"$HOME/.config/noctalia/user-templates.toml") == "current" ]]
[[ $(<"$HOME/.config/noctalia/templates/newer.tpl") == "newer" ]]
(( $(grep -xc monarch-refresh-noctalia "$TEST_LOG") == 1 ))

legacy_backup="$HOME/.local/share/monarch-v4"
ln -s missing "$legacy_backup"
if bash "$runtime_hook" >/dev/null 2>&1; then
  echo "runtime finalization overwrote a broken backup symlink" >&2
  exit 1
fi
[[ -d $HOME/.local/share/monarch && -L $legacy_backup && -x $runtime_hook ]]
rm -f "$legacy_backup"

if bash "$runtime_hook"; then
  echo "runtime finalization ignored an unavailable notification service" >&2
  exit 1
fi
[[ ! -e $HOME/.local/share/monarch ]]
[[ -d $HOME/.local/share/monarch-v4/.git ]]
[[ $(<"$HOME/.local/share/monarch-v4/user-config/noctalia/settings.json") == "legacy-settings" ]]
[[ $(<"$HOME/.local/share/monarch-v4/user-config/noctalia/user-templates.toml") == "legacy" ]]
[[ $(<"$HOME/.local/share/monarch-v4/user-config/noctalia/colorschemes/User/palette.json") == "user-palette" ]]
[[ $(<"$HOME/.local/share/monarch-v4/user-config/noctalia/plugins/user/plugin.qml") == "user-plugin" ]]
[[ ! -e $runtime_hook ]]
[[ $(<"$HOME/.local/state/monarch/schema") == "2" ]]
[[ ! -e $HOME/.local/state/monarch/reconcile ]]
invitation_hook="$HOME/.config/monarch/hooks/post-boot.d/legacy-runtime-cleanup"
[[ -x $invitation_hook ]]

TEST_NOTIFICATION_READY=true bash "$invitation_hook"
[[ ! -e $invitation_hook ]]
grep -qF 'notification -g 󰆴 Monarch V5 upgrade complete' "$TEST_LOG"
grep -qF -- '--action Clean up monarch-launch-floating-terminal-with-presentation monarch-remove-legacy-runtime' "$TEST_LOG"

cp "$ROOT/install/reconcile/noctalia-plugins.sh" "$plugin_hook"
cat >"$TEST_ROOT/bin/reconcile-complete" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >"$(dirname "$TEST_LOG")/reconcile-complete"
EOF
chmod +x "$TEST_ROOT/bin/reconcile-complete"
rm -f "$TEST_ROOT/noctalia-status-count"
TEST_NOCTALIA_READY_AFTER=3 MONARCH_RECONCILE_BIN="$TEST_ROOT/bin/reconcile-complete" \
  bash "$plugin_hook"
[[ ! -e $plugin_hook ]]
[[ $(<"$TEST_ROOT/noctalia-status-count") == "4" ]]
[[ $(<"$TEST_ROOT/reconcile-complete") == "--complete" ]]

prepare_deferred_hooks() {
  local hook_home="$1"
  local hook_runtime="$hook_home/runtime"
  local hook_dir="$hook_home/.config/monarch/hooks/post-boot.d"

  mkdir -p "$hook_runtime/bin" "$hook_home/.local/share/monarch/.git" \
    "$hook_home/.local/state/monarch/reconcile/1-to-2" "$hook_dir"
  touch "$hook_runtime/bin/monarch"
  chmod +x "$hook_runtime/bin/monarch"
  printf '%s\n' complete >"$hook_home/.local/state/monarch/reconcile/1-to-2/system-after-user"
  cp "$ROOT/install/reconcile/noctalia-plugins.sh" "$hook_dir/noctalia-v5-plugins"
  cp "$ROOT/install/reconcile/packaged-runtime.sh" "$hook_dir/packaged-runtime"
}

runtime_first_home="$TEST_ROOT/runtime-first"
prepare_deferred_hooks "$runtime_first_home"
TEST_NOCTALIA=ready TEST_NOTIFICATION_READY=true HOME="$runtime_first_home" \
  MONARCH_RUNTIME_ROOT="$runtime_first_home/runtime" MONARCH_RECONCILE_BIN="$ROOT/bin/monarch-reconcile" \
  bash "$runtime_first_home/.config/monarch/hooks/post-boot.d/packaged-runtime"
[[ ! -e $runtime_first_home/.local/state/monarch/schema ]]
[[ -d $runtime_first_home/.local/share/monarch-v4/.git ]]
TEST_NOCTALIA=ready HOME="$runtime_first_home" MONARCH_RECONCILE_BIN="$ROOT/bin/monarch-reconcile" \
  bash "$runtime_first_home/.config/monarch/hooks/post-boot.d/noctalia-v5-plugins"
[[ $(<"$runtime_first_home/.local/state/monarch/schema") == "2" ]]

plugins_first_home="$TEST_ROOT/plugins-first"
prepare_deferred_hooks "$plugins_first_home"
TEST_NOCTALIA=ready HOME="$plugins_first_home" MONARCH_RECONCILE_BIN="$ROOT/bin/monarch-reconcile" \
  bash "$plugins_first_home/.config/monarch/hooks/post-boot.d/noctalia-v5-plugins"
[[ ! -e $plugins_first_home/.local/state/monarch/schema ]]
[[ -d $plugins_first_home/.local/share/monarch/.git ]]
TEST_NOCTALIA=ready TEST_NOTIFICATION_READY=true HOME="$plugins_first_home" \
  MONARCH_RUNTIME_ROOT="$plugins_first_home/runtime" MONARCH_RECONCILE_BIN="$ROOT/bin/monarch-reconcile" \
  bash "$plugins_first_home/.config/monarch/hooks/post-boot.d/packaged-runtime"
[[ $(<"$plugins_first_home/.local/state/monarch/schema") == "2" ]]
[[ -d $plugins_first_home/.local/share/monarch-v4/.git ]]

archive_only_home="$TEST_ROOT/archive-only"
mkdir -p "$archive_only_home/runtime/bin" \
  "$archive_only_home/.local/state/monarch/reconcile/1-to-2/legacy-noctalia-config"
touch "$archive_only_home/runtime/bin/monarch"
chmod +x "$archive_only_home/runtime/bin/monarch"
printf '%s\n' legacy-settings \
  >"$archive_only_home/.local/state/monarch/reconcile/1-to-2/legacy-noctalia-config/settings.json"
HOME="$archive_only_home" MONARCH_PATH="$ROOT" \
  bash "$ROOT/install/reconcile/schema/1-to-2/runtime-hook.sh"
printf '%s\n' complete \
  >"$archive_only_home/.local/state/monarch/reconcile/1-to-2/system-after-user"
TEST_NOTIFICATION_READY=true HOME="$archive_only_home" \
  MONARCH_RUNTIME_ROOT="$archive_only_home/runtime" MONARCH_RECONCILE_BIN="$ROOT/bin/monarch-reconcile" \
  bash "$archive_only_home/.config/monarch/hooks/post-boot.d/packaged-runtime"
[[ $(<"$archive_only_home/.local/share/monarch-v4/user-config/noctalia/settings.json") == "legacy-settings" ]]
[[ $(<"$archive_only_home/.local/state/monarch/schema") == "2" ]]

nvim_conflict_home="$TEST_ROOT/nvim-conflict"
mkdir -p "$nvim_conflict_home/.config/nvim/lua/config" "$nvim_conflict_home/dotfiles"
printf '%s\n' 'return { custom = true }' >"$nvim_conflict_home/dotfiles/remote_clipboard.lua"
ln -s "$nvim_conflict_home/dotfiles/remote_clipboard.lua" \
  "$nvim_conflict_home/.config/nvim/lua/config/remote_clipboard.lua"
printf '%s\n' 'vim.opt.number = true' \
  >"$nvim_conflict_home/.config/nvim/lua/config/options.lua"
HOME="$nvim_conflict_home" MONARCH_NVIM_CONFIG_DIR="$MONARCH_NVIM_CONFIG_DIR" \
  bash "$ROOT/install/reconcile/schema/1-to-2/nvim.sh"
[[ -L $nvim_conflict_home/.config/nvim/lua/config/remote_clipboard.lua ]]
if grep -qF 'config.remote_clipboard' \
  "$nvim_conflict_home/.config/nvim/lua/config/options.lua"; then
  echo "A custom Nvim provider was enabled without a compatible setup function" >&2
  exit 1
fi

cat >"$TEST_ROOT/bin/gsettings" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_ROOT/gsettings-calls"
EOF
chmod +x "$TEST_ROOT/bin/gsettings"
TEST_ROOT="$TEST_ROOT" bash "$ROOT/install/user/first-run/gnome-theme.sh"
[[ $(<"$TEST_ROOT/gsettings-calls") == $'set org.gnome.desktop.interface gtk-theme Adwaita-dark\nset org.gnome.desktop.interface color-scheme prefer-dark\nset org.gnome.desktop.interface icon-theme Yaru-blue' ]]

if find "$ROOT/migrations" -type f -name '*.sh' -print -quit 2>/dev/null | grep -q .; then
  echo "historical migrations remain" >&2
  exit 1
fi

grep -q '^  monarch-reconcile$' "$ROOT/bin/monarch-update"
grep -qF 'install/config/enable-services.sh' "$ROOT/install/reconcile/system.sh"

echo "All reconciliation tests passed."
