#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"
source "$ROOT/install/reconcile/config-files.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
source_tree="$test_tmp/source"
target_tree="$test_tmp/target"
mkdir -p "$source_tree/nested"
printf 'first\n' >"$source_tree/nested/entry"
chmod 0755 "$source_tree/nested/entry"
ln -s missing "$source_tree/link"
monarch_reconcile_managed_tree "$source_tree" "$target_tree"
tree_inode=$(stat -c %i "$target_tree")
file_inode=$(stat -c %i "$target_tree/nested/entry")
touch -d '2000-01-01' "$target_tree/nested/entry"
monarch_reconcile_managed_tree "$source_tree" "$target_tree"
[[ $(stat -c %i "$target_tree") == "$tree_inode" ]] || fail "unchanged managed trees are not replaced"
[[ $(stat -c %i "$target_tree/nested/entry") == "$file_inode" ]] || fail "unchanged managed files are not recopied"
pass "unchanged content, modes and links keep their inodes regardless of mtime"

printf 'other\n' >"$target_tree/nested/entry"
touch -r "$source_tree/nested/entry" "$target_tree/nested/entry"
monarch_reconcile_managed_tree "$source_tree" "$target_tree"
cmp "$source_tree/nested/entry" "$target_tree/nested/entry"
chmod 0644 "$target_tree/nested/entry"
monarch_reconcile_managed_tree "$source_tree" "$target_tree"
[[ $(stat -c %a "$target_tree/nested/entry") == 755 ]]
chmod 0700 "$target_tree/nested"
monarch_reconcile_managed_tree "$source_tree" "$target_tree"
[[ $(stat -c %a "$target_tree/nested") == "$(stat -c %a "$source_tree/nested")" ]]
printf 'obsolete\n' >"$target_tree/obsolete"
monarch_reconcile_managed_tree "$source_tree" "$target_tree"
[[ ! -e $target_tree/obsolete ]]
pass "same-size content changes, executable bits, directory modes and obsolete files converge"

ln -sfn different "$target_tree/link"
monarch_reconcile_managed_tree "$source_tree" "$target_tree"
[[ $(readlink "$target_tree/link") == missing ]]
rm "$target_tree/link"
printf 'not-a-link\n' >"$target_tree/link"
monarch_reconcile_managed_tree "$source_tree" "$target_tree"
[[ -L $target_tree/link ]]
mv "$target_tree" "$test_tmp/external"
ln -s "$test_tmp/external" "$target_tree"
monarch_reconcile_managed_tree "$source_tree" "$target_tree"
[[ ! -L $target_tree && -d $target_tree && -d $test_tmp/external ]]
pass "symlink targets, entry types and the managed root converge without changing external trees"

mkdir -p "$test_tmp/bin"
cat >"$test_tmp/bin/cp" <<'EOF'
#!/bin/bash
exit 42
EOF
chmod +x "$test_tmp/bin/cp"
printf 'keep-on-failure\n' >"$target_tree/obsolete"
if PATH="$test_tmp/bin:/usr/bin" monarch_reconcile_managed_tree "$source_tree" "$target_tree"; then
  fail "failed staging reports failure"
fi
[[ $(<"$target_tree/obsolete") == keep-on-failure ]]

cat >"$test_tmp/bin/mv" <<'EOF'
#!/bin/bash
[[ $1 != */.target.new.* ]] || exit 42
exec /usr/bin/mv "$@"
EOF
chmod +x "$test_tmp/bin/mv"
rm "$test_tmp/bin/cp"
if PATH="$test_tmp/bin:/usr/bin" monarch_reconcile_managed_tree "$source_tree" "$target_tree"; then
  fail "failed publication reports failure"
fi
[[ $(<"$target_tree/obsolete") == keep-on-failure ]]
pass "staging and publication failures retain the previous tree"
