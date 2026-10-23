set -euo pipefail

if (( EUID == 0 )); then
  export PATH=/usr/bin:/usr/sbin
fi
source "${BASH_SOURCE[0]%/*}/../helpers/root-file.sh"
monarch_root_file_context system_root runtime_root trusted_uid stop test_mode
if (( EUID != 0 && ! test_mode )); then
  echo "The initramfs keyboard repair must run as root" >&2
  exit 1
fi

config="$system_root/etc/mkinitcpio.conf"
config_dir="$system_root/etc/mkinitcpio.conf.d"
guard="$config_dir/monarch_vconsole.conf"
vconsole="$system_root/etc/vconsole.conf"
plymouth_hook="$system_root/usr/lib/initcpio/install/plymouth"
state_dir="$system_root/var/lib/monarch"
marker="$state_dir/vconsole-initramfs.sha256"

[[ -f $vconsole && -f $plymouth_hook ]] || exit 0
grep -q 'vconsole\.conf' "$plymouth_hook" || exit 0
[[ -f $config && -f $guard ]] || {
  echo "Missing the packaged initramfs keyboard configuration" >&2
  exit 1
}
[[ ! -L $state_dir && ! -L $marker ]] || {
  echo "Refusing symlinked initramfs keyboard rebuild state" >&2
  exit 1
}

# Evaluate final FILES, including administrator drop-ins, before deciding whether
# old images need repair. The probe never builds an image or runs install hooks.
if bash -c '
  FILES=() HOOKS=() MODULES=()
  _monarch_vconsole_probe_copied=false
  add_file() { _monarch_vconsole_probe_copied=true; }
  configs=("$1")
  mapfile -d "" -t dropins < <(find "$2" -maxdepth 1 -xtype f -name "*.conf" -print0 | LC_ALL=C.UTF-8 sort -zVu)
  for dropin in "${dropins[@]}"; do
    [[ ! -r $dropin ]] || configs+=("$dropin")
  done
  source <(cat -- "${configs[@]}") >/dev/null || exit 2
  [[ " ${HOOKS[*]} " == *" plymouth "* ]] || exit 1
  add_file "$3" >/dev/null || exit 2
  $_monarch_vconsole_probe_copied && exit 1
  exit 0
' -- "$config" "$config_dir" "$vconsole"; then
  :
else
  status=$?
  (( status == 1 )) && exit 0
  echo "Could not evaluate the initramfs keyboard configuration" >&2
  exit "$status"
fi

# An explicit preset config makes mkinitcpio use -c, disabling all drop-ins,
# even when it names /etc/mkinitcpio.conf. Check before trusting an older marker.
for preset in "$system_root/etc/mkinitcpio.d/"*.preset; do
  [[ -e $preset || -L $preset ]] || continue
  if ! bash -c '
    PRESETS=() ALL_config=""
    source "$1" >/dev/null || exit 1
    for image in "${PRESETS[@]}"; do
      [[ $image =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || exit 1
      config_key="${image}_config"
      effective_config=${!config_key:-$ALL_config}
      if [[ -n $effective_config ]]; then
        printf "Cannot verify the LUKS keyboard guard: %s (%s) selects config %s and bypasses mkinitcpio drop-ins.\n" \
          "$1" "$image" "$effective_config" >&2
        exit 1
      fi
    done
  ' -- "$preset"; then
    echo "Review $preset; the initramfs keyboard repair remains pending. Administrator configuration was preserved." >&2
    exit 1
  fi
done

digest=$(sha256sum "$guard")
digest=${digest%% *}
if [[ -e $state_dir ]]; then
  monarch_root_file_trusted_directory "$state_dir" "$trusted_uid" "$stop"
fi
if [[ -e $marker ]]; then
  monarch_root_file_trusted_source "$marker" "$trusted_uid" "$stop"
  [[ $(<"$marker") != "$digest" ]] || exit 0
fi

rebuild=(mkinitcpio -P)
if command -v limine-mkinitcpio >/dev/null 2>&1; then
  rebuild=(limine-mkinitcpio)
fi

if [[ ! -d $state_dir ]]; then
  monarch_root_file_trusted_directory "${state_dir%/*}" "$trusted_uid" "$stop"
  install -d -m 0755 "$state_dir"
fi
log=$(mktemp "$state_dir/.vconsole-rebuild.XXXXXX")
candidate=""
trap 'rm -f -- "$log" "$candidate"' EXIT
echo "Rebuild boot images without the non-Latin Plymouth keyboard layout"
"${rebuild[@]}" 2>&1 | tee "$log"
if grep -q 'mkinitcpio failed for kernel' "$log"; then
  echo "A boot image was not rebuilt; reconciliation must be retried before rebooting" >&2
  exit 1
fi

candidate=$(mktemp "$state_dir/.vconsole-initramfs.XXXXXX")
printf '%s\n' "$digest" >"$candidate"
chmod 0644 "$candidate"
mv -fT -- "$candidate" "$marker"
