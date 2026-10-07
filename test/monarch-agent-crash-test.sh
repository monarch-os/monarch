#!/bin/bash

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export PATH="$test_tmp/bin:/usr/bin" MONARCH_PATH="$root"
export TEST_UID=$UID TEST_CALLS="$test_tmp/coredumpctl.calls" TEST_PROMPT="$test_tmp/prompt"
id=0123456789abcdef0123456789abcdef:4242:1790859948000000

cat > "$test_tmp/bin/coredumpctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$TEST_CALLS"
[[ ${TEST_MISSING:-false} != "true" ]] || exit 1
if [[ ${TEST_WRONG:-false} == "true" ]]; then
  printf '{"BootID":"0123456789abcdef0123456789abcdef","PID":4242,"Timestamp":1790859949000000,"UID":%s}\n' "$TEST_UID"
  exit
fi
printf '{"BootID":"0123456789abcdef0123456789abcdef","PID":4242,"Timestamp":1790859948000000,"UID":%s,"ThreadName":"crasher","Executable":"/usr/bin/crasher","SignalName":"SEGV"}\n' "$TEST_UID"
[[ " $* " == *" --quiet "* ]] || printf 'Output may be incomplete while a coredump is being processed.\n'
EOF
cat > "$test_tmp/bin/monarch-agent" <<'EOF'
#!/bin/bash
[[ $1 == "--prompt" ]]
printf '%s\n' "$2" > "$TEST_PROMPT"
EOF
chmod +x "$test_tmp/bin/"*

"$root/bin/monarch-agent-crash" "$id"
grep -Fx -- '--no-pager --quiet --json=short info COREDUMP_PID=4242 _BOOT_ID=0123456789abcdef0123456789abcdef COREDUMP_TIMESTAMP=1790859948000000' "$TEST_CALLS" >/dev/null
grep -F 'binary:   /usr/bin/crasher' "$TEST_PROMPT" >/dev/null
grep -F 'COREDUMP_TIMESTAMP=1790859948000000' "$TEST_PROMPT" >/dev/null
grep -F 'Never select this crash by PID alone.' "$TEST_PROMPT" >/dev/null

: > "$TEST_CALLS"
: > "$TEST_PROMPT"
if TEST_MISSING=true "$root/bin/monarch-agent-crash" "$id" 2> "$test_tmp/error"; then
  echo "A missing exact crash should not launch the agent." >&2
  exit 1
fi
grep -F 'This crash is no longer available.' "$test_tmp/error" >/dev/null
[[ ! -s $TEST_PROMPT ]]

: > "$TEST_PROMPT"
if TEST_WRONG=true "$root/bin/monarch-agent-crash" "$id" 2> "$test_tmp/error"; then
  echo "A reused PID must not select another crash." >&2
  exit 1
fi
[[ ! -s $TEST_PROMPT ]]

echo "Exact crash identity is preserved for the AI diagnosis"
