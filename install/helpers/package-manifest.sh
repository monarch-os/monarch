monarch_load_package_manifest() {
  local -n result="$1"
  local manifest="$2"
  local requested_section="${3:-all}"
  local section=""
  local found=false
  local line

  result=()

  [[ $requested_section == "all" || $requested_section == "required" || $requested_section == "preinstalled" ]] || {
    echo "Unknown package manifest section: $requested_section" >&2
    return 1
  }

  while IFS= read -r line || [[ -n $line ]]; do
    case "$line" in
    "# required")
      section=required
      [[ $requested_section != "required" ]] || found=true
      ;;
    "# preinstalled")
      section=preinstalled
      [[ $requested_section != "preinstalled" ]] || found=true
      ;;
    "" | \#*) ;;
    *)
      [[ -n $section ]] || {
        echo "Package found before a manifest section: $line" >&2
        return 1
      }
      [[ $line =~ ^[a-zA-Z0-9@._+-]+$ ]] || {
        echo "Invalid package name in manifest: $line" >&2
        return 1
      }
      [[ $requested_section == "all" || $requested_section == "$section" ]] && result+=("$line")
      ;;
    esac
  done <"$manifest"

  [[ $requested_section == "all" || $found == true ]] || {
    echo "Missing package manifest section: $requested_section" >&2
    return 1
  }
}
