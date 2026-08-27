mkdir -p "$HOME/Work" "$HOME/Work/tries"
cat >"$HOME/Work/.mise.toml" <<'EOF'
[env]
_.path = "{{ cwd }}/bin"
EOF
mise trust "$HOME/Work/.mise.toml"

case ${MONARCH_SETUP_CONTEXT:-runtime} in
  iso-chroot) node_package_dir=/opt/packages ;;
  provision-owner) node_package_dir=/var/lib/monarch/provisioning/packages ;;
  *) node_package_dir="" ;;
esac

if [[ -n $node_package_dir ]]; then
  node_tarball=$(find "$node_package_dir" -name 'node-v*-linux-x64.tar.gz' -type f 2>/dev/null | head -n 1)
  if [[ -z $node_tarball ]]; then
    if [[ ${MONARCH_SETUP_CONTEXT:-} == provision-owner ]]; then
      echo "Warning: no bundled Node.js tarball in $node_package_dir; trying the network" >&2
      mise use -g node@latest || echo "Warning: Node.js install deferred (no network)" >&2
    else
      echo "Error: bundled Node.js tarball missing from $node_package_dir" >&2
      exit 1
    fi
  else
    node_version=$(basename "$node_tarball" | sed 's/node-v\(.*\)-linux-x64.tar.gz/\1/')
    node_install_dir="$HOME/.local/share/mise/installs/node/$node_version"
    mkdir -p "$node_install_dir"
    tar -xzf "$node_tarball" --strip-components=1 -C "$node_install_dir"
    mise use -g node@"$node_version"
  fi
else
  mise use -g node@latest
fi
