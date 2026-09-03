set -euo pipefail

nvim_plugins="$HOME/.config/nvim/lua/plugins"
legacy_nvim_theme="$HOME/.config/monarch/current/theme/neovim.lua"
if [[ -L $nvim_plugins/theme.lua && $(readlink "$nvim_plugins/theme.lua") == $legacy_nvim_theme ]]; then
  rm -f "$nvim_plugins/theme.lua"
fi
rm -f "$nvim_plugins/omarchy-theme-hotreload.lua"

nvim_config="$HOME/.config/nvim"
nvim_options="$nvim_config/lua/config/options.lua"
nvim_provider="$nvim_config/lua/config/remote_clipboard.lua"
nvim_package_config="${MONARCH_NVIM_CONFIG_DIR:-/usr/share/monarch-nvim/config}"
nvim_provider_source="$nvim_package_config/lua/config/remote_clipboard.lua"
if [[ -d $nvim_config && -f $nvim_provider_source ]]; then
  provider_ready=false
  if [[ ! -e $nvim_provider && ! -L $nvim_provider ]]; then
    mkdir -p "$(dirname "$nvim_provider")"
    provider_tmp=$(mktemp "$nvim_config/lua/config/.remote-clipboard.XXXXXX")
    trap 'rm -f "$provider_tmp"' EXIT
    install -m 0644 "$nvim_provider_source" "$provider_tmp"
    mv "$provider_tmp" "$nvim_provider"
    trap - EXIT
    provider_ready=true
  elif [[ -f $nvim_provider ]] && cmp -s "$nvim_provider_source" "$nvim_provider"; then
    provider_ready=true
  fi
  if [[ $provider_ready == "true" && -f $nvim_options ]] &&
    ! grep -qF 'config.remote_clipboard' "$nvim_options"; then
    options_target=$(readlink -e "$nvim_options")
    options_tmp=$(mktemp "$(dirname "$options_target")/.options.XXXXXX")
    trap 'rm -f "$options_tmp"' EXIT
    {
      printf '%s\n' 'require("config.remote_clipboard").setup()'
      cat "$options_target"
    } >"$options_tmp"
    chmod --reference="$options_target" "$options_tmp"
    mv "$options_tmp" "$options_target"
    trap - EXIT
  fi
fi
