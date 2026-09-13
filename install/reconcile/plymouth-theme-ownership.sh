set -euo pipefail

if ((EUID == 0)); then
  theme_dir=/usr/share/plymouth/themes/monarch
else
  theme_dir=${MONARCH_PLYMOUTH_OWNERSHIP_TEST_DIR:?}
fi

[[ ! -L $theme_dir ]] || {
  echo "Refusing to repair a symlinked Plymouth theme directory: $theme_dir" >&2
  exit 1
}
[[ -d $theme_dir ]] || exit 0

chown root:root "$theme_dir"
chmod 0755 "$theme_dir"
