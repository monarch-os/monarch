# Parse the persistent Niri workspace-name file once for every consumer.
# Blank lines and comments are ignored; Niri exposes at most ten numbered
# shortcuts, so additional names cannot be addressed and are discarded.
monarch_read_workspace_names() {
  local names_file="$1"
  local output_name="$2"
  local -n output="$output_name"
  local line trimmed

  output=()
  [[ -f $names_file ]] || return 0

  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [[ -z $trimmed ]] && continue
    output+=("$trimmed")
    (( ${#output[@]} >= 10 )) && break
  done <"$names_file"
}
