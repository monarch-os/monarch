#!/bin/bash

set -euo pipefail

case "${0##*/}" in
  blkid) printf '%s' "$LUKS_DRIVES"; exit 0 ;;
  monarch-drive-select) printf '%s' "$LUKS_SELECTED"; exit 0 ;;
  gum)
    printf '%s\n' "$*" >>"$LUKS_CASE/prompts"
    [[ ! ${new_password+x} && ! ${confirmation+x} ]] || touch "$LUKS_CASE/leak"
    if [[ ! -e $LUKS_CASE/prompted ]]; then
      touch "$LUKS_CASE/prompted"
      printf '%s' "$LUKS_NEW"
      exit "$LUKS_INPUT_STATUS"
    fi
    printf '%s' "$LUKS_CONFIRMATION"
    exit "$LUKS_CONFIRM_STATUS"
    ;;
  sudo)
    printf '%s\0' "$@" >>"$LUKS_CASE/args"
    [[ ! ${new_password+x} && ! ${confirmation+x} ]] || touch "$LUKS_CASE/leak"
    (( LUKS_SUDO_STATUS == 0 )) || exit "$LUKS_SUDO_STATUS"
    if [[ ${LUKS_REGRESSION:-} == 1 && $1 == bash ]]; then exec "$@"; fi
    [[ $1 == /usr/bin/bash && $2 == -p && $3 == /usr/share/monarch/install/drive-password/rekey.sh ]] || exit 98
    exec /usr/bin/bash -p "$LUKS_FIXTURE/helper" "$4"
    ;;
  sync)
    file=$2
    point=''
    if [[ -f $file ]]; then
      point=temporary-$(jq -r .phase "$file")
    elif [[ -d $file ]]; then
      journals=("$file"/*.json)
      if [[ -e ${journals[0]} ]]; then point=published-$(jq -r .phase "${journals[0]}"); else point=journal-removed; fi
    fi
    if [[ ${LUKS_SYNC_ERROR:-} == "$point" ]]; then exit 5; fi
    if [[ ${LUKS_CRASH:-} == "$point" ]]; then kill -KILL "$PPID"; fi
    exit 0
    ;;
  cryptsetup)
    printf '%s\0' "$@" >>"$LUKS_CASE/args"
    [[ ! ${new_password+x} && ! ${current_password+x} ]] || touch "$LUKS_CASE/leak"
    exec python3 - "$@" <<'PY'
import hashlib, json, os, struct, sys, signal
from pathlib import Path
p = Path(os.environ['LUKS_CASE'])
args = sys.argv[1:]
op = args.pop(0)
options, positional = {}, []
while args:
    a = args.pop(0)
    if a in ('--test-passphrase', '--batch-mode', '--dump-json-metadata'):
        options[a] = True
    elif a.startswith('--'):
        options[a] = args.pop(0)
    else:
        positional.append(a)
state = json.loads((p/'volume').read_text())
def save():
    (p/'volume').write_text(json.dumps(state))
def event(name):
    with (p/'events').open('a') as f: f.write(name+'\n')
    if os.environ.get('LUKS_CRASH') == name:
        parent = os.getppid()
        if Path('/proc/'+str(parent)+'/comm').read_text().strip() == 'timeout':
            parent = int(next(line.split()[1] for line in Path('/proc/'+str(parent)+'/status').read_text().splitlines() if line.startswith('PPid:')))
        os.kill(parent, signal.SIGKILL)
        sys.exit(137)
def secret():
    return Path(options['--key-file']).read_text()
if op == 'fixture-header':
    header = bytearray(1024)
    header[:6] = b'LUKS\xba\xbe'
    version = int(os.environ.get('LUKS_VERSION', '2'))
    struct.pack_into('>H',header,6,version)
    if version == 1:
        for start, value in [(8,b'aes'),(40,b'xts-plain64'),(72,b'sha256')]:
            header[start:start+len(value)] = value
        struct.pack_into('>II',header,104,8192,64)
        struct.pack_into('>I',header,164,1000)
        encoded_uuid = state['uuid'].encode('ascii')
        header[168:168+len(encoded_uuid)] = encoded_uuid
        for i in range(8):
            s = state['slots'].get(str(i))
            struct.pack_into('>II32sII',header,208+i*48,
                0x00AC71F3 if s else 0x0000DEAD, 1000 if s else 0,
                hashlib.sha256(s['salt'].encode()).digest() if s else bytes(32),
                8+i*512,4000)
    fault = os.environ.get('LUKS_HEADER_FAULT')
    if fault == 'magic': header[0] = 0
    if fault == 'marker': struct.pack_into('>I',header,208,123)
    if fault == 'overlap': struct.pack_into('>I',header,208+48+40,8)
    if fault == 'stripes': struct.pack_into('>I',header,208+44,3999)
    if fault == 'uuid': header[168] = ord('2')
    if fault == 'iterations': struct.pack_into('>I',header,212,0)
    if fault == 'hash': header[72:104] = b'x'*32
    if fault == 'size': struct.pack_into('>I',header,108,0xffffffff)
    if fault == 'boundary': struct.pack_into('>I',header,104,10)
    if fault == 'version': struct.pack_into('>H',header,6,3)
    if fault == 'truncated': header = header[:511]
    (p/'header').write_bytes(header)
elif op == 'luksUUID':
    print(state['uuid'])
elif op == 'luksDump':
    if os.environ.get('LUKS_VERSION') == '1': sys.exit(1)
    print(json.dumps({'keyslots': {k: {'type':'luks2', 'kdf':{'salt':v['salt']}} for k,v in state['slots'].items()}}))
elif op == 'open':
    if os.environ.get('LUKS_OPEN_ERROR'): sys.exit(4)
    if options.get('--token-type') != 'passphrase-only':
        (p/'token-false-positive').touch()
        sys.exit(0)
    s = state['slots'].get(options['--key-slot'])
    sys.exit(0 if s and secret() == s['key'] else 2)
elif op == 'luksAddKey':
    event('before-add')
    if os.environ.get('LUKS_ADD_ERROR'): sys.exit(5)
    target = options['--key-slot']
    version = int(os.environ.get('LUKS_VERSION', '2'))
    if options.get('--pbkdf') != ('pbkdf2' if version == 1 else 'argon2id'): sys.exit(97)
    if not 0 <= int(target) < (8 if version == 1 else 32): sys.exit(97)
    if target in state['slots']: sys.exit(1)
    if secret() not in [v['key'] for v in state['slots'].values()]: sys.exit(2)
    new = Path(positional[1]).read_text()
    (p/'received-key').write_text(new)
    state['slots'][target] = {'key':new, 'salt':'new-salt'}
    save()
    if os.environ.get('LUKS_ENROLL_RECOVERY'):
        state['slots']['7'] = {'key':'independent-fixture', 'salt':'external-salt'}
        save()
    event('after-add')
elif op == 'luksKillSlot':
    event('before-kill')
    if os.environ.get('LUKS_KILL_ERROR'): sys.exit(5)
    target = positional[1]
    if secret() not in [v['key'] for k,v in state['slots'].items() if k != target]: sys.exit(2)
    del state['slots'][target]
    save()
    event('after-kill')
elif op == 'luksChangeKey' and os.environ.get('LUKS_REGRESSION') == '1':
    with open('/dev/tty') as tty:
        if tty.readline().strip() != 'current-fixture': sys.exit(2)
    state['slots']['2'] = {'key':Path(positional[1]).read_text(), 'salt':'new-salt'}
    save()
    event('after-add')
else:
    sys.exit(97)
PY
    ;;
esac

if [[ -z ${LUKS_MATRIX_CHILD:-} ]]; then
  for version in 1 2; do
    echo "LUKS$version fixture matrix"
    LUKS_MATRIX_CHILD=1 LUKS_TEST_VERSION=$version bash "$0"
  done
  exit
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
export LUKS_FIXTURE=$test_dir
mkdir "$test_dir/bin"
for stub in blkid monarch-drive-select gum sudo cryptsetup sync; do
  ln -s "$ROOT/test/monarch-drive-password-test.sh" "$test_dir/bin/$stub"
done
export PATH="$test_dir/bin:$PATH" ROOT
export LUKS_COMMAND=${LUKS_COMMAND:-$ROOT/bin/monarch-drive-password}

# Substitute only host boundaries; all journal and key-transition logic is shipped code.
python3 - "$ROOT" "$test_dir" <<'PY'
import os, sys
from pathlib import Path
root, tmp = map(Path, sys.argv[1:])
s = (root/'install/drive-password/rekey.sh').read_text()
s = s.replace('&& $EUID == 0', '&& $EUID == '+str(os.getuid()))
s = s.replace('export PATH=/usr/bin:/bin LC_ALL=C', 'export PATH="'+str(tmp)+'/bin:/usr/bin:/bin" LC_ALL=C')
s = s.replace('state_dir=/var/lib/monarch-drive-password', 'state_dir=$LUKS_CASE/state')
s = s.replace('/run/monarch-drive-password.lock', '"$LUKS_CASE/lock"')
s = s.replace('provisioning=/var/lib/monarch/provisioning', 'provisioning=$LUKS_CASE/provisioning')
s = s.replace('&& -b $1', '&& $1 == /dev/test-*').replace('&& -b $drive', '&& $drive == /dev/test-*')
s = s.replace('== 0:700', '== '+str(os.getuid())+':700').replace('== 0:600', '== '+str(os.getuid())+':600')
s = s.replace('  header=$(timeout --foreground 120 /usr/bin/python3 -I /usr/share/monarch/install/drive-password/metadata.py "$drive" "$uuid")',
    '  cryptsetup fixture-header\n  header=$(timeout --foreground 120 /usr/bin/python3 -I "$ROOT/install/drive-password/metadata.py" "$LUKS_CASE/header" "$uuid")')
(tmp/'helper').write_text(s)
PY

fail() { echo "not ok - $*" >&2; cat "$LUKS_CASE/output" >&2; exit 1; }
reset_case() {
  export LUKS_CASE
  LUKS_CASE=$(mktemp -d "$test_dir/case.XXXXXX")
  export LUKS_DRIVES=/dev/test-luks LUKS_SELECTED=/dev/test-luks
  export LUKS_NEW=replacement-fixture LUKS_CONFIRMATION=replacement-fixture
  export LUKS_INPUT_STATUS=0 LUKS_CONFIRM_STATUS=0 LUKS_SUDO_STATUS=0
  export LUKS_VERSION=${LUKS_TEST_VERSION:-2}
  unset LUKS_CRASH LUKS_OPEN_ERROR LUKS_ADD_ERROR LUKS_KILL_ERROR LUKS_ENROLL_RECOVERY LUKS_SYNC_ERROR LUKS_HEADER_FAULT
  python3 - <<'PY'
import json, os
from pathlib import Path
Path(os.environ['LUKS_CASE']+'/volume').write_text(json.dumps({'uuid':'11111111-1111-1111-1111-111111111111', 'slots':{'0':{'key':'current-fixture','salt':'old-salt'},'1':{'key':'recovery-fixture','salt':'recovery-salt'}}}))
PY
}
attempt() {
  rm -f "$LUKS_CASE/prompted"
  if printf '%s\n' "$@" | timeout 20s script -q -e -E never -c \
    'new_password=seed confirmation=seed bash -c '\''set -a; export SHELLOPTS; exec bash -x "$LUKS_COMMAND"'\''' \
    /dev/null >"$LUKS_CASE/output" 2>&1; then status=0; else status=$?; fi
  (( status != 124 )) || fail "hung at a prompt"
}
journal() { printf '%s/state/11111111-1111-1111-1111-111111111111.json' "$LUKS_CASE"; }
slots() { jq -cS '.slots | with_entries(.value = .value.key)' "$LUKS_CASE/volume"; }
assert_failed() { (( status != 0 )) || fail "$1 succeeded"; }
assert_complete() {
  (( status == 0 )) || fail "change did not finish"
  [[ ! -e $(journal) ]] || fail "completed journal remains"
  jq -e --arg key "$LUKS_NEW" '.slots["0"] == null and .slots["2"].key == $key and .slots["1"].key == "recovery-fixture"' "$LUKS_CASE/volume" >/dev/null || fail "wrong slots retired"
}
assert_private() {
  [[ ! -e $LUKS_CASE/leak && ! -e $LUKS_CASE/token-false-positive ]] || fail "environment/token leak"
  for file in "$LUKS_CASE/args" "$LUKS_CASE/output" "$(journal)"; do
    [[ -e $file ]] || continue
    ! grep -qF -e "$LUKS_NEW" -e current-fixture -e recovery-fixture "$file" || fail "secret in arguments, trace or journal"
  done
  [[ ! -e $(journal) || $(stat -c %a "$(journal)") == 600 ]] || fail "journal is not private"
}

if [[ ${LUKS_REGRESSION:-} == 1 ]]; then
  reset_case
  export LUKS_CRASH=after-add
  attempt current-fixture
  assert_failed 'interrupted key replacement'
  [[ -e $(journal) ]] || fail 'regression: interruption after adding a key leaves no durable resume journal'
  echo 'ok - interrupted key replacement has a durable journal'
  exit
fi

for input in empty mismatch cancel-new cancel-confirm; do
  reset_case
  case $input in
    empty) LUKS_NEW=''; LUKS_CONFIRMATION='' ;;
    mismatch) LUKS_CONFIRMATION='*' ;;
    cancel-new) LUKS_INPUT_STATUS=130 ;;
    cancel-confirm) LUKS_CONFIRM_STATUS=130 ;;
  esac
  attempt
  assert_failed "$input"
  [[ ! -e $LUKS_CASE/args ]] || fail "$input reached sudo"
done
echo 'ok - empty, mismatched and cancelled passwords stop before sudo'

for password in replacement-fixture '   ' '  p@ss "quote" '\''quote %s $() `literal` \\ * [ab] café  ' "$(printf '%0512d' 0)"; do
  reset_case
  LUKS_NEW=$password LUKS_CONFIRMATION=$password
  attempt current-fixture
  assert_complete
  printf '%s' "$password" | cmp -s - "$LUKS_CASE/received-key" || fail "password bytes changed"
  assert_private
done
echo 'ok - FD transport preserves bytes, terminal old-password input, no argv/environment/xtrace leaks'

for point in before-add after-add before-kill after-kill; do
  reset_case
  export LUKS_CRASH=$point
  attempt current-fixture
  assert_failed "crash $point"
  [[ -e $(journal) ]] || fail "interruption has no journal"
  assert_private
  unset LUKS_CRASH
  attempt current-fixture 'ADOPT 11111111-1111-1111-1111-111111111111 2'
  assert_complete
done
echo 'ok - interruption before/after add and deletion resumes, including after old-secret removal'

for point in temporary-prepared published-prepared temporary-verified published-verified journal-removed; do
  reset_case
  export LUKS_CRASH=$point
  attempt current-fixture
  assert_failed "journal interruption $point"
  assert_private
  unset LUKS_CRASH
  if [[ $point == journal-removed ]]; then
    jq -e '.slots["0"] == null and .slots["2"].key == "replacement-fixture"' "$LUKS_CASE/volume" >/dev/null || fail 'completed interruption lost new secret'
    [[ ! -e $(journal) ]] || fail 'removed journal reappeared'
  else
    attempt current-fixture 'ADOPT 11111111-1111-1111-1111-111111111111 2'
    assert_complete
  fi
done
echo 'ok - interruption at journal temporary-file/publication/removal boundaries remains recoverable'

for point in temporary-prepared published-prepared temporary-verified published-verified; do
  reset_case
  export LUKS_SYNC_ERROR=$point
  attempt current-fixture
  assert_failed "journal durability failure $point"
  jq -e '.slots["0"].key == "current-fixture"' "$LUKS_CASE/volume" >/dev/null || fail 'sync failure retired old slot'
  unset LUKS_SYNC_ERROR
  attempt current-fixture 'ADOPT 11111111-1111-1111-1111-111111111111 2'
  assert_complete
done
echo 'ok - journal durability errors stop before retirement and can be retried'

reset_case
export LUKS_CRASH=after-add
attempt current-fixture
unset LUKS_CRASH
before=$(slots)
attempt current-fixture NO
assert_failed 'unconfirmed added slot'
[[ $(slots) == "$before" ]] || fail "unconfirmed slot changed"
attempt current-fixture 'ADOPT 11111111-1111-1111-1111-111111111111 2'
assert_complete
echo 'ok - adoption of a slot appearing during interruption requires explicit confirmation'

for corruption in invalid uuid base target old format symlink permissions; do
  reset_case
  export LUKS_CRASH=before-kill
  attempt current-fixture
  unset LUKS_CRASH
  case $corruption in
    invalid) printf 'not json\n' >"$(journal)" ;;
    uuid) jq '.uuid="22222222-2222-2222-2222-222222222222"' "$(journal)" >"$LUKS_CASE/edit"; mv "$LUKS_CASE/edit" "$(journal)"; chmod 600 "$(journal)" ;;
    base) jq '.slots["1"].salt="replacement-salt"' "$LUKS_CASE/volume" >"$LUKS_CASE/edit"; mv "$LUKS_CASE/edit" "$LUKS_CASE/volume" ;;
    target) jq '.slots["2"].salt="replacement-salt"' "$LUKS_CASE/volume" >"$LUKS_CASE/edit"; mv "$LUKS_CASE/edit" "$LUKS_CASE/volume" ;;
    old) jq '.slots["0"]={key:"independent-fixture",salt:"reused-old-slot-salt"}' "$LUKS_CASE/volume" >"$LUKS_CASE/edit"; mv "$LUKS_CASE/edit" "$LUKS_CASE/volume" ;;
    format) export LUKS_VERSION=$((3 - LUKS_TEST_VERSION)) ;;
    symlink) mv "$(journal)" "$LUKS_CASE/foreign"; ln -s "$LUKS_CASE/foreign" "$(journal)" ;;
    permissions) chmod 644 "$(journal)" ;;
  esac
  before=$(slots)
  attempt current-fixture
  assert_failed "$corruption journal/slot"
  [[ $(slots) == "$before" && -e $(journal) ]] || fail "invalid state was consumed"
done
echo 'ok - invalid/foreign UUID journals and replaced baseline/new slots fail closed'

reset_case
export LUKS_CRASH=before-add
attempt current-fixture
unset LUKS_CRASH
jq '.slots["2"]={key:"independent-fixture",salt:"independent-salt"}' "$LUKS_CASE/volume" >"$LUKS_CASE/edit"
mv "$LUKS_CASE/edit" "$LUKS_CASE/volume"
before=$(slots)
attempt current-fixture 'ADOPT 11111111-1111-1111-1111-111111111111 2'
assert_failed 'independent recovery in target'
[[ $(slots) == "$before" ]] || fail "independent recovery removed"

reset_case
export LUKS_ENROLL_RECOVERY=1 LUKS_CRASH=after-add
attempt current-fixture
unset LUKS_CRASH
attempt current-fixture 'ADOPT 11111111-1111-1111-1111-111111111111 2'
assert_complete
jq -e '.slots["7"].key == "independent-fixture"' "$LUKS_CASE/volume" >/dev/null || fail 'concurrent recovery lost'
echo 'ok - independent recovery keys are preserved, including one occupying the planned slot'

reset_case
python3 - <<'PY'
import json, os
from pathlib import Path
p = Path(os.environ['LUKS_CASE'])/'volume'
state = json.loads(p.read_text())
for i in range(8 if os.environ['LUKS_VERSION'] == '1' else 32):
    state['slots'].setdefault(str(i), {'key':'capacity-fixture-'+str(i), 'salt':'capacity-salt-'+str(i)})
p.write_text(json.dumps(state))
PY
before=$(slots)
attempt current-fixture
assert_failed 'no free key slot'
[[ $(slots) == "$before" && ! -e $(journal) ]] || fail 'full header was modified'
echo 'ok - a full slot table is refused before journaling or modifying keys'

for error in LUKS_OPEN_ERROR LUKS_ADD_ERROR LUKS_KILL_ERROR; do
  reset_case
  export "$error=1"
  attempt current-fixture
  assert_failed "$error"
  jq -e '.slots["0"].key == "current-fixture" and .slots["1"].key == "recovery-fixture"' "$LUKS_CASE/volume" >/dev/null || fail 'error removed original slot'
  unset "$error"
  attempt current-fixture 'ADOPT 11111111-1111-1111-1111-111111111111 2'
  assert_complete
done
reset_case
attempt wrong-fixture
assert_failed 'wrong old password'
grep -qF 'That current password does not open' "$LUKS_CASE/output" || fail 'wrong-password diagnostic'
[[ ! -e $(journal) ]] || fail 'wrong password started a journal'
echo 'ok - tool errors and incorrect secrets are distinguished; failed transitions remain retryable'

reset_case
jq '.slots["3"]={key:"current-fixture",salt:"duplicate-salt"}' "$LUKS_CASE/volume" >"$LUKS_CASE/edit"
mv "$LUKS_CASE/edit" "$LUKS_CASE/volume"
before=$(slots)
attempt current-fixture 0 NO
assert_failed 'duplicate without confirmation'
[[ $(slots) == "$before" ]] || fail 'duplicate changed without choice'
attempt current-fixture 0 'REPLACE 0'
assert_complete
jq -e '.slots["3"].key == "current-fixture"' "$LUKS_CASE/volume" >/dev/null || fail 'duplicate not preserved'
echo 'ok - duplicate old secret requires explicit slot choice and acknowledgement of surviving copies'

reset_case
exec {held}>"$LUKS_CASE/lock"
flock -n "$held"
attempt current-fixture
assert_failed 'concurrent invocation'
[[ ! -e $(journal) && ! -e $LUKS_CASE/events ]] || fail 'concurrent invocation touched disk'
exec {held}>&-
echo 'ok - concurrent invocation cannot inspect or mutate the volume while lock is held'

faults=(magic truncated version)
if [[ $LUKS_TEST_VERSION == 1 ]]; then faults+=(marker overlap stripes uuid iterations hash size boundary); fi
for fault in "${faults[@]}"; do
  reset_case
  export LUKS_HEADER_FAULT=$fault
  attempt current-fixture
  assert_failed "invalid LUKS header $fault"
  [[ ! -e $(journal) && ! -e $LUKS_CASE/events ]] || fail 'invalid header mutated'
done
echo 'ok - real binary metadata parser rejects invalid/truncated/foreign/overlapping headers before mutation'

if [[ $LUKS_TEST_VERSION == 1 ]]; then
  reset_case
  cryptsetup fixture-header
  /usr/bin/python3 -I "$ROOT/install/drive-password/metadata.py" "$LUKS_CASE/header" 11111111-1111-1111-1111-111111111111 >"$LUKS_CASE/metadata"
  jq -e '(.slots | keys) == ["0","1"] and .slots["0"].type == "luks1"' "$LUKS_CASE/metadata" >/dev/null || fail 'LUKS1 parser missed active slots'
  python3 - "$LUKS_CASE/header" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
header = bytearray(p.read_bytes())
header[208+8] ^= 1
p.write_bytes(header)
PY
  /usr/bin/python3 -I "$ROOT/install/drive-password/metadata.py" "$LUKS_CASE/header" 11111111-1111-1111-1111-111111111111 >"$LUKS_CASE/changed"
  [[ $(jq -r '.slots["0"].entry' "$LUKS_CASE/metadata") != "$(jq -r '.slots["0"].entry' "$LUKS_CASE/changed")" ]] || fail 'salt reuse did not change slot identity'
  [[ $(jq -r '.slots["1"]' "$LUKS_CASE/metadata") == "$(jq -r '.slots["1"]' "$LUKS_CASE/changed")" ]] || fail 'unrelated slot identity changed'
  echo 'ok - binary LUKS1 parser identifies exact active entries and changes identity for a reused slot salt'
fi

reset_case
export LUKS_DRIVES=$'/dev/test-first\n/dev/test-second' LUKS_SELECTED=''
attempt
(( status == 0 )) || fail 'drive selection cancellation'
[[ ! -e $LUKS_CASE/prompts ]] || fail 'cancelled selection prompted'
LUKS_DRIVES=''
attempt
assert_failed 'no drives'

if /usr/bin/bash "$ROOT/install/drive-password/rekey.sh" -p >"$LUKS_CASE/output" 2>&1; then fail 'ordinary Bash with decoy -p accepted'; fi
echo 'ok - selection cancellation and privilege-mode guard are preserved'
