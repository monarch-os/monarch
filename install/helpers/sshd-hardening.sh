source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/as-root.sh"

monarch_sshd_hardening_path() {
  echo /etc/ssh/sshd_config.d/10-monarch-hardening.conf
}

monarch_sshd_main_config_path() {
  echo /etc/ssh/sshd_config
}

monarch_sshd_dropin_dir() {
  echo /etc/ssh/sshd_config.d
}

monarch_sshd_hardening_content() {
  cat <<'EOF'
# Managed by Monarch.
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
}

monarch_sshd_has_usable_key() {
  local authorized_keys=$1 user=$2 effective=${3:-}
  local line key_type fingerprint bits key value rest accepted="" required_rsa_size=""

  [[ -f $authorized_keys && -r $authorized_keys ]] || return 1
  [[ -n $effective ]] ||
    effective=$(as_root sshd -T -C "user=$user,host=localhost,addr=127.0.0.1") || return 1
  while read -r key value rest; do
    case ${key,,} in
      pubkeyacceptedalgorithms) accepted=$value ;;
      requiredrsasize) required_rsa_size=$value ;;
    esac
  done <<<"$effective"
  [[ -n $accepted && $required_rsa_size =~ ^[0-9]+$ ]] || return 1

  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*(#|$|@) ]] && continue
    read -r key_type _ <<<"$line"
    case $key_type in
      ssh-ed25519 | ssh-rsa | ecdsa-sha2-nistp256 | ecdsa-sha2-nistp384 | ecdsa-sha2-nistp521 | \
        sk-ssh-ed25519@openssh.com | sk-ecdsa-sha2-nistp256@openssh.com) ;;
      *) continue ;;
    esac
    fingerprint=$(ssh-keygen -lf /dev/stdin <<<"$line" 2>/dev/null) || continue
    bits=${fingerprint%% *}
    [[ $bits =~ ^[0-9]+$ ]] || continue
    case $key_type in
      ssh-rsa)
        (( bits >= required_rsa_size )) || continue
        [[ ,$accepted, == *",rsa-sha2-512,"* || ,$accepted, == *",rsa-sha2-256,"* ||
          ,$accepted, == *",ssh-rsa,"* ]] && return 0
        ;;
      *) [[ ,$accepted, == *",$key_type,"* ]] && return 0 ;;
    esac
  done <"$authorized_keys"
  return 1
}

monarch_sshd_configuration_is_supported() {
  local main dropin file target contents line directive rest
  local -a files

  main=$(monarch_sshd_main_config_path)
  dropin=$(monarch_sshd_dropin_dir)
  [[ -f $main && ! -L $main && -d $dropin && ! -L $dropin ]] || return 1

  files=("$main")
  for file in "$dropin"/*.conf; do
    [[ -e $file || -L $file ]] && files+=("$file")
  done

  for file in "${files[@]}"; do
    if [[ -L $file ]]; then
      target=$(realpath -e -- "$file") || return 1
      [[ -f $target && $target == /usr/lib/systemd/sshd_config.d/*.conf ]] || return 1
    else
      [[ -f $file ]] || return 1
    fi
    contents=$(as_root cat -- "$file") || return 1
    while IFS= read -r line || [[ -n $line ]]; do
      line=${line%%#*}
      read -r directive rest <<<"$line"
      case ${directive,,} in
        match) return 1 ;;
        include)
          [[ $file == "$main" && $rest == "$dropin/*.conf" ]] || return 1
          ;;
      esac
    done <<<"$contents"
  done
}

monarch_sshd_key_paths_safe() {
  local home=$1 authorized_keys=$2 user_id=$3 path owner mode

  for path in "$home" "$home/.ssh" "$authorized_keys"; do
    [[ -e $path ]] || return 1
    read -r owner mode < <(stat -Lc '%u %a' "$path") || return 1
    (( owner == 0 || owner == user_id )) || return 1
    (( (8#$mode & 8#022) == 0 )) || return 1
  done
}

monarch_sshd_context_supports_user_key() {
  local user=$1 home=$2 effective key value rest path
  local pubkey=false key_path=false methods=false revocation=true

  effective=$(as_root sshd -T -C "user=$user,host=localhost,addr=127.0.0.1") || return 1
  while read -r key value rest; do
    case ${key,,} in
      pubkeyauthentication)
        [[ ${value,,} == "yes" ]] && pubkey=true
        ;;
      authorizedkeysfile)
        for path in $value $rest; do
          case $path in
            .ssh/authorized_keys | %h/.ssh/authorized_keys | "$home/.ssh/authorized_keys")
              key_path=true
              ;;
          esac
        done
        ;;
      authenticationmethods)
        [[ ( ${value,,} == "any" || ${value,,} == "publickey" ) && -z $rest ]] && methods=true
        ;;
      revokedkeys)
        [[ ${value,,} == "none" && -z $rest ]] || revocation=false
        ;;
    esac
  done <<<"$effective"

  [[ $pubkey == "true" && $key_path == "true" && $methods == "true" && $revocation == "true" ]]
}

monarch_sshd_output_is_key_only() {
  local output=$1

  grep -qixF 'passwordauthentication no' <<<"$output" &&
    grep -qixF 'kbdinteractiveauthentication no' <<<"$output"
}

monarch_sshd_effective_hardened() {
  local user=$1 home=$2 global contextual

  global=$(as_root sshd -T) || return 1
  contextual=$(as_root sshd -T -C "user=$user,host=localhost,addr=127.0.0.1") || return 1
  monarch_sshd_output_is_key_only "$global" || return 1
  monarch_sshd_output_is_key_only "$contextual" || return 1
  monarch_sshd_context_supports_user_key "$user" "$home"
}

monarch_sshd_install_hardening() {
  local user=$1 home=$2 config config_dir expected current tmp created=false

  if ! monarch_sshd_configuration_is_supported; then
    echo "Refusing to harden an SSH configuration with conditional or custom includes." >&2
    return 1
  fi

  config=$(monarch_sshd_hardening_path)
  config_dir=${config%/*}
  expected=$(monarch_sshd_hardening_content)

  if [[ -e $config || -L $config ]]; then
    if [[ ! -f $config || -L $config ]] ||
      ! current=$(as_root cat -- "$config") || [[ $current != "$expected" ]]; then
      echo "Refusing to replace the existing SSH configuration at $config." >&2
      return 1
    fi
    as_root chown root:root "$config" || return 1
    as_root chmod 0644 "$config" || return 1
  else
    if [[ ! -d $config_dir || -L $config_dir ]]; then
      echo "The SSH configuration directory is unavailable: $config_dir" >&2
      return 1
    fi
    tmp=$(as_root mktemp "$config_dir/.10-monarch-hardening.conf.XXXXXX") || return 1
    if ! monarch_sshd_hardening_content |
      as_root install -m 0644 -o root -g root /dev/stdin "$tmp"; then
      as_root rm -f -- "$tmp" || true
      return 1
    fi
    if ! as_root mv -fT -- "$tmp" "$config"; then
      as_root rm -f -- "$tmp" || true
      return 1
    fi
    created=true
  fi

  if ! as_root sshd -t || ! monarch_sshd_effective_hardened "$user" "$home"; then
    [[ $created == "false" ]] || as_root rm -f -- "$config" || true
    echo "sshd did not accept the key-only Monarch configuration." >&2
    return 1
  fi
}
