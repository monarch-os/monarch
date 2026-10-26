monarch_configure_lazyvpn() {
  local root=$1 config_dir=${XDG_CONFIG_HOME:-$HOME/.config} data_dir=${XDG_DATA_HOME:-$HOME/.local/share}
  local source target relative legacy

  /usr/bin/monarch-lazyvpn --preview --help >/dev/null 2>&1 || {
    echo "LazyVPN 0.2.0 or newer is required for graphical integration." >&2
    return 1
  }
  [[ -f /usr/share/monarch-lazyvpn/noctalia/lazyvpn.json && -f /usr/share/applications/monarch-lazyvpn.desktop ]] || return 1
  for relative in niri/monarch-lazyvpn.kdl noctalia/lazyvpn.toml; do
    [[ -f $root/default/monarch/lazyvpn/$relative ]] || return 1
  done

  for relative in niri/monarch-lazyvpn.kdl noctalia/lazyvpn.toml; do
    source="$root/default/monarch/lazyvpn/$relative"
    target="$config_dir/$relative"
    [[ $relative != niri/* ]] || target="$HOME/.config/$relative"
    mkdir -p "$(dirname "$target")"
    if ! cmp -s "$source" "$target"; then
      if [[ -f $target && ! -e $target.pre-gpui ]]; then
        cp -p "$target" "$target.pre-gpui" || return
      fi
      install -m 0644 "$source" "$target" || return
    fi
  done
  target="$HOME/.config/niri/user.kdl"
  touch "$target"
  if ! grep -Eq '^[[:space:]]*include[[:space:]]+"\./monarch-lazyvpn\.kdl"' "$target"; then
    cat >>"$target" <<'EOF'

// monarch:lazyvpn:begin
include "./monarch-lazyvpn.kdl"
// monarch:lazyvpn:end
EOF
  fi

  legacy="$data_dir/applications/LazyVPN.desktop"
  if [[ -f $legacy ]] && grep -Fqx 'Exec=monarch-launch-floating-terminal-with-presentation monarch-lazyvpn' "$legacy"; then
    [[ -e $legacy.pre-gpui ]] || cp -p "$legacy" "$legacy.pre-gpui" || return
    rm -f "$legacy"
  fi
  mkdir -p "$config_dir/monarch-lazyvpn"
  if monarch-cmd-present noctalia; then
    noctalia msg templates-apply >/dev/null 2>&1 || true
  fi
  if [[ -n ${NIRI_SOCKET:-} ]] && pgrep -u "$(id -u)" -x niri >/dev/null 2>&1; then
    niri validate && niri msg action load-config-file || return
  fi
  return 0
}
