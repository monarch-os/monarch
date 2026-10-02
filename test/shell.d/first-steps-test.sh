#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
runtime="$test_tmp/runtime"
mkdir -p "$runtime/bin" "$runtime/install/reconcile"
cp "$ROOT/bin/monarch-setup-first-steps" "$runtime/bin/"
cp "$ROOT/install/reconcile/noctalia-wait.sh" "$runtime/install/reconcile/"
export MONARCH_PATH="$runtime" TEST_FIRST_STEPS="$test_tmp" PATH="$runtime/bin:$PATH"

cat >"$runtime/bin/noctalia" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_FIRST_STEPS/calls"
if [[ $* == 'msg status' ]]; then
  case ${TEST_FIRST_STEPS_MODE:-ready} in
    unavailable) exit 1 ;;
    locked) printf '%s\n' '{"locked":true,"panelOpen":false}' ;;
    busy) printf '%s\n' '{"locked":false,"panelOpen":true}' ;;
    manual)
      monarch-setup-first-steps opened
      printf '%s\n' '{"locked":false,"panelOpen":false}'
      ;;
    *) printf '%s\n' '{"locked":false,"panelOpen":false}' ;;
  esac
elif [[ $1 == "msg" && $2 == "panel-open" ]]; then
  [[ ${TEST_FIRST_STEPS_MODE:-} != rejected ]] || exit 42
  printf '%s\n' "$4" >"$TEST_FIRST_STEPS/context"
  [[ ${TEST_FIRST_STEPS_MODE:-} != unconfirmed ]] || exit 0
  monarch-setup-first-steps opened
fi
EOF
printf '#!/bin/bash\nexit 0\n' >"$runtime/bin/sleep"
cat >"$runtime/bin/monarch-pkg-present" <<'EOF'
#!/bin/bash
[[ -f $TEST_FIRST_STEPS/installed ]]
EOF
cat >"$runtime/bin/monarch-pkg-aur-add" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >"$TEST_FIRST_STEPS/installer-args"
touch "$TEST_FIRST_STEPS/installer-started"
while [[ -f $TEST_FIRST_STEPS/block-install ]]; do /usr/bin/sleep 0.02; done
[[ ${TEST_FIRST_STEPS_EXIT:-0} == 0 ]] || exit "$TEST_FIRST_STEPS_EXIT"
touch "$TEST_FIRST_STEPS/installed"
EOF
cat >"$runtime/bin/monarch-launch-floating-terminal-with-presentation" <<'EOF'
#!/bin/bash
exec bash -c "$*"
EOF
chmod +x "$runtime/bin/"*

fresh_state() {
  export XDG_STATE_HOME="$test_tmp/state-$1"
  state_dir="$XDG_STATE_HOME/monarch/first-steps"
  : >"$test_tmp/calls"
  unset TEST_FIRST_STEPS_MODE
}

fresh_state existing
monarch-setup-first-steps first-login
[[ ! -s $test_tmp/calls ]] || fail "existing users are not offered first steps automatically"
pass "existing users keep manual access without an automatic offer"

fresh_state fresh
monarch-setup-first-steps prepare
[[ -f $state_dir/pending ]] || fail "initial setup arms first steps"
monarch-setup-first-steps first-login
[[ -f $state_dir/shown && ! -e $state_dir/pending ]] || fail "the panel confirms its first opening"
grep -q '^msg panel-open monarch/first-steps:panel ' "$test_tmp/calls"
jq -e --arg root "$runtime" --arg home "$XDG_STATE_HOME" \
  '.root == $root and .stateHome == $home and .phase == "welcome"' "$test_tmp/context" >/dev/null
cp "$test_tmp/calls" "$test_tmp/expected-calls"
monarch-setup-first-steps first-login
monarch-setup-first-steps prepare
cmp "$test_tmp/calls" "$test_tmp/expected-calls"
[[ ! -e $state_dir/pending ]] || fail "refreshing setup does not rearm an offered guide"
pass "the first session opens the guide exactly once and retains its user state"

monarch-setup-first-steps record appearance
monarch-setup-first-steps open
jq -e '.phase == "appearance"' "$test_tmp/context" >/dev/null
monarch-setup-first-steps reset
jq -e '.phase == "welcome"' "$test_tmp/context" >/dev/null
[[ -f $state_dir/shown && ! -e $state_dir/pending ]] || fail "manual replay does not rearm startup"
pass "manual access resumes progress and replay preserves the already-shown marker"

for mode in unavailable locked busy rejected unconfirmed; do
  fresh_state "$mode"
  monarch-setup-first-steps prepare
  export TEST_FIRST_STEPS_MODE="$mode"
  if monarch-setup-first-steps first-login >/dev/null 2>&1; then fail "$mode cannot consume the first offer"; fi
  [[ -f $state_dir/pending && ! -e $state_dir/shown ]] || fail "$mode remains pending"
  unset TEST_FIRST_STEPS_MODE
  monarch-setup-first-steps first-login
  [[ -f $state_dir/shown && ! -e $state_dir/pending ]] || fail "$mode retries when the desktop is ready"
  pass "$mode keeps the guide pending until a confirmed opening"
done

fresh_state concurrent
monarch-setup-first-steps prepare
exec 8>"$state_dir/offer.lock"
flock -n 8
monarch-setup-first-steps first-login
[[ ! -s $test_tmp/calls && -f $state_dir/pending ]] || fail "a concurrent first-login offer is excluded"
flock -u 8
exec 8>&-
monarch-setup-first-steps first-login
pass "concurrent first-login attempts cannot open duplicate guides"

fresh_state manual-race
monarch-setup-first-steps prepare
export TEST_FIRST_STEPS_MODE=manual
monarch-setup-first-steps first-login
[[ -f $state_dir/shown && ! -f $state_dir/pending ]] || fail "manual opening consumes the first offer"
if grep -q '^msg panel-open ' "$test_tmp/calls"; then fail "manual opening cancels a waiting automatic offer"; fi
unset TEST_FIRST_STEPS_MODE
pass "manual opening cancels a waiting automatic offer"

fresh_state installer
: >"$test_tmp/block-install"
monarch-setup-first-steps install-tool seclists
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ ! -e $test_tmp/installer-started ]] || break
  /usr/bin/sleep 0.02
done
[[ -f $test_tmp/installer-started ]] || fail "installation starts in the presentation terminal"
if monarch-setup-first-steps install-tool seclists >/dev/null 2>&1; then fail "duplicate installation is excluded"; fi
monarch-setup-first-steps tools-state | jq -e '.active == "seclists"' >/dev/null
rm "$test_tmp/block-install"
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ -d $state_dir/installing ]] || break
  /usr/bin/sleep 0.02
done
monarch-setup-first-steps tools-state | jq -e '.installed.seclists and .active == "" and .lastResult.code == 0' >/dev/null
[[ $(<"$test_tmp/installer-args") == seclists ]] || fail "the existing wordlist installer receives its package"
pass "installation state is stored outside the runtime and excludes duplicate jobs"

rm "$test_tmp/installed" "$test_tmp/installer-started"
export TEST_FIRST_STEPS_EXIT=42
monarch-setup-first-steps install-tool seclists
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ -d $state_dir/installing ]] || break
  /usr/bin/sleep 0.02
done
monarch-setup-first-steps tools-state | jq -e '.active == "" and .lastResult.code == 42' >/dev/null
if monarch-setup-first-steps install-tool unknown >/dev/null 2>&1; then fail "unknown tools cannot launch installers"; fi
pass "failed installations release their slot and unknown tools are rejected"
