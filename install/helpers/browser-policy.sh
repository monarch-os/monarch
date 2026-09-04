source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/as-root.sh"

BROWSER_POLICY_MANAGED_DIRS=(
  /etc/chromium/policies/managed
  /etc/opt/chrome/policies/managed
  /etc/opt/edge/policies/managed
  /etc/brave/policies/managed
)

BROWSER_POLICY_PARENT_DIRS=(
  /etc/chromium
  /etc/chromium/policies
  /etc/opt/chrome
  /etc/opt/chrome/policies
  /etc/opt/edge
  /etc/opt/edge/policies
  /etc/brave
  /etc/brave/policies
)

BROWSER_POLICY_FIREFOX_DIRS=(
  /usr/lib/firefox/distribution
  /opt/zen-browser/distribution
)

browser_policy_setup_parent() {
  local dir="$1"

  if [[ -L $dir || ( -e $dir && ! -d $dir ) ]]; then
    as_root rm -rf -- "$dir"
  fi
  as_root install -d -m 0755 -o root -g root "$dir"
}

browser_policy_setup_parents_for() {
  local dir="$1" parent

  for parent in "${BROWSER_POLICY_PARENT_DIRS[@]}"; do
    [[ $dir == "$parent"/* ]] || continue
    browser_policy_setup_parent "$parent"
  done
}

browser_policy_purge_untrusted() (
  local dir="$1"
  local entry

  shopt -s dotglob nullglob
  for entry in "$dir"/*; do
    browser_policy_file_trusted "$entry" || as_root rm -rf -- "$entry"
  done
)

browser_policy_setup_dir() {
  local dir="$1"

  browser_policy_setup_parents_for "$dir"
  browser_policy_setup_parent "$dir"
  browser_policy_purge_untrusted "$dir"
}

browser_policy_file_trusted() {
  local file="$1" mode

  [[ -f $file && ! -L $file ]] || return 1
  [[ $(stat -c '%U' "$file") == "root" ]] || return 1
  mode=$(stat -c '%a' "$file")
  (( (8#${mode: -2:1} & 2) == 0 && (8#${mode: -1} & 2) == 0 ))
}

browser_policy_firefox_hardened() {
  local dir="$1"

  [[ -d $dir && ! -L $dir ]] || return 1
  [[ $(stat -c '%U' "$dir") == "root" ]] || return 1
  [[ $(stat -c '%a' "$dir") == "755" ]] || return 1
  browser_policy_file_trusted "$dir/policies.json"
}

browser_policy_setup_firefox() {
  local dir="$1"
  local policies="${2:-${MONARCH_PATH:-/usr/share/monarch}/default/firefox/policies.json}"

  browser_policy_setup_parent "$dir"
  browser_policy_purge_untrusted "$dir"
  as_root install -m 0644 -o root -g root -T "$policies" "$dir/policies.json"
}
