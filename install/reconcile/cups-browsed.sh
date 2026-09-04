set -euo pipefail

marker=${MONARCH_CUPS_BROWSED_RETIREMENT_MARKER:-/var/lib/monarch/reconcile/cups-browsed-removed}
unit_link=${MONARCH_CUPS_BROWSED_UNIT_LINK:-/etc/systemd/system/multi-user.target.wants/cups-browsed.service}
printers_conf=${MONARCH_CUPS_PRINTERS_CONF:-/etc/cups/printers.conf}

record_retirement() {
  local marker_dir stage

  marker_dir=${marker%/*}
  [[ ! -L $marker_dir && ( ! -e $marker_dir || -d $marker_dir ) ]] || {
    echo "Invalid cups-browsed retirement state directory: $marker_dir" >&2
    return 1
  }
  install -d -m 0755 "$marker_dir"
  stage=$(mktemp "$marker_dir/.cups-browsed-removed.XXXXXX")
  chmod 0644 "$stage"
  mv -fT "$stage" "$marker"
}

stop_discovery() {
  local load_state

  if ! load_state=$(systemctl show cups-browsed.service \
    --property=LoadState --value 2>&1); then
    printf '%s\n' "$load_state" >&2
    return 1
  fi

  case $load_state in
    loaded | masked) systemctl disable --now cups-browsed.service >/dev/null ;;
    not-found) ;;
    *)
      echo "Unexpected cups-browsed service state: $load_state" >&2
      return 1
      ;;
  esac
}

cups_browsed_installed() {
  local query_output query_status

  if query_output=$(LC_ALL=C pacman -Qq cups-browsed 2>&1); then
    [[ $query_output == cups-browsed ]] || {
      echo "Unexpected cups-browsed package query result: $query_output" >&2
      return 2
    }
    return 0
  else
    query_status=$?
  fi

  if ((query_status == 1)) &&
    [[ $query_output == "error: package 'cups-browsed' was not found" ]]; then
    return 1
  fi
  printf '%s\n' "$query_output" >&2
  return 2
}

remove_stale_unit_link() {
  if [[ -L $unit_link ]]; then
    rm -f -- "$unit_link"
  elif [[ -e $unit_link ]]; then
    echo "Invalid cups-browsed enablement path: $unit_link" >&2
    return 1
  fi
}

cleanup_generated_queues() {
  local queue_report generated_queues queue reject_error job_report delete_error

  if queue_report=$(LC_ALL=C lpstat -v 2>&1); then
    :
  elif [[ $queue_report == "lpstat: No destinations added." ]]; then
    queue_report=""
  else
    printf '%s\n' "$queue_report" >&2
    return 1
  fi

  generated_queues=$(printf '%s\n' "$queue_report" |
    sed -n 's|^device for \(.*\): implicitclass://.*|\1|p')

  while IFS= read -r queue; do
    [[ -n $queue ]] || continue
    if [[ ! $queue =~ ^[A-Za-z0-9_.:][A-Za-z0-9_.:-]*$ || $queue == "all" ]]; then
      printf 'Leaving generated queue with unsafe name for manual removal: %q\n' "$queue" >&2
      continue
    fi

    if ! reject_error=$(LC_ALL=C cupsreject \
      -r "Automatic printer discovery has been removed from Monarch" "$queue" 2>&1); then
      if LC_ALL=C lpstat -p "$queue" >/dev/null 2>&1; then
        printf '%s\n' "$reject_error" >&2
        return 1
      fi
      continue
    fi

    if job_report=$(LC_ALL=C lpstat -o "$queue" 2>&1); then
      if [[ -n $job_report ]]; then
        echo "$queue still has jobs and was left for manual removal." >&2
        continue
      fi
    elif LC_ALL=C lpstat -p "$queue" >/dev/null 2>&1; then
      printf '%s\n' "$job_report" >&2
      return 1
    else
      continue
    fi

    if ! delete_error=$(LC_ALL=C lpadmin -x "$queue" 2>&1) &&
      LC_ALL=C lpstat -p "$queue" >/dev/null 2>&1; then
      printf '%s\n' "$delete_error" >&2
      return 1
    fi
  done <<<"$generated_queues"
}

if [[ -f $marker && ! -L $marker ]]; then
  exit 0
elif [[ -e $marker || -L $marker ]]; then
  echo "Invalid cups-browsed retirement marker: $marker" >&2
  exit 1
fi

stop_discovery

package_installed=false
if cups_browsed_installed; then
  package_installed=true
else
  query_status=$?
  ((query_status == 1)) || exit "$query_status"
fi

if [[ $package_installed == false ]]; then
  if [[ -L $printers_conf || ( -e $printers_conf && ! -f $printers_conf ) ]]; then
    echo "Invalid CUPS printer configuration: $printers_conf" >&2
    exit 1
  fi
  if [[ -f $printers_conf ]] &&
    grep -qE '^[[:space:]]*DeviceURI[[:space:]]+implicitclass:' "$printers_conf"; then
    cleanup_generated_queues
  fi
  remove_stale_unit_link
  systemctl daemon-reload >/dev/null 2>&1 || true
  record_retirement
  exit 0
fi

removal_blocked=false
pacman -R --print cups-browsed >/dev/null 2>&1 || removal_blocked=true

if [[ $removal_blocked == "true" ]]; then
  echo "cups-browsed has dependents; discovery is disabled and removal will retry later." >&2
  exit 1
fi

cleanup_generated_queues
pacman -R --noconfirm cups-browsed
remove_stale_unit_link
record_retirement
