#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/runtime"

cat >"$test_tmp/bin/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF

cat >"$test_tmp/bin/niri" <<'EOF'
#!/bin/bash
case "$*" in
  'msg --json focused-output')
    printf '%s\n' '{"name":"eDP-1","current_mode":0,"modes":[{"width":1920,"height":1080}]}'
    ;;
  'msg --json outputs')
    printf '%s\n' '{"eDP-1":{"name":"eDP-1","logical":{"x":0,"y":0,"width":1920,"height":1080}}}'
    ;;
  'msg --json workspaces') printf '%s\n' '[{"id":1,"is_focused":true}]' ;;
  'msg --json windows') printf '%s\n' '[]' ;;
esac
EOF

cat >"$test_tmp/bin/slurp" <<'EOF'
#!/bin/bash
cat >/dev/null
touch "$PORTAL_RECORDING_CASE/picker"
printf '%s\n' '0,0 1920x1080'
EOF

cat >"$test_tmp/bin/hyprpicker" <<'EOF'
#!/bin/bash
sleep 1
EOF

cat >"$test_tmp/bin/gpu-screen-recorder" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >>"$PORTAL_RECORDING_CASE/arguments"
printf '%s\n' launch >>"$PORTAL_RECORDING_CASE/launches"
exit 1
EOF

chmod +x "$test_tmp/bin/"*

run_capture() {
  local name=$1 portal=$2
  shift 2
  local case_dir="$test_tmp/$name"
  mkdir -p "$case_dir"
  local status=0
  local capture_env=(env -u MONARCH_SCREENRECORD_USE_PORTAL
    PORTAL_RECORDING_CASE="$case_dir" PATH="$test_tmp/bin:/usr/bin"
    XDG_RUNTIME_DIR="$test_tmp/runtime" MONARCH_SCREENRECORD_DIR="$case_dir"
    MONARCH_SCREENRECORD_DEBUG=false)
  [[ $portal == unset ]] || capture_env+=(MONARCH_SCREENRECORD_USE_PORTAL="$portal")
  "${capture_env[@]}" "$ROOT/bin/monarch-capture-screenrecording" "$@" >"$case_dir/output" 2>&1 || status=$?
  [[ -f $case_dir/arguments ]] || fail "$name launches the recorder"
  local target
  target=$(sed -n '2p' "$case_dir/arguments")
  if [[ $portal == false ]]; then
    [[ $target == eDP-1 ]] || fail "$name honors the explicit direct capture override"
    if [[ $name == direct ]]; then
      [[ -f $case_dir/picker ]] || fail "direct capture uses its picker"
    else
      [[ ! -e $case_dir/picker ]] || fail "direct fullscreen capture skips the picker"
    fi
  else
    [[ $target == portal && ! -e $case_dir/picker ]] || fail "$name always uses the portal" "actual target: $target"
  fi
  [[ $(wc -l <"$case_dir/launches") == 1 ]] || fail "$name does not retry with a different capture backend"
  (( status != 0 )) || fail "$name reports recorder startup failure"
}

run_capture default unset
run_capture default-fullscreen unset --fullscreen
run_capture empty ''
run_capture invalid tru
run_capture explicit-portal true
run_capture portal-fullscreen true --fullscreen
run_capture direct false
run_capture direct-fullscreen false --fullscreen
pass "recording defaults to the portal and never falls back after failure"

MONARCH_PATH="$ROOT" "$ROOT/bin/monarch-menu" --tree | jq -e '
  [.[] | select(.id | startswith("trigger.capture.screenrecord.")) | .action]
  | any(. == "monarch-capture-screenrecording")
    and all(contains("--private") | not)
' >/dev/null
pass "the existing recording menu uses the default capture mode"
