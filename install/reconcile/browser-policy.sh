MONARCH_PATH="$1"
source "$MONARCH_PATH/install/helpers/browser-policy.sh"

for dir in "${BROWSER_POLICY_MANAGED_DIRS[@]}"; do
  [[ -e $dir || -L $dir ]] || continue
  browser_policy_setup_dir "$dir"
done

for dir in "${BROWSER_POLICY_FIREFOX_DIRS[@]}"; do
  [[ -e $dir || -L $dir ]] || continue
  if browser_policy_firefox_hardened "$dir"; then
    browser_policy_purge_untrusted "$dir"
  else
    browser_policy_setup_firefox "$dir"
  fi
done
