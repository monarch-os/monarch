monarch_noctalia_wait() {
  local attempts=${1:-300}
  local attempt

  for ((attempt = 0; attempt < attempts; attempt++)); do
    noctalia msg status >/dev/null 2>&1 && return 0
    sleep 0.1
  done

  return 1
}
