set -euo pipefail

source "${BASH_SOURCE[0]%/*}/../helpers/root-file.sh"

monarch_reconcile_polkit_auth() {
  local system_root runtime_root trusted_uid stop test_mode file normalized line stage mode gid
  local fingerprint=0 fido=0 index=0
  local -a lines

  monarch_root_file_context system_root runtime_root trusted_uid stop test_mode || return 1
  file="$system_root/etc/pam.d/polkit-1"
  [[ -e $file || -L $file ]] || return 0
  monarch_root_file_trusted_source "$file" "$trusted_uid" "$stop" || return 1
  normalized=$(/usr/bin/awk '!/^[[:space:]]*(#|$)/ { $1=$1; print }' "$file") || return 1
  mapfile -t lines <<<"$normalized"

  while (( index < ${#lines[@]} - 4 )); do
    line=${lines[index]}
    case $line in
      'auth sufficient pam_u2f.so cue authfile=/etc/fido2/fido2')
        (( fido == 0 )) || return 0
        fido=1
        ;;
      'auth [success=1 default=ignore] pam_exec.so quiet /usr/local/bin/monarch-hw-laptop-closed')
        (( fingerprint == 0 )) || return 0
        (( index += 1 ))
        [[ ${lines[index]:-} == 'auth sufficient pam_fprintd.so' ]] || return 0
        fingerprint=1
        ;;
      'auth sufficient pam_fprintd.so')
        (( fingerprint == 0 )) || return 0
        fingerprint=1
        ;;
      *) return 0 ;;
    esac
    (( index += 1 ))
  done

  for line in auth account password session; do
    [[ ${lines[index]:-} == "$line required pam_unix.so" ]] || return 0
    (( index += 1 ))
  done
  (( index == ${#lines[@]} )) || return 0

  mode=$(/usr/bin/stat -c '%a' -- "$file") || return 1
  gid=$(/usr/bin/stat -c '%g' -- "$file") || return 1
  stage=$(/usr/bin/mktemp -- "${file%/*}/.polkit-1.monarch.XXXXXX") || return 1
  if monarch_root_file_run "$test_mode" /usr/bin/install -m "$mode" -o root -g "$gid" -T -- "$file" "$stage" &&
    /usr/bin/sed -Ei 's/^([[:space:]]*(auth|account|password|session))[[:space:]]+required[[:space:]]+pam_unix\.so[[:space:]]*$/\1 include system-auth/' "$stage" &&
    /usr/bin/mv -Tf -- "$stage" "$file"; then
    echo "Restored the system authentication policy for polkit."
    return 0
  fi
  /usr/bin/rm -f -- "$stage"
  return 1
}

monarch_reconcile_polkit_auth
