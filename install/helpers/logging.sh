monarch_log_to_stdout() {
  [[ ${MONARCH_LOG_TO_STDOUT:-} == "1" || -z ${MONARCH_INSTALL_LOG_FILE:-} ]]
}

monarch_log_line() {
  if monarch_log_to_stdout; then echo "$1"; else echo "$1" >>"$MONARCH_INSTALL_LOG_FILE"; fi
}

start_install_log() {
  if ! monarch_log_to_stdout; then
    mkdir -p "$(dirname "$MONARCH_INSTALL_LOG_FILE")"
    touch "$MONARCH_INSTALL_LOG_FILE"
    chmod 666 "$MONARCH_INSTALL_LOG_FILE" 2>/dev/null || true
  fi
  export MONARCH_START_TIME="${MONARCH_START_TIME:-$(date '+%Y-%m-%d %H:%M:%S')}"
  export MONARCH_START_EPOCH="${MONARCH_START_EPOCH:-$(date +%s)}"
  monarch_log_line "=== Monarch Setup Started: $MONARCH_START_TIME ==="
}

stop_install_log() {
  local end_time end_epoch duration mins secs
  end_time=$(date '+%Y-%m-%d %H:%M:%S'); end_epoch=$(date +%s)
  monarch_log_line "=== Monarch Setup Completed: $end_time ==="
  if [[ -n ${MONARCH_START_EPOCH:-} ]]; then
    duration=$((end_epoch - MONARCH_START_EPOCH)); mins=$((duration / 60)); secs=$((duration % 60))
    monarch_log_line "Monarch setup: ${mins}m ${secs}s"
  fi
}

run_logged() {
  local script="$1" exit_code errexit_was_set=0
  monarch_log_line "[$(date '+%Y-%m-%d %H:%M:%S')] Starting: $script"
  case $- in *e*) errexit_was_set=1; set +e ;; esac
  local runner=(bash -eE)
  [[ ${MONARCH_INSTALL_DEBUG:-} == "1" ]] && runner=(bash -x -eE)
  if monarch_log_to_stdout; then
    PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO}:${FUNCNAME[0]:-main}: ' "${runner[@]}" -c 'source "$1"' bash "$script" </dev/null 2>&1
  else
    PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO}:${FUNCNAME[0]:-main}: ' "${runner[@]}" -c 'source "$1"' bash "$script" </dev/null >>"$MONARCH_INSTALL_LOG_FILE" 2>&1
  fi
  exit_code=$?; (( errexit_was_set )) && set -e
  if (( exit_code == 0 )); then
    monarch_log_line "[$(date '+%Y-%m-%d %H:%M:%S')] Completed: $script"
  else
    monarch_log_line "[$(date '+%Y-%m-%d %H:%M:%S')] Failed: $script (exit code: $exit_code)"
  fi
  return $exit_code
}
