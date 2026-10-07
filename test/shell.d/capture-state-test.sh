#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
cleanup() {
  local pid_file pid
  for pid_file in "$test_tmp"/*/recorder.pid; do
    [[ -f $pid_file ]] || continue
    pid=$(<"$pid_file")
    kill -TERM "$pid" 2>/dev/null || true
  done
  rm -rf "$test_tmp"
}
trap cleanup EXIT
export HOME="$test_tmp/home" PATH="$test_tmp/bin:/usr/bin"
mkdir -p "$HOME" "$test_tmp/bin" "$test_tmp/runtime"
chmod 700 "$test_tmp/runtime"

cat >"$test_tmp/bin/pgrep" <<'STUB'
#!/bin/bash
[[ $* == "-u $UID -f ^gpu-screen-recorder" ]] || exit 99
[[ -f $CAPTURE_CASE/recorder.pid ]]
STUB
cat >"$test_tmp/bin/pkill" <<'STUB'
#!/bin/bash
[[ $* == "-SIGINT -u $UID -f ^gpu-screen-recorder" ]] || exit 99
kill -TERM "$(cat "$CAPTURE_CASE/recorder.pid")"
rm "$CAPTURE_CASE/recorder.pid"
STUB
cat >"$test_tmp/bin/gpu-screen-recorder" <<'STUB'
#!/bin/bash
while (($#)); do
  if [[ $1 == -o ]]; then
    filename=$2
    break
  fi
  shift
done
printf '%s\n' "$$" >"$CAPTURE_CASE/recorder.pid"
echo fixture-recorder-log >&2
printf 'raw\n' >"$filename"
exec sleep 30
STUB
cat >"$test_tmp/bin/ffmpeg" <<'STUB'
#!/bin/bash
for argument in "$@"; do
  case $argument in
    *-processed.mp4|*-preview.png)
      [[ $argument == "$CAPTURE_CASE/"* ]] || exit 99
      printf 'processed\n' >"$argument"
      ;;
  esac
done
STUB
cat >"$test_tmp/bin/ffprobe" <<'STUB'
#!/bin/bash
exit 1
STUB
cat >"$test_tmp/bin/monarch-notification-send" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >"$CAPTURE_CASE/notification"
STUB
chmod +x "$test_tmp/bin/"*

run_capture() {
  local name=$1 state_dir=$2
  shift 2
  local case_dir="$test_tmp/$name" filename
  mkdir -p "$case_dir"
  local -a capture_env=(env -u XDG_RUNTIME_DIR -u XDG_STATE_HOME
    HOME="$HOME" PATH="$PATH" CAPTURE_CASE="$case_dir"
    MONARCH_SCREENRECORD_DIR="$case_dir" MONARCH_SCREENRECORD_DEBUG=true "$@")
  "${capture_env[@]}" "$ROOT/bin/monarch-capture-screenrecording" --resolution=1920x1080 >"$case_dir/start-output" 2>&1
  filename=$(<"$state_dir/monarch-screenrecord-filename")
  [[ $filename == "$case_dir/"* && -f $filename ]] || fail "$name stores the recording filename in the expected state directory"
  [[ $(stat -c '%a' "$state_dir") == 700 && \
    $(stat -c '%a' "$state_dir/monarch-screenrecord-filename") == 600 && \
    $(stat -c '%a' "$state_dir/monarch-screenrecord.log") == 600 ]] || fail "$name keeps recording state and logs private"
  grep -Fq fixture-recorder-log "$state_dir/monarch-screenrecord.log" || fail "$name writes debug output to its private log"
  "${capture_env[@]}" "$ROOT/bin/monarch-capture-screenrecording" --stop-recording >"$case_dir/stop-output" 2>&1
  [[ $(<"$filename") == processed && -s $case_dir/notification ]] || fail "$name cannot stop and finalize its recording"
  [[ ! -e $state_dir/monarch-screenrecord-filename && ! -e $case_dir/recorder.pid ]] || fail "$name leaves active recording state behind"
  pass "$name starts, stops and finalizes recordings with private state and logs"
}

run_capture runtime "$test_tmp/runtime" XDG_RUNTIME_DIR="$test_tmp/runtime"
run_capture default-fallback "$HOME/.local/state/monarch"
mkdir -p "$test_tmp/state/monarch"
chmod 755 "$test_tmp/state/monarch"
run_capture existing-fallback "$test_tmp/state/monarch" XDG_STATE_HOME="$test_tmp/state"
