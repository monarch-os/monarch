set -euo pipefail

state="$HOME/.local/state/monarch/reconcile/1-to-2/legacy-noctalia"
archive="$HOME/.local/state/monarch/reconcile/1-to-2/legacy-noctalia-config"
[[ ! -f $state ]] || exit 0

archive_legacy_path() {
  local source="$1"
  local relative_path="$2"
  local destination="$archive/$relative_path"

  [[ -e $source || -L $source ]] || return 0
  if [[ -e $destination || -L $destination ]]; then
    echo "Cannot preserve legacy Noctalia data: $destination already exists" >&2
    return 1
  fi
  mkdir -p "$(dirname "$destination")"
  mv "$source" "$destination"
}

remove_legacy_template() {
  local template_file="$1"
  local legacy_checksum="$2"
  local current_checksum

  [[ -f $template_file && ! -L $template_file ]] || return 0
  current_checksum=$(sha256sum "$template_file")
  current_checksum=${current_checksum%% *}
  [[ $current_checksum != $legacy_checksum ]] || rm -f "$template_file"
}

pkill -f 'qs.*noctalia-shell' 2>/dev/null || true

monarch-refresh-config herdr/config.toml
monarch-refresh-config fastfetch/config.jsonc

for legacy_file in "$HOME"/.config/noctalia/settings.json \
  "$HOME"/.config/noctalia/settings.json.bak.* \
  "$HOME"/.config/noctalia/user-templates.toml \
  "$HOME"/.config/noctalia/user-templates.toml.bak.* \
  "$HOME"/.config/noctalia/plugins.json; do
  archive_legacy_path "$legacy_file" "${legacy_file#"$HOME/.config/noctalia/"}"
done
archive_legacy_path "$HOME/.config/noctalia/colorschemes" colorschemes
archive_legacy_path "$HOME/.config/noctalia/plugins" plugins
rm -f "$HOME/.cache/noctalia/shell-state.json" "$HOME/.cache/noctalia/wallpapers.json"
rm -rf "$HOME/.cache/noctalia-qs"
remove_legacy_template "$HOME/.config/noctalia/templates/fuzzel.ini" \
  12df7f9bd7310c133ce96caaf51dd2f81fe4ac2894cdbd8ab5421012152d3733
remove_legacy_template "$HOME/.config/noctalia/templates/herdr.toml" \
  3959426bdc72aab761291e1c6e8d571fb11af7f3e41c2b294769cf6ae0069075
remove_legacy_template "$HOME/.config/noctalia/templates/nvim-base16.lua" \
  4970133a9d79f3f9c24c1fd4c5071b7c11ef14da89be2ba4412591ccfc5f3365
remove_legacy_template "$HOME/.config/noctalia/templates/obsidian.css" \
  36dfd6e3b1dc4c98f9a5234815ea09a204fab4ef9d297a3ac6cb6013240548be
remove_legacy_template "$HOME/.config/noctalia/templates/sddm.conf" \
  41255868a7fdc8a634e0b9e8315afd9647518637c9014f50e725b8b46c5e3e79
remove_legacy_template "$HOME/.config/noctalia/templates/zed.json" \
  fe03f8557debc88434732e786b5c5c149c992be7982a159f12a7b532aefaf015
rmdir "$HOME/.config/noctalia/templates" 2>/dev/null || true
rm -f "$HOME/.config/environment.d/noctalia-fingerprint.conf"

if [[ -f $HOME/.local/state/monarch/fingerprint-enabled ]]; then
  cat >"$HOME/.config/noctalia/monarch-fingerprint.toml" <<'EOF'
[lockscreen]
fingerprint = true
EOF
fi

mkdir -p "$(dirname "$state")"
printf '%s\n' complete >"$state.tmp"
mv "$state.tmp" "$state"
