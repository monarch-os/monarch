monarch_install_app_command() {
  local name="$1" packages="$2" package
  local -a package_args=()

  IFS=$' \t\n' read -r -d '' -a package_args < <(printf '%s\0' "$packages")
  if (( ${#package_args[@]} == 0 )); then
    echo "At least one package name is required." >&2
    return 1
  fi

  for package in "${package_args[@]}"; do
    if [[ ! $package =~ ^[a-zA-Z0-9@_+][a-zA-Z0-9@._+-]*$ ]]; then
      printf 'Invalid package name: %s\n' "$package" >&2
      return 1
    fi
  done

  printf '%q ' printf '%s\n' "Installing ${name}..."
  printf '; '
  printf '%q ' monarch-pkg-add "${package_args[@]}"
}
