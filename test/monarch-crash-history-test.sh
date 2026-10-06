#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/home"
export JOURNAL_FIXTURE="$test_tmp/journal.jsonl" JOURNAL_CALLS="$test_tmp/journal.calls"
export PACMAN_CALLS="$test_tmp/pacman.calls"
export NOCTALIA_CALLS="$test_tmp/noctalia.calls"
export XDG_CONFIG_HOME="$test_tmp/home" XDG_STATE_HOME="$test_tmp/state" MONARCH_PATH="$ROOT"
export PATH="$test_tmp/bin:$ROOT/bin:/usr/bin"
boot=0123456789abcdef0123456789abcdef
old_boot=abcdef0123456789abcdef0123456789
id="$boot:4242:1790859948000000"
old_id="$old_boot:4242:1790684259000000"

cat > "$test_tmp/bin/journalctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$JOURNAL_CALLS"
[[ ${FAIL_JOURNAL:-0} != 1 ]] || exit 1
matches='{}'
for arg; do
  case $arg in
    _BOOT_ID=*|COREDUMP_PID=*|COREDUMP_TIMESTAMP=*)
      matches=$(jq -cn --argjson previous "$matches" --arg key "${arg%%=*}" --arg value "${arg#*=}" '$previous + {($key):$value}')
      ;;
  esac
done
jq -c --argjson matches "$matches" 'select(. as $entry | $matches | to_entries | all(.value == $entry[.key]))' "$JOURNAL_FIXTURE"
EOF
cat > "$test_tmp/bin/pacman" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$PACMAN_CALLS"
[[ ${TEST_PACKAGE_MISSING:-0} != 1 ]] || exit 1
if [[ $1 == "-Qoq" ]]; then echo crasher; else echo "$3 1.2.3-1"; fi
EOF
cat > "$test_tmp/bin/monarch-default-agent" <<'EOF'
#!/bin/bash
[[ ${NO_AGENT:-false} == "true" ]] || printf 'codex\n'
EOF
cat > "$test_tmp/bin/monarch-cmd-present" <<'EOF'
#!/bin/bash
[[ ${AGENT_MISSING:-false} != "true" ]]
EOF
cat > "$test_tmp/bin/noctalia" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$NOCTALIA_CALLS"
EOF
chmod +x "$test_tmp/bin/"*
touch "$test_tmp/core"

entry() {
  jq -cn --arg uid "$1" --arg boot "$2" --arg timestamp "$3" --arg file "$4" \
    --arg home "$test_tmp/home" '{_BOOT_ID:$boot,COREDUMP_UID:$uid,COREDUMP_PID:"4242",
      COREDUMP_TIMESTAMP:$timestamp,COREDUMP_EXE:"/usr/bin/crasher",COREDUMP_SIGNAL_NAME:"SIGSEGV",
      COREDUMP_FILENAME:$file,COREDUMP_ENVIRON:"TOKEN=DO_NOT_EXPORT",COREDUMP_CMDLINE:"crasher SECRET_ARGUMENT",
      COREDUMP_HOSTNAME:"PRIVATE_HOST",MESSAGE:("Process 4242 of user 1000: SECRET_HEADER\nStack trace of thread 4242:\n#0  0x000abcdef do_crash (libcrasher.so + 0x10)\n#1  0x000abcdef main ("+$home+"/My Project (draft)/private-source.c + 0x20)\nTOKEN=DO_NOT_EXPORT")}'
}
entry "$UID" "$boot" 1790859948000000 "$test_tmp/core" > "$JOURNAL_FIXTURE"
entry "$UID" "$old_boot" 1790684259000000 "$test_tmp/gone" >> "$JOURNAL_FIXTURE"
entry "$((UID + 1))" "$boot" 1790959948000000 "$test_tmp/core" >> "$JOURNAL_FIXTURE"
state=$(monarch-crash-history list --json)
jq -e --arg id "$id" --arg old "$old_id" \
  '.crashes | length == 2 and .[0].id == $id and .[1].id == $old and .[0].core == "present" and .[1].core == "missing"' <<< "$state" >/dev/null
! rg -q 'PRIVATE_HOST|SECRET_ARGUMENT|TOKEN|/usr/bin/crasher|private-source' <<< "$state"

: > "$JOURNAL_FIXTURE"
for ((index = 0; index <= 100; index++)); do
  entry "$UID" "$boot" "$((1790859948000000 + index))" "$test_tmp/core" >> "$JOURNAL_FIXTURE"
done
state=$(monarch-crash-history list --json)
jq -e --arg id "$id" '.hasMore == true and (.crashes | length) == 100
  and all(.crashes[]; .id != $id)' <<< "$state" >/dev/null
detail=$(monarch-crash-history show "$id" --json)
jq -e --arg id "$id" '.id == $id and .application == "crasher"' <<< "$detail" >/dev/null
entry "$UID" "$boot" 1790859948000000 "$test_tmp/core" > "$JOURNAL_FIXTURE"
entry "$UID" "$old_boot" 1790684259000000 "$test_tmp/gone" >> "$JOURNAL_FIXTURE"
entry "$((UID + 1))" "$boot" 1790959948000000 "$test_tmp/core" >> "$JOURNAL_FIXTURE"

report=$(monarch-crash-history report "$id" --json)
jq -e '.crash.application == "crasher" and .package.version == "1.2.3-1" and .package.source == "installed" and (.backtrace | length) == 3' <<< "$report" >/dev/null
! rg -q 'PRIVATE_HOST|SECRET_ARGUMENT|TOKEN|SECRET_HEADER|My Project|draft|private-source|0x000abcdef|"pid"|"id"' <<< "$report"
rg -q '<private-path>' <<< "$report"
jq -e '.backtrace[2] == "#1  main (<private-path> + 0x20)"' <<< "$report" >/dev/null
old_report=$(monarch-crash-history report "$old_id" --json)
jq -e '.crash.core == "missing" and .crash.date == "2026-09-29 12:17 UTC"' <<< "$old_report" >/dev/null

frames=$(jq -n -L "$ROOT/default/monarch" 'include "crashes";
  {MESSAGE:([
    "#0 first (/home/alice/My Project/file.c + 0x10)",
    "#1 second (/tmp/My Project (draft)/module.so + 0x20)",
    "#2 third (/run/user/1000/My Project/module.so + 0x30)",
    "#3 fourth (/root/My Project/module.so + 0x40)",
    "#4 fifth at /home/alice/My Project/file.c:12",
    "#5 system (/usr/lib/My Library.so + 0x50)"
  ] | join("\n"))} | frames')
jq -e '. == [
  "#0 first (<private-path> + 0x10)",
  "#1 second (<private-path> + 0x20)",
  "#2 third (<private-path> + 0x30)",
  "#3 fourth (<private-path> + 0x40)",
  "#4 fifth at <private-path>",
  "#5 system (/usr/lib/My Library.so + 0x50)"
]' <<< "$frames" >/dev/null

entry "$UID" "$boot" 1790859948000000 "$test_tmp/core" |
  jq '.COREDUMP_PACKAGE_NAME="journal-crasher" | del(.COREDUMP_EXE)' > "$JOURNAL_FIXTURE"
: > "$PACMAN_CALLS"
partial=$(monarch-crash-history report "$id" --json)
jq -e '.package == {name:"journal-crasher",version:"1.2.3-1",source:"installed"}' <<< "$partial" >/dev/null
[[ $(cat "$PACMAN_CALLS") == '-Q -- journal-crasher' ]]
missing=$(TEST_PACKAGE_MISSING=1 monarch-crash-history report "$id" --json)
jq -e '.package == {name:"journal-crasher",version:"",source:"journal"}' <<< "$missing" >/dev/null

jq '.COREDUMP_PACKAGE_VERSION="9.8.7"' "$JOURNAL_FIXTURE" > "$test_tmp/versioned"
mv "$test_tmp/versioned" "$JOURNAL_FIXTURE"
: > "$PACMAN_CALLS"
versioned=$(monarch-crash-history report "$id" --json)
jq -e '.package == {name:"journal-crasher",version:"9.8.7",source:"journal"}' <<< "$versioned" >/dev/null
[[ ! -s $PACMAN_CALLS ]]
entry "$UID" "$boot" 1790859948000000 "$test_tmp/core" |
  jq '.COREDUMP_PACKAGE_VERSION="9.8.7"' > "$JOURNAL_FIXTURE"
versioned=$(monarch-crash-history report "$id" --json)
jq -e '.package == {name:"crasher",version:"9.8.7",source:"journal"}' <<< "$versioned" >/dev/null
entry "$UID" "$boot" 1790859948000000 "$test_tmp/core" > "$JOURNAL_FIXTURE"

saved=$(monarch-crash-history export "$id" | jq -r .path)
[[ -f $saved && $(stat -c %a "$saved") == 600 ]]
[[ $(stat -c %a "${saved%/*}") == 700 ]]
monarch-crash-history report "$id" > "$test_tmp/preview.txt"
cmp "$saved" "$test_tmp/preview.txt"
! rg -q 'PRIVATE_HOST|SECRET_ARGUMENT|TOKEN|SECRET_HEADER|My Project|draft|private-source' "$saved"

# A journal rotation between preview and export must not replace the preview.
: > "$JOURNAL_FIXTURE"
saved=$(monarch-crash-history export "$id" --stdin < "$test_tmp/preview.txt" | jq -r .path)
cmp "$saved" "$test_tmp/preview.txt"
entry "$UID" "$boot" 1790859948000000 "$test_tmp/core" > "$JOURNAL_FIXTURE"
if monarch-crash-history export "$id" --stdin </dev/null >/dev/null 2>&1; then
  echo "Exported an empty preview" >&2
  exit 1
fi
printf -v oversized '%65537s' ''
if printf '%s' "$oversized" | monarch-crash-history export "$id" --stdin >/dev/null 2>&1; then
  echo "Exported an oversized preview" >&2
  exit 1
fi

for invalid in '' 4242 '../escape' "$boot:4242:bad" "$boot:4242:1790859948000000; touch injected"; do
  if monarch-crash-history export "$invalid" >/dev/null 2>&1; then
    echo "Accepted invalid crash id" >&2
    exit 1
  fi
done
if monarch-crash-history report "$boot:4242:1" >/dev/null 2>&1; then
  echo "Returned a different crash when the requested event was absent" >&2
  exit 1
fi
if FAIL_JOURNAL=1 monarch-crash-history list --json >/dev/null 2>&1; then
  echo "Reported an unreadable journal as an empty history" >&2
  exit 1
fi
! rg -q 'COREDUMP_ENVIRON|COREDUMP_CMDLINE|COREDUMP_OPEN_FDS|COREDUMP_PROC|COREDUMP_HOSTNAME' "$JOURNAL_CALLS"
rg -q "COREDUMP_UID=$UID" "$JOURNAL_CALLS"

: > "$JOURNAL_FIXTURE"
monarch-crash-history list --json | jq -e '.crashes == [] and .hasMore == false' >/dev/null
entry "$UID" "$boot" 1790859948000000 '' > "$JOURNAL_FIXTURE"
monarch-crash-history list --json | jq -e '.crashes[0].core == "unavailable"' >/dev/null

monarch-crash-history open "$id"
sed -n 's/^msg panel-open monarch\/crashes:panel //p' "$NOCTALIA_CALLS" |
  jq -e --arg id "$id" 'select(.id == $id and .agent == true)' >/dev/null
: > "$NOCTALIA_CALLS"
NO_AGENT=true monarch-crash-history open "$id"
sed -n 's/^msg panel-open monarch\/crashes:panel //p' "$NOCTALIA_CALLS" |
  jq -e --arg id "$id" 'select(.id == $id and .agent == false)' >/dev/null
: > "$NOCTALIA_CALLS"
AGENT_MISSING=true monarch-crash-history open "$id"
sed -n 's/^msg panel-open monarch\/crashes:panel //p' "$NOCTALIA_CALLS" |
  jq -e --arg id "$id" 'select(.id == $id and .agent == false)' >/dev/null

echo "Crash history identity, user scope, journal failure, report projection and private export pass"
