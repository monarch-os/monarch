#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export MONARCH_PATH="$ROOT" XDG_STATE_HOME="$test_tmp/state" XDG_CONFIG_HOME="$test_tmp/config"
export SUBMISSION_CALLS="$test_tmp/calls" SUBMISSION_BODY="$test_tmp/body" JOURNAL_FIXTURE="$test_tmp/journal"
export COPIED_LINK="$test_tmp/clipboard"
export PATH="$test_tmp/bin:$ROOT/bin:/usr/bin"
unset MONARCH_CRASH_ENDPOINT MONARCH_CRASH_ALLOW_LOCAL
id=0123456789abcdef0123456789abcdef:4242:1790859948000000

cat > "$test_tmp/bin/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SUBMISSION_CALLS"
[[ ${FAIL_SUBMIT:-0} != 1 ]] || exit 22
case "${!#}" in
  */v1/status) printf '%s\n' '{"schema":1,"enabled":true,"maxBytes":65536,"retentionDays":30}' ;;
  */v1/reports)
    for arg; do
      [[ $arg != @* ]] || cp "${arg#@}" "$SUBMISSION_BODY"
      [[ $arg != 'Idempotency-Key: '* ]] || key=${arg#'Idempotency-Key: '}
    done
    hash=$(printf '%s' "$key" | sha256sum | cut -d' ' -f1)
    jq -cn --arg url "${BAD_LINK:-https://crashes.example.com/admin/reports/$hash}" \
      '{reference:"MCR-0123456789ABCDEF",url:$url}'
    ;;
esac
EOF
cat > "$test_tmp/bin/journalctl" <<'EOF'
#!/bin/bash
cat "$JOURNAL_FIXTURE"
EOF
cat > "$test_tmp/bin/pacman" <<'EOF'
#!/bin/bash
exit 1
EOF
cat > "$test_tmp/bin/wl-copy" <<'EOF'
#!/bin/bash
cat > "$COPIED_LINK"
EOF
chmod +x "$test_tmp/bin/"*
jq -cn --arg uid "$UID" '{_BOOT_ID:"0123456789abcdef0123456789abcdef",COREDUMP_UID:$uid,
  COREDUMP_PID:"4242",COREDUMP_TIMESTAMP:"1790859948000000",COREDUMP_EXE:"/usr/bin/crasher",
  COREDUMP_SIGNAL_NAME:"SIGSEGV",COREDUMP_PACKAGE_NAME:"crasher",COREDUMP_PACKAGE_VERSION:"1.0.0",
  MESSAGE:"Stack trace of thread 4242:\n#0 do_crash (libcrasher.so + 0x10)\n#1 main (/home/alice/My Project (draft)/file.c + 0x20)"}' > "$JOURNAL_FIXTURE"

monarch-crash-submit status | jq -e '.enabled and .endpoint == "https://crashes.monarchlinux.com" and .retentionDays == 30' >/dev/null
[[ $(wc -l < "$SUBMISSION_CALLS") == 1 ]]
rg -q 'https://crashes.monarchlinux.com/v1/status$' "$SUBMISSION_CALLS"
FAIL_SUBMIT=1 monarch-crash-submit status | jq -e '.enabled == false and .endpoint == "https://crashes.monarchlinux.com"' >/dev/null

mkdir -p "$XDG_CONFIG_HOME/monarch"
jq -cn '{endpoint:""}' > "$XDG_CONFIG_HOME/monarch/crash-reporting.json"
before=$(wc -l < "$SUBMISSION_CALLS")
monarch-crash-submit status | jq -e '.enabled == false and .endpoint == ""' >/dev/null
[[ $(wc -l < "$SUBMISSION_CALLS") == "$before" ]]
if monarch-crash-submit send "$id" --confirm https://crashes.monarchlinux.com >/dev/null 2>&1; then
  echo "Sent a report while remote submission was disabled" >&2
  exit 1
fi
[[ $(wc -l < "$SUBMISSION_CALLS") == "$before" ]]
export MONARCH_CRASH_ENDPOINT=https://crashes.example.com
collection=$(monarch-crash-submit status)
jq -e '.enabled and .retentionDays == 30' <<< "$collection" >/dev/null
confirmed_endpoint=$(jq -r .endpoint <<< "$collection")
if monarch-crash-submit send "$id" --confirm "$confirmed_endpoint" >/dev/null 2>&1; then
  echo "Sent a report without a preview" >&2
  exit 1
fi
preview=$(monarch-crash-submit prepare "$id")
jq -e '.receipt == null and .report.crash.application == "crasher" and (.text | contains("do_crash"))' <<< "$preview" >/dev/null
if monarch-crash-submit send "$id" >/dev/null 2>&1; then
  echo "Sent a report without explicit confirmation" >&2
  exit 1
fi
! rg -q '/v1/reports' "$SUBMISSION_CALLS"

unset MONARCH_CRASH_ENDPOINT
jq -cn '{endpoint:"https://changed.example.com"}' > "$XDG_CONFIG_HOME/monarch/crash-reporting.json"
before=$(wc -l < "$SUBMISSION_CALLS")
if monarch-crash-submit send "$id" --confirm "$confirmed_endpoint" > "$test_tmp/output" 2> "$test_tmp/error"; then
  echo "Sent a report after its confirmed destination changed" >&2
  exit 1
fi
rg -q 'destination changed' "$test_tmp/error"
[[ $(wc -l < "$SUBMISSION_CALLS") == "$before" ]]
monarch-crash-submit prepare "$id" | jq -e '.receipt == null' >/dev/null
jq -cn --arg endpoint "$confirmed_endpoint" '{endpoint:$endpoint}' > "$XDG_CONFIG_HOME/monarch/crash-reporting.json"
if monarch-crash-submit send "$id" --confirm '' >/dev/null 2>&1; then
  echo "Accepted an empty confirmed destination" >&2
  exit 1
fi
[[ $(wc -l < "$SUBMISSION_CALLS") == "$before" ]]

# Reopening and retrying keep the reviewed snapshot even after journal rotation.
: > "$JOURNAL_FIXTURE"
again=$(monarch-crash-submit prepare "$id")
[[ $preview == "$again" ]]
if FAIL_SUBMIT=1 monarch-crash-submit send "$id" --confirm "$confirmed_endpoint" >/dev/null 2>&1; then
  echo "Accepted a failed upload" >&2
  exit 1
fi
for link in 'https://other.example.com/admin/reports/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  'https://crashes.example.com/admin/reports/short' 'https://crashes.example.com/admin/reports/../../private'; do
  if BAD_LINK="$link" monarch-crash-submit send "$id" --confirm "$confirmed_endpoint" >/dev/null 2>&1; then
    echo "Accepted an invalid crash link" >&2
    exit 1
  fi
  monarch-crash-submit prepare "$id" | jq -e '.receipt == null' >/dev/null
done
sent=$(monarch-crash-submit send "$id" --confirm "$confirmed_endpoint")
jq -e '.reference == "MCR-0123456789ABCDEF" and (.url | test("^https://crashes.example.com/admin/reports/[a-f0-9]{64}$"))' <<< "$sent" >/dev/null
jq -S . "$SUBMISSION_BODY" > "$test_tmp/actual"
jq -S .report <<< "$preview" > "$test_tmp/expected"
cmp "$test_tmp/expected" "$test_tmp/actual"
! rg -q '4242|submission|receipt|endpoint|alice|My Project|draft|file.c' "$SUBMISSION_BODY"
jq -e '.backtrace[2] == "#1 main (<private-path> + 0x20)"' "$SUBMISSION_BODY" >/dev/null
rg -q 'Idempotency-Key: [a-f0-9-]{36}' "$SUBMISSION_CALLS"
[[ $(sed -n 's/.*Idempotency-Key: \([a-f0-9-]*\).*/\1/p' "$SUBMISSION_CALLS" | sort -u | wc -l) == 1 ]]
before=$(wc -l < "$SUBMISSION_CALLS")
[[ $(monarch-crash-submit send "$id" --confirm) == "$sent" ]]
[[ $(wc -l < "$SUBMISSION_CALLS") == "$before" ]]
monarch-crash-submit prepare "$id" | jq -e '.receipt == "MCR-0123456789ABCDEF"' >/dev/null
monarch-crash-submit copy "$id"
[[ $(cat "$COPIED_LINK") == "$(jq -r .url <<< "$sent")" ]]
file="$XDG_STATE_HOME/monarch/crashes/submissions/${id//:/-}.json"
jq 'del(.url)' "$file" > "$test_tmp/legacy"
cat "$test_tmp/legacy" > "$file"
[[ $(monarch-crash-submit send "$id" --confirm) == "$sent" ]]
MONARCH_CRASH_ENDPOINT='' monarch-crash-submit copy "$id"
[[ $(cat "$COPIED_LINK") == "$(jq -r .url <<< "$sent")" ]]
[[ $(wc -l < "$SUBMISSION_CALLS") == "$before" ]]
[[ $(stat -c %a "$XDG_STATE_HOME/monarch/crashes/submissions") == 700 ]]
[[ $(stat -c %a "$XDG_STATE_HOME/monarch/crashes/submissions/${id//:/-}.json") == 600 ]]

for endpoint in 'http://evil.example.com' 'https://user:secret@example.com' 'https://example.com/path' 'https://example.com?token=secret'; do
  if MONARCH_CRASH_ENDPOINT="$endpoint" monarch-crash-submit status >/dev/null 2>&1; then
    echo "Accepted invalid collection endpoint" >&2
    exit 1
  fi
done
MONARCH_CRASH_ENDPOINT=http://127.0.0.1:8787 MONARCH_CRASH_ALLOW_LOCAL=1 monarch-crash-submit status | jq -e '.enabled' >/dev/null
echo "Crash submission confirmation, frozen preview, retries, receipts and private storage pass"
