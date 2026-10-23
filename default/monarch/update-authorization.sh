monarch_update_sanitize_environment() {
  local script=$1 entry name
  local unsets=()
  shift
  while IFS= read -r -d '' entry; do
    name=${entry%%=*}
    case $name in
      BASH_ENV | ENV | SHELLOPTS | BASHOPTS | PS4 | CDPATH | GLOBIGNORE | BASH_FUNC_*%%)
        unsets+=(-u "$name")
        ;;
    esac
  done < <(/usr/bin/env -0)
  if (( ${#unsets[@]} )); then
    exec /usr/bin/env "${unsets[@]}" /bin/bash -p -- "$script" "$@"
  fi
}

monarch_update_select_runtime() {
  local runtime=${update_entrypoint%/*}
  runtime=${runtime%/*}
  if [[ -n ${MONARCH_PATH:-} && $(/usr/bin/realpath -e -- "$MONARCH_PATH") != "$runtime" ]]; then
    echo "MONARCH_PATH does not match this update command." >&2
    return 1
  fi
  export MONARCH_PATH=$runtime
}

monarch_update_revoke_authorization() {
  /usr/bin/sudo -k
}

monarch_update_check_sudo() {
  local help
  help=$(LC_ALL=C /usr/bin/sudo -h 2>&1) || return 1
  if ! /usr/bin/grep -Eq '^usage: sudo .*\[[^]]*N[^]]*\]' <<<"$help"; then
    echo "This sudo does not support --no-update; refusing to run AUR builds with reusable authorization." >&2
    return 1
  fi
  [[ -x $update_sudo_wrapper ]] || {
    echo "The update sudo wrapper is missing." >&2
    return 1
  }
}

monarch_update_authorize() {
  [[ -z $sudo_keepalive_pid ]] || return 0
  /usr/bin/sudo /usr/bin/true || return 1
  local update_pid=$$
  (
    [[ -z ${MONARCH_UPDATE_LOCK_FD:-} ]] || exec {MONARCH_UPDATE_LOCK_FD}>&-
    sleep_pid=""
    trap - EXIT HUP INT
    trap '[[ -z $sleep_pid ]] || kill "$sleep_pid" 2>/dev/null; exit 0' TERM
    while :; do
      /usr/bin/sleep 60 &
      sleep_pid=$!
      wait "$sleep_pid"
      kill -0 "$update_pid" 2>/dev/null || exit 0
      /usr/bin/sudo -n /usr/bin/true 2>/dev/null || exit 0
    done
  ) &
  sudo_keepalive_pid=$!
}

monarch_update_end_authorization() {
  if [[ -n $sudo_keepalive_pid ]]; then
    kill "$sudo_keepalive_pid" 2>/dev/null || true
    wait "$sudo_keepalive_pid" 2>/dev/null || true
    sudo_keepalive_pid=""
  fi
  monarch_update_revoke_authorization
}
