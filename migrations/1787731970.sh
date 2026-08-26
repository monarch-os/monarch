echo "Enable the Monarch theme selectors"

plugin_src="$MONARCH_PATH/default/noctalia/plugins/monarch-theme"
plugin_dst="$HOME/.local/share/noctalia/plugins/monarch-theme"

mkdir -p "$plugin_dst"
cp -rf "$plugin_src"/. "$plugin_dst/"

if noctalia msg status >/dev/null 2>&1; then
  noctalia msg plugins enable monarch/theme >/dev/null 2>&1 || true
else
  hook_dir="$HOME/.config/monarch/hooks/post-boot.d"
  mkdir -p "$hook_dir"
  cat >"$hook_dir/noctalia-theme-plugin" <<'HOOK'
#!/bin/bash

noctalia msg status >/dev/null 2>&1 || exit 0
noctalia msg plugins enable monarch/theme >/dev/null 2>&1 || exit 0
rm -f "$0"
HOOK
  chmod 755 "$hook_dir/noctalia-theme-plugin"
fi
