#!/bin/bash

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

runtime="$test_tmp/runtime"
home="$test_tmp/home"
mkdir -p "$runtime/default/niri" "$runtime/config/niri" "$runtime/install/helpers" "$home" "$test_tmp/bin"
cp "$ROOT/default/niri/config.kdl" "$runtime/default/niri/config.kdl"
cp "$ROOT/config/niri/"{user.kdl,noctalia.kdl,workspaces.conf} "$runtime/config/niri/"
cp "$ROOT/install/helpers/workspaces.sh" "$runtime/install/helpers/workspaces.sh"

cat >"$test_tmp/bin/niri" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$test_tmp/bin/niri"

if ! HOME="$home" MONARCH_PATH="$runtime" PATH="$test_tmp/bin:$PATH" \
  bash "$ROOT/bin/monarch-refresh-niri"; then
  fail "refresh niri runs against the packaged runtime fixture"
fi

target="$home/.config/niri/config.kdl"
[[ -f $target ]] || fail "refresh niri creates the packaged user entry point"
grep -qF "include \"$runtime/default/niri/environment.kdl\"" "$target" ||
  fail "refresh niri expands the selected runtime path"
if grep -qF '.local/share/monarch' "$target"; then
  fail "the generated Niri entry point still references a checkout"
fi
pass "refresh niri uses MONARCH_PATH for packaged defaults"

grep -qF 'MONARCH_PATH=${MONARCH_PATH:-/usr/share/monarch}' "$ROOT/config/uwsm/env" ||
  fail "the graphical session does not default to the packaged runtime"
grep -qF 'MONARCH_RUNTIME_ROOT:-/usr/share/monarch' "$ROOT/default/shells/envs" ||
  fail "shell sessions do not prefer the packaged runtime"
grep -qF 'MONARCH_PATH=$HOME/.local/share/monarch' "$ROOT/default/shells/envs" ||
  fail "shell sessions cannot recover through the legacy checkout"
for rc in "$ROOT/default/zsh/rc" "$ROOT/default/bash/rc"; do
  grep -qF '${MONARCH_RUNTIME_ROOT:-/usr/share/monarch}/bin/monarch' "$rc" ||
    fail "$(basename "$(dirname "$rc")") does not check the packaged runtime"
  grep -qF 'MONARCH_PATH=$HOME/.local/share/monarch' "$rc" ||
    fail "$(basename "$(dirname "$rc")") cannot recover through the legacy checkout"
done
pass "login sessions prefer the packaged runtime and retain upgrade recovery"

grep -qF '${MONARCH_INSTALL:-${MONARCH_PATH:-/usr/share/monarch}/install}/helpers/workspaces.sh' \
  "$ROOT/install/user/detect-keyboard-layout.sh" ||
  fail "keyboard detection does not fall back from MONARCH_INSTALL to the packaged runtime"
pass "keyboard detection resolves helpers from the packaged runtime"

if grep -R -q '%h/.local/share/monarch/bin/' "$ROOT/config/systemd/user"; then
  fail "a user service still invokes a checkout-only command path"
fi
pass "user services invoke packaged Monarch commands"

for plugin in theme background unlock; do
  plugin_file="$ROOT/default/noctalia/plugins/monarch-theme/$plugin.luau"
  grep -qF 'noctalia.getenv("MONARCH_PATH") or "/usr/share/monarch"' "$plugin_file" ||
    fail "the Monarch $plugin panel does not default to the packaged runtime"
done
pass "theme panels invoke commands from the packaged Monarch runtime"

for command in monarch-theme-apply monarch-theme-bundle monarch-theme-list; do
  grep -qF '$HOME/.config/monarch/themes' "$ROOT/bin/$command" ||
    fail "$command does not keep user themes under ~/.config/monarch"
done
grep -qF '$HOME/.config/monarch/themes' "$ROOT/default/monarch/monarch-menu.jsonc" ||
  fail "the menu does not discover user themes under ~/.config/monarch"
[[ ! -e $ROOT/bin/monarch-reinstall-git ]] ||
  fail "the package runtime still exposes the checkout reinstaller"
pass "user themes and reinstall workflows no longer depend on a source checkout"

runtime_commands=(
  monarch-install-tailscale
  monarch-plymouth-preview
  monarch-refresh-sddm
  monarch-theme-background-import
  monarch-theme-background-list
  monarch-theme-background-remove
  monarch-theme-list
  monarch-unlock-list
)
for command in "${runtime_commands[@]}"; do
  if grep -Eq '\$HOME/\.local/share/monarch/(bin|config|default|install|themes)' "$ROOT/bin/$command"; then
    fail "$command still defaults to a checkout-only runtime"
  fi
done
pass "theme and Tailscale commands default to the packaged Monarch runtime"
