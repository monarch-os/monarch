set -euo pipefail

mise_data=${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}

for bundle in "$mise_data"/installs/cursor-agent/*; do
  [[ -d $bundle && ! -L $bundle && ! -L $bundle/dist-package ]] || continue
  [[ -f $bundle/dist-package/cursor-agent && -x $bundle/dist-package/cursor-agent ]] || continue
  [[ ! -L $bundle/bin ]] || continue
  [[ ! -e $bundle/bin || -d $bundle/bin ]] || continue
  [[ ! -e $bundle/bin/cursor-agent && ! -L $bundle/bin/cursor-agent ]] || continue

  mkdir -p "$bundle/bin"
  ln -s ../dist-package/cursor-agent "$bundle/bin/cursor-agent"
done
