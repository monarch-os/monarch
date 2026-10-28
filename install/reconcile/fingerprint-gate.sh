set -euo pipefail
export PATH=/usr/bin:/usr/sbin

source "${BASH_SOURCE[0]%/*}/../helpers/root-file.sh"

monarch_reconcile_fingerprint_gate() {
  local system_root runtime_root trusted_uid stop test_mode packaged resolved pam stage mode gid legacy action
  local old='auth      [success=1 default=ignore] pam_exec.so quiet /usr/local/bin/monarch-hw-laptop-closed'
  local current='auth      [success=1 default=ignore] pam_exec.so quiet /usr/bin/monarch-hw-laptop-closed'

  monarch_root_file_context system_root runtime_root trusted_uid stop test_mode || return 1
  packaged="$system_root/usr/bin/monarch-hw-laptop-closed"
  monarch_root_file_trusted_directory "${packaged%/*}" "$trusted_uid" "$stop" || return 1
  resolved=$(/usr/bin/realpath -e -- "$packaged") || return 1
  monarch_root_file_trusted_source "$resolved" "$trusted_uid" "$stop" || return 1
  [[ -x $resolved ]] || return 1

  for pam in "$system_root/etc/pam.d/sudo" "$system_root/etc/pam.d/polkit-1"; do
    [[ -e $pam || -L $pam ]] || continue
    monarch_root_file_trusted_source "$pam" "$trusted_uid" "$stop" || return 1
    action=replace
    if ! /usr/bin/grep -qxF "$old" "$pam"; then
      /usr/bin/grep -q 'monarch-hw-laptop-closed' "$pam" && continue
      /usr/bin/grep -Eq '^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_fprintd\.so[[:space:]]*$' "$pam" || continue
      action=insert
    fi
    mode=$(/usr/bin/stat -c '%a' -- "$pam") || return 1
    gid=$(/usr/bin/stat -c '%g' -- "$pam") || return 1
    stage=$(/usr/bin/mktemp -- "${pam%/*}/.fingerprint-gate.XXXXXX") || return 1
    if monarch_root_file_run "$test_mode" /usr/bin/install -m "$mode" -o root -g "$gid" -T -- "$pam" "$stage" &&
      /usr/bin/awk -v old="$old" -v current="$current" -v action="$action" '
        action == "replace" && $0 == old { print current; next }
        action == "insert" && /^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_fprintd\.so[[:space:]]*$/ { print current }
        { print }
      ' "$pam" >"$stage" &&
      /usr/bin/grep -qxF "$current" "$stage" &&
      /usr/bin/mv -Tf -- "$stage" "$pam"; then
      :
    else
      /usr/bin/rm -f -- "$stage"
      return 1
    fi
  done

  # Unknown stacks or administrator helper changes retain their legacy file.
  for pam in "$system_root"/etc/pam.d/*; do
    [[ -f $pam && ! -L $pam ]] || return 0
    if /usr/bin/grep -qF '/usr/local/bin/monarch-hw-laptop-closed' "$pam"; then
      return 0
    else
      local status=$?
      (( status == 1 )) || return 1
    fi
  done
  legacy="$system_root/usr/local/bin/monarch-hw-laptop-closed"
  [[ -e $legacy || -L $legacy ]] || return 0
  monarch_root_file_trusted_source "$legacy" "$trusted_uid" "$stop" || return 1
  /usr/bin/cmp -s -- "$resolved" "$legacy" || return 0
  /usr/bin/rm -f -- "$legacy"
}

monarch_reconcile_fingerprint_gate
