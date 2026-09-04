set -euo pipefail

user_unit_dir=${MONARCH_USER_SYSTEMD_DIR:-$HOME/.config/systemd/user}
vendor_unit_dir=${MONARCH_SYSTEMD_USER_VENDOR_DIR:-/usr/lib/systemd/user}
state_dir="$HOME/.local/state/monarch/reconcile/1-to-2/legacy-user-files"

file_matches() {
  local file="$1"
  local expected_checksum="$2"
  local checksum

  [[ -f $file && ! -L $file ]] || return 1
  checksum=$(sha256sum "$file")
  checksum=${checksum%% *}
  [[ $checksum == $expected_checksum ]]
}

valid_enable_state() {
  case $1 in
    enabled | enabled-runtime | disabled | static | indirect | alias | linked | linked-runtime | masked | masked-runtime | generated | transient) return 0 ;;
    *) return 1 ;;
  esac
}

valid_active_state() {
  case $1 in
    active | reloading | inactive | failed | activating | deactivating | maintenance | refreshing) return 0 ;;
    *) return 1 ;;
  esac
}

prepare_unit() {
  local unit="$1"
  local legacy_checksum="$2"
  local target="$user_unit_dir/$unit"
  local replacement="$vendor_unit_dir/$unit"
  local marker="$state_dir/$unit"
  local enable_state active_state temporary

  if [[ -f $marker ]]; then
    [[ -f $replacement ]] || {
      echo "Cannot replace legacy user unit: $replacement is unavailable" >&2
      return 1
    }
    if [[ -e $target || -L $target ]]; then
      if file_matches "$target" "$legacy_checksum"; then
        rm -f "$target"
      else
        rm -f "$marker"
      fi
    fi
    return 0
  fi

  file_matches "$target" "$legacy_checksum" || return 0
  [[ -f $replacement ]] || {
    echo "Cannot replace legacy user unit: $replacement is unavailable" >&2
    return 1
  }

  enable_state=$(systemctl --user is-enabled "$unit" 2>/dev/null || true)
  active_state=$(systemctl --user is-active "$unit" 2>/dev/null || true)
  valid_enable_state "$enable_state" || {
    echo "Cannot determine whether $unit is enabled" >&2
    return 1
  }
  valid_active_state "$active_state" || {
    echo "Cannot determine whether $unit is active" >&2
    return 1
  }

  mkdir -p "$state_dir"
  temporary=$(mktemp "$state_dir/.${unit}.XXXXXX")
  printf '%s\t%s\n' "$enable_state" "$active_state" >"$temporary"
  mv "$temporary" "$marker"
  rm -f "$target"
}

remove_legacy_file() {
  local file="$1"
  local legacy_checksum="$2"

  file_matches "$file" "$legacy_checksum" || return 0
  rm -f "$file"
}

declare -A unit_checksums=(
  [monarch-recover-internal-monitor.service]=a60226f83b010601daa675cec6dd065851e3cf6cd66176cc5df687420bf0e1fc
  [monarch-battery-monitor.service]=f8a2f9a09f9b189c1d49e39e00bd74e010b2f7323c27f451878d3ce581d66a1c
  [monarch-battery-monitor.timer]=e073738fdaadb814f04fcf9be55ac99a167f6c863d494da5b67b65d87d209761
)

for unit in "${!unit_checksums[@]}"; do
  prepare_unit "$unit" "${unit_checksums[$unit]}"
done

pending=false
for unit in "${!unit_checksums[@]}"; do
  [[ ! -f $state_dir/$unit ]] || pending=true
done

if [[ $pending == "true" ]]; then
  systemctl --user daemon-reload

  for unit in "${!unit_checksums[@]}"; do
    marker="$state_dir/$unit"
    [[ -f $marker ]] || continue
    [[ -f $vendor_unit_dir/$unit ]] || {
      echo "Cannot replace legacy user unit: $vendor_unit_dir/$unit is unavailable" >&2
      exit 1
    }

    IFS=$'\t' read -r enable_state active_state <"$marker"
    if ! valid_enable_state "$enable_state" || ! valid_active_state "$active_state"; then
      echo "Invalid legacy user unit state: $unit" >&2
      exit 1
    fi

    case $enable_state in
      enabled) systemctl --user reenable "$unit" ;;
      enabled-runtime) systemctl --user --runtime reenable "$unit" ;;
    esac

    case $active_state in
      active | reloading | activating | refreshing)
        systemctl --user restart "$unit"
        ;;
      failed)
        case $enable_state in
          enabled | enabled-runtime) systemctl --user restart "$unit" ;;
        esac
        ;;
    esac

    rm -f "$marker"
  done

  rmdir "$state_dir" 2>/dev/null || true
fi

remove_legacy_file "$HOME/.config/monarch/extensions/menu.sh" \
  39f459e47012c9a6c827fa1b52bfeb57b2e84b2e614f3a490dd48f35cbffd974
remove_legacy_file "$HOME/.config/monarch/hooks/theme-set.d/show-theme-notification.sample" \
  85de7c0a6f12ae796663c409ad198d15d20d254a1444db66e0680ab7326f826e
