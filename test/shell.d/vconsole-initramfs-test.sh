#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

vconsole="$test_tmp/vconsole.conf"
config_dir="$test_tmp/mkinitcpio.conf.d"
mkdir -p "$config_dir"

for config in "$ROOT/etc/mkinitcpio.conf.d/monarch"*.conf; do
  sed "s|/etc/vconsole.conf|$vconsole|g" "$config" >"$config_dir/${config##*/}"
done

python3 - "$config_dir" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
def nonlatin_layouts(name):
  arms = re.findall(r'^\s*([a-z]+(?:\s*\|\s*[a-z]+)+)\)', (root / name).read_text(), re.MULTILINE)
  assert len(arms) == 1, f'keyboard classification changed in {name}'
  return {layout.strip() for layout in arms[0].split('|')}

hooks = nonlatin_layouts('monarch_hooks.conf')
guard = nonlatin_layouts('monarch_vconsole.conf')
assert hooks == guard, f'keyboard classifications diverged: hooks only={hooks - guard}, guard only={guard - hooks}'
print('ok - independent initramfs drop-ins agree on non-Latin layouts')
PY

load_config() {
  local config
  for config in "$config_dir/"*.conf; do
    source "$config"
  done
}

probe_layout() (
  local layout="$1"
  local expected="$2"
  printf 'XKBLAYOUT="%s"\n' "$layout" >"$vconsole"
  FILES=()
  added=()
  add_file() { added+=("${2:-$1}"); }
  load_config
  load_config

  plymouth_build() {
    local FILES=()
    add_file "$vconsole"
  }
  plymouth_build
  [[ ${#added[@]} == "$expected" ]] ||
    fail "Plymouth copied the wrong keyboard layout for $layout" "${added[*]:-}"
)

probe_layout ru 0
probe_layout gr,us 0
probe_layout il 0
pass "Plymouth cannot reintroduce a non-Latin primary layout into the initramfs"

(
  printf '%s\n' 'XKBLAYOUT=ru' >"$vconsole"
  FILES=()
  added=()
  add_file() { added+=("$*"); }
  load_config
  add_file /another/source "$vconsole"
  [[ ${#added[@]} == 0 ]] || fail "an explicit add_file destination bypassed the keyboard guard"
)
pass "the guard also checks the destination passed to add_file"

probe_layout de 1
probe_layout fr,ru 1
pass "Latin primary layouts remain available at the LUKS prompt"

(
  printf '%s\n' 'XKBLAYOUT=ru' >"$vconsole"
  FILES=()
  added=()
  add_file() { added+=("${2:-$1}"); }
  load_config
  FILES+=("$vconsole")
  add_file "$vconsole"
  [[ ${added[*]} == "$vconsole" ]] || fail "an explicit FILES entry was ignored"
)
pass "an administrator can explicitly include vconsole.conf through FILES"

(
  printf '%s\n' 'KEYMAP=de-latin1' >"$vconsole"
  export XKBLAYOUT=ru
  FILES=()
  added=()
  add_file() { added+=("${2:-$1}"); }
  load_config
  local_copy() {
    local FILES=()
    add_file "$vconsole"
  }
  local_copy
  [[ ${added[*]} == "$vconsole" ]] || fail "an inherited XKBLAYOUT overrode vconsole.conf"
) 2>"$test_tmp/inherited.err"
[[ ! -s $test_tmp/inherited.err ]] || fail "a KEYMAP-only configuration produced errors" "$(<"$test_tmp/inherited.err")"
pass "a layout inherited from the caller cannot classify the boot keyboard"

(
  printf '%s\n' 'XKBLAYOUT=ru' >"$vconsole"
  FILES=()
  added=()
  add_file() { added+=("$*"); return 17; }
  load_config
  if add_file /usr/lib/other /destination 0644; then
    fail "the add_file exit status was lost"
  else
    [[ $? == 17 ]] || fail "the add_file exit status changed"
  fi
  [[ ${added[*]} == '/usr/lib/other /destination 0644' ]] ||
    fail "unrelated initramfs files lost their arguments"
)
pass "the guard preserves unrelated add_file arguments and failures"
