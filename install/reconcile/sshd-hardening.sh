set -euo pipefail

source "$MONARCH_PATH/install/helpers/sshd-hardening.sh"

config=$(monarch_sshd_hardening_path)
authorized_keys="$HOME/.ssh/authorized_keys"
user=$(id -un)
user_id=$(id -u)

sole_login_user() {
  local entries name password uid group gecos home shell global sources source
  local found=false

  sources=$(awk '$1 == "passwd:" { for (i = 2; i <= NF; i++) print $i }' /etc/nsswitch.conf) || return 1
  [[ -n $sources ]] || return 1
  while read -r source; do
    case $source in
      files | systemd) ;;
      *) return 1 ;;
    esac
  done <<<"$sources"

  entries=$(getent passwd) || return 1
  while IFS=: read -r name password uid group gecos home shell; do
    case $shell in
      */false | */nologin) continue ;;
    esac
    [[ $name != "root" ]] || continue
    [[ $name == "$user" ]] || return 1
    found=true
  done <<<"$entries"
  [[ $found == "true" ]] || return 1

  global=$(as_root sshd -T) || return 1
  grep -Eiq '^permitrootlogin (no|prohibit-password|without-password|forced-commands-only)$' <<<"$global"
}

if ! systemctl is-enabled --quiet sshd.service 2>/dev/null &&
  ! systemctl is-active --quiet sshd.service 2>/dev/null; then
  exit 0
fi

if [[ ! -e $config && ! -L $config ]]; then
  if monarch-cmd-missing ufw ||
    ! sudo env LC_ALL=C ufw status 2>/dev/null | grep -Fq 'monarch-sshd'; then
    exit 0
  fi
fi

if ! monarch_sshd_configuration_is_supported; then
  echo "SSH password authentication remains enabled: conditional or custom SSH configuration needs manual review."
  exit 0
fi

monarch_sshd_effective_hardened "$user" "$HOME" && exit 0

if ! sole_login_user; then
  echo "SSH password authentication remains enabled: other login identities may depend on password authentication."
  echo "Run monarch setup security sshd after reviewing access for every administrator."
  exit 0
fi

if ! monarch_sshd_has_usable_key "$authorized_keys" "$user"; then
  echo "SSH password authentication remains enabled: $authorized_keys has no usable public key."
  echo "Run monarch setup security sshd to authorize a key and harden the server."
  exit 0
fi

home_mode=$(stat -Lc '%a' "$HOME" 2>/dev/null) || {
  echo "SSH password authentication remains enabled: could not inspect $HOME."
  exit 0
}
if (( 8#$home_mode & 8#022 )); then
  echo "SSH password authentication remains enabled: $HOME is group- or world-writable."
  exit 0
fi

if ! chmod 700 "$HOME/.ssh" || ! chmod 600 "$authorized_keys" ||
  ! monarch_sshd_key_paths_safe "$HOME" "$authorized_keys" "$user_id" ||
  ! monarch_sshd_context_supports_user_key "$user" "$HOME"; then
  echo "SSH password authentication remains enabled: the authorized key path is not usable by sshd."
  exit 0
fi

echo "Disabling SSH password authentication on the existing Monarch SSH server..."
if ! monarch_sshd_install_hardening "$user" "$HOME"; then
  echo "SSH password authentication remains enabled; repair sshd and rerun monarch update."
  exit 0
fi

if systemctl is-active --quiet sshd.service 2>/dev/null &&
  ! sudo systemctl reload sshd.service; then
  echo "The key-only SSH policy is installed but sshd could not reload it."
fi
