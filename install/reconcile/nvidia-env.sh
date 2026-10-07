monarch_nvidia_environment() {
  local architecture=$1 display=$2

  case $architecture in
    turing_plus)
      printf '%s\n' '# NVIDIA (Turing+ with GSP firmware) — managed by monarch-install-nvidia' 'NVD_BACKEND=direct'
      [[ $display != "true" ]] || printf '%s\n' 'LIBVA_DRIVER_NAME=nvidia' '__GLX_VENDOR_LIBRARY_NAME=nvidia'
      ;;
    maxwell_pascal_volta)
      printf '%s\n' '# NVIDIA (Maxwell/Pascal/Volta without GSP firmware) — managed by monarch-install-nvidia' 'NVD_BACKEND=egl'
      [[ $display != "true" ]] || printf '%s\n' '__GLX_VENDOR_LIBRARY_NAME=nvidia'
      ;;
    *) return 1 ;;
  esac
  return 0
}

monarch_reconcile_nvidia_environment() {
  local architecture=${1:-} display=false file="$HOME/.config/environment.d/nvidia.conf"
  local known_architecture known_display recognized=false temporary

  if [[ -z $architecture ]]; then
    monarch-hw-nvidia || return 0
    if monarch-hw-nvidia-gsp; then
      architecture=turing_plus
    elif monarch-hw-nvidia-without-gsp; then
      architecture=maxwell_pascal_volta
    else
      return 0
    fi
  fi
  case $architecture in
    turing_plus)
      monarch-pkg-present nvidia-open-dkms nvidia-utils libva-nvidia-driver || return 0
      ;;
    maxwell_pascal_volta)
      monarch-pkg-present nvidia-580xx-dkms nvidia-580xx-utils || return 0
      ;;
    *) return 0 ;;
  esac
  monarch-hw-nvidia-display && display=true

  if [[ -L $file || ( -e $file && ! -f $file ) ]]; then
    echo "Keeping custom NVIDIA environment: $file" >&2
    return 0
  fi
  if [[ -f $file ]]; then
    cmp -s "$file" <(monarch_nvidia_environment "$architecture" "$display") && return 0
    for known_architecture in turing_plus maxwell_pascal_volta; do
      for known_display in true false; do
        if cmp -s "$file" <(monarch_nvidia_environment "$known_architecture" "$known_display"); then
          recognized=true
        fi
      done
    done
    if [[ $recognized == "false" ]]; then
      echo "Keeping custom NVIDIA environment: $file" >&2
      return 0
    fi
  fi

  mkdir -p "${file%/*}"
  temporary=$(mktemp "${file%/*}/.monarch-nvidia.XXXXXX") || return 1
  if monarch_nvidia_environment "$architecture" "$display" >"$temporary" &&
    mv -fT -- "$temporary" "$file"; then
    echo "NVIDIA session environment updated; log out or reboot to apply it."
    return 0
  fi
  rm -f -- "$temporary"
  return 1
}
