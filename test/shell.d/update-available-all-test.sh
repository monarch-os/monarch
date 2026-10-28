#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export PATH="$test_tmp/bin:$ROOT/bin:$PATH" TMPDIR="$test_tmp"
export MONARCH_PATH="$ROOT"
export CHECK_TEST="$test_tmp"
: > "$test_tmp/repositories"
: > "$test_tmp/aur"

cat > "$test_tmp/bin/monarch-cmd-missing" <<'EOF'
#!/bin/bash
[[ $* == "${CHECK_MISSING:-}" ]]
EOF
cat > "$test_tmp/bin/checkupdates" <<'EOF'
#!/bin/bash
[[ $* == '--nocolor' && $LC_ALL == C && -d $CHECKUPDATES_DB ]] || exit 99
printf '%s\n' "$CHECKUPDATES_DB" > "$CHECK_TEST/database"
cat "$CHECK_TEST/repositories"
exit "${CHECK_REPO_CODE:-0}"
EOF
cat > "$test_tmp/bin/pacman" <<'EOF'
#!/bin/bash
[[ $1 == --dbpath && $2 == "$(<"$CHECK_TEST/database")" && $3 == -Qqm ]] || exit 99
touch "$CHECK_TEST/pacman-called"
[[ ${CHECK_FOREIGN_ERROR:-0} == 0 ]] || { echo 'database failed' >&2; exit 1; }
[[ -n ${CHECK_FOREIGN:-} ]] || exit 1
printf '%s\n' "$CHECK_FOREIGN"
EOF
cat > "$test_tmp/bin/yay" <<'EOF'
#!/bin/bash
[[ $* == "--dbpath $(<"$CHECK_TEST/database") -Qua --color never --ignore gcc14,gcc14-libs" && $LC_ALL == C ]] || exit 99
touch "$CHECK_TEST/aur-called"
[[ -z ${CHECK_AUR_ERROR:-} ]] || printf '%s\n' "$CHECK_AUR_ERROR" >&2
cat "$CHECK_TEST/aur"
exit "${CHECK_AUR_CODE:-0}"
EOF
cat > "$test_tmp/bin/sudo" <<'EOF'
#!/bin/bash
touch "$CHECK_TEST/sudo-called"
exit 99
EOF
chmod +x "$test_tmp/bin/"*

run_check() {
  code=0
  (( $# > 0 )) || set -- --all --json
  bash "$ROOT/bin/monarch-update-available" "$@" > "$test_tmp/result" || code=$?
  if [[ -f $test_tmp/database ]]; then
    [[ ! -e $(<"$test_tmp/database") ]] || fail "temporary package databases are removed"
  fi
  [[ ! -f $test_tmp/sudo-called ]] || fail "checking updates never elevates privileges"
}

printf 'monarch 1 -> 2\nlinux-cachyos 6.1 -> 6.2\n' > "$test_tmp/repositories"
run_check
(( code == 0 )) || fail "repository check succeeds"
jq -e '.status == "available" and .count == 2 and .repositories == 2 and .aur == 0' "$test_tmp/result" >/dev/null
jq -e '.scope == "all" and .counts == {monarch:1,repo:1,aur:0} and
  .packages == [{name:"monarch",category:"monarch",installed:"1",available:"2"},
               {name:"linux-cachyos",category:"repo",installed:"6.1",available:"6.2"}]' "$test_tmp/result" >/dev/null
[[ ! -f $test_tmp/aur-called ]] || fail "no AUR request is made without foreign packages"
pass "all repository upgrades are counted using an isolated database without sudo"

export CHECK_FOREIGN=example-aur
printf 'example-aur 3 -> 4\n' > "$test_tmp/aur"
run_check
jq -e '.status == "available" and .count == 3 and .repositories == 2 and .aur == 1' "$test_tmp/result" >/dev/null
jq -e '.counts == {monarch:1,repo:1,aur:1} and .packages[2] ==
  {name:"example-aur",category:"aur",installed:"3",available:"4"}' "$test_tmp/result" >/dev/null
[[ -f $test_tmp/aur-called ]] || fail "foreign packages trigger the AUR check"
pass "AUR and repository upgrades are combined using the same isolated database"

# Formats emitted by yay 13's FormatAgeTag/FormatDuration, including a future
# LastModified timestamp. The badge must not leak into the available version.
for age in '[0m]' '[45m]' '[1h]' '[23h59m]' '[1d]' '[2d3h]' '[38d8h]' '[-3m]'; do
  printf 'example-aur 3 -> 4 %s\n' "$age" > "$test_tmp/aur"
  run_check
  (( code == 0 )) || fail "yay age tag $age blocks available updates"
  jq -e '.status == "available" and .count == 3 and .aur == 1 and .packages[2] ==
    {name:"example-aur",category:"aur",installed:"3",available:"4"}' "$test_tmp/result" >/dev/null
done
printf 'example-aur 3 -> 4\n' > "$test_tmp/aur"
pass "yay 13 age tags preserve AUR counts and clean version fields"

export CHECK_AUR_ERROR='AUR unavailable'
for CHECK_AUR_CODE in 1 124 127; do
  export CHECK_AUR_CODE
  run_check
  (( code == 0 )) || fail "an AUR outage blocks known repository upgrades"
  jq -e '.status == "available" and .count == 2 and .repositories == 2 and
    .complete == false and .aur == null and .counts.aur == null and
    .warnings == [{source:"aur",reason:"aur-unavailable"}] and
    (.packages | length) == 2 and ([.packages[].category] | index("aur")) == null' "$test_tmp/result" >/dev/null
done
unset CHECK_AUR_ERROR
export CHECK_AUR_CODE=0 CHECK_MISSING=yay
run_check
(( code == 0 )) || fail "missing yay blocks repository upgrades"
jq -e '.count == 2 and .warnings[0].reason == "missing-aur-helper"' "$test_tmp/result" >/dev/null
unset CHECK_MISSING
printf 'example-aur 3 -> 4 [2d3h]\nbroken AUR output\n' > "$test_tmp/aur"
run_check
(( code == 0 )) || fail "malformed AUR output blocks repository upgrades"
jq -e '.count == 2 and .aur == null and .warnings[0].reason == "invalid-aur-result" and
  (.packages | length) == 2' "$test_tmp/result" >/dev/null
printf 'example-aur 3 -> 4\n' > "$test_tmp/aur"
pass "AUR failures preserve repository upgrades and discard all unverified AUR rows"

rm "$test_tmp/pacman-called" "$test_tmp/aur-called"
run_check --json
(( code == 0 )) || fail "JSON-only keeps the Monarch-only scope"
jq -e '.scope == "monarch" and .count == 1 and .packages[0].name == "monarch"' "$test_tmp/result" >/dev/null
[[ ! -e $test_tmp/pacman-called && ! -e $test_tmp/aur-called ]] || fail "JSON-only queries the AUR"
printf 'monarch-keyring 1 -> 2\nlinux-cachyos 6.1 -> 6.2\n' > "$test_tmp/repositories"
run_check --json
(( code == 1 )) || fail "similarly named packages do not change the Monarch-only scope"
jq -e '.status == "current" and .count == 0 and .packages == []' "$test_tmp/result" >/dev/null
run_check --json --all
(( code == 0 )) || fail "option order does not change the combined scope"
jq -e '.count == 3 and .counts == {monarch:0,repo:2,aur:1} and .packages[0].name == "monarch-keyring"' "$test_tmp/result" >/dev/null
run_check --all
(( code == 0 )) || fail "all-package text mode reports available upgrades"
grep -q '3' "$test_tmp/result" || fail "text output includes the update count"
pass "JSON changes only the format; all expands the scope and categories carry versions"

: > "$test_tmp/repositories"
export CHECK_REPO_CODE=2
run_check
jq -e '.status == "available" and .count == 1 and .repositories == 0 and .aur == 1' "$test_tmp/result" >/dev/null
pass "AUR-only updates are offered even with no repository upgrades"

: > "$test_tmp/aur"
export CHECK_AUR_CODE=1
run_check
(( code == 1 )) || fail "a confirmed empty update list returns the no-updates status"
jq -e '.status == "current" and .count == 0' "$test_tmp/result" >/dev/null
pass "up-to-date is reported only after both checks succeed"

for CHECK_REPO_CODE in 1 124 127; do
  export CHECK_REPO_CODE
  run_check
  (( code == 2 )) || fail "repository failure or timeout must fail"
  jq -e '.status == "error" and .count == null' "$test_tmp/result" >/dev/null
done
pass "repository errors and timeouts never claim that the system is current"

export CHECK_REPO_CODE=2 CHECK_AUR_ERROR='AUR unavailable'
run_check
(( code == 2 )) || fail "an AUR error must not look like an empty update list"
jq -e '.reason == "aur-unavailable"' "$test_tmp/result" >/dev/null
jq -e '.status == "error" and .count == null and .repositories == 0 and .aur == null and
  .complete == false and .warnings[0].source == "aur"' "$test_tmp/result" >/dev/null
unset CHECK_AUR_ERROR
export CHECK_AUR_CODE=124
run_check
(( code == 2 )) || fail "an AUR timeout must fail"
pass "AUR failures and timeouts cannot produce a false up-to-date result"

export CHECK_AUR_CODE=0 CHECK_REPO_CODE=0
printf 'broken repository output\n' > "$test_tmp/repositories"
run_check
(( code == 2 )) || fail "malformed repository output must fail"
jq -e '.reason == "invalid-repository-result"' "$test_tmp/result" >/dev/null
: > "$test_tmp/repositories"
printf 'example-aur 3 ->\n' > "$test_tmp/aur"
run_check
(( code == 2 )) || fail "malformed AUR output must fail"
jq -e '.reason == "invalid-aur-result"' "$test_tmp/result" >/dev/null
pass "malformed package results cannot become update counts"

for extra in 'unexpected' '[]' '[unknown]' '[2d 3h]' '[2d3h] unexpected' '[2d3h] [4h]'; do
  printf 'example-aur 3 -> 4 %s\n' "$extra" > "$test_tmp/aur"
  run_check
  (( code == 2 )) || fail "unexpected AUR suffix $extra is accepted"
  jq -e '.reason == "invalid-aur-result"' "$test_tmp/result" >/dev/null
done
printf 'linux-cachyos 6.1 -> 6.2 [2d3h]\n' > "$test_tmp/repositories"
: > "$test_tmp/aur"
run_check
(( code == 2 )) || fail "repository rows unexpectedly accept AUR age tags"
jq -e '.reason == "invalid-repository-result"' "$test_tmp/result" >/dev/null
: > "$test_tmp/repositories"
pass "only the documented AUR suffix is accepted; unrelated extra fields still fail"

export CHECK_FOREIGN_ERROR=1
run_check
(( code == 2 )) || fail "local package query failure must fail"
jq -e '.reason == "installed-packages-unavailable"' "$test_tmp/result" >/dev/null
unset CHECK_FOREIGN_ERROR
export CHECK_MISSING=yay
run_check
(( code == 2 )) || fail "missing AUR helper must fail when foreign packages exist"
jq -e '.reason == "missing-aur-helper"' "$test_tmp/result" >/dev/null
export CHECK_MISSING='checkupdates fakeroot'
run_check
(( code == 2 )) || fail "missing check dependencies must fail"
jq -e '.reason == "missing-dependencies"' "$test_tmp/result" >/dev/null
pass "missing dependencies and local database errors are explicit failures"

rm "$test_tmp/database"
run_check --invalid
(( code == 2 )) || fail "invalid options are rejected"
[[ ! -e $test_tmp/database ]] || fail "invalid arguments query repositories"
run_check --help
(( code == 0 )) || fail "help succeeds without check dependencies"
[[ ! -e $test_tmp/database ]] || fail "help queries repositories"
pass "help and invalid options do not start network checks"
