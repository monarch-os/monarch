#!/bin/bash

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
runtime="$test_tmp/runtime"
mkdir -p "$home/.local/share/monarch-v4/.git" "$home/.local/state/monarch" "$runtime/bin" "$test_tmp/bin"
touch "$runtime/bin/monarch"
chmod +x "$runtime/bin/monarch"

cat >"$test_tmp/bin/gum" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >"$TEST_GUM_LOG"
[[ ${TEST_CONFIRM:-false} == "true" ]]
EOF
chmod +x "$test_tmp/bin/gum"
export TEST_GUM_LOG="$test_tmp/gum.log"

printf '%s\n' 1 >"$home/.local/state/monarch/schema"
if HOME="$home" MONARCH_RUNTIME_ROOT="$runtime" PATH="$test_tmp/bin:/usr/bin" \
  bash "$ROOT/bin/monarch-remove-legacy-runtime" >/dev/null 2>&1; then
  fail "legacy runtime cleanup accepted an incomplete reconciliation"
fi
[[ -d $home/.local/share/monarch-v4 ]] || fail "refused cleanup removed the archive"

printf '%s\n' 2 >"$home/.local/state/monarch/schema"
HOME="$home" MONARCH_RUNTIME_ROOT="$runtime" PATH="$test_tmp/bin:/usr/bin" \
  bash "$ROOT/bin/monarch-remove-legacy-runtime"
[[ -d $home/.local/share/monarch-v4 ]] || fail "cancelled cleanup removed the archive"
grep -qF -- '--default=false' "$TEST_GUM_LOG" || fail "destructive cleanup defaults to confirmation"

printf '%s\n' 3 >"$home/.local/state/monarch/schema"
HOME="$home" MONARCH_RUNTIME_ROOT="$runtime" PATH="$test_tmp/bin:/usr/bin" \
  bash "$ROOT/bin/monarch-remove-legacy-runtime"
[[ -d $home/.local/share/monarch-v4 ]] || fail "future reconciliation schema rejected the archive"

TEST_CONFIRM=true HOME="$home" MONARCH_RUNTIME_ROOT="$runtime" PATH="$test_tmp/bin:/usr/bin" \
  bash "$ROOT/bin/monarch-remove-legacy-runtime"
[[ ! -e $home/.local/share/monarch-v4 ]] || fail "confirmed cleanup kept the archive"

mkdir -p "$home/.local/share/monarch-v4/user-config/noctalia"
TEST_CONFIRM=true HOME="$home" MONARCH_RUNTIME_ROOT="$runtime" PATH="$test_tmp/bin:/usr/bin" \
  bash "$ROOT/bin/monarch-remove-legacy-runtime"
[[ ! -e $home/.local/share/monarch-v4 ]] || fail "confirmed cleanup kept an archived V4 configuration"

pass "legacy runtime cleanup is explicit and guarded"
