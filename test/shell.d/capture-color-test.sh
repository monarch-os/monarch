#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
export COLOR_TEST_ROOT=$test_root
mkdir -p "$test_root/bin"

cat >"$test_root/bin/slurp" <<'EOF'
#!/bin/bash
[[ ${COLOR_TEST_MODE:-valid} == cancel ]] && exit 1
printf '%s\n' '-12,34 1x1'
EOF
cat >"$test_root/bin/grim" <<'EOF'
#!/bin/bash
[[ $1 == -g && $2 == '-12,34 1x1' && $3 == -t && $4 == ppm && $5 == - ]] || exit 2
case ${COLOR_TEST_MODE:-valid} in
  empty) exit 0 ;;
  truncated) printf 'P6\n1 1\n255'; exit 0 ;;
  short-pixel) printf 'P6\n1 1\n255\n\x12'; exit 0 ;;
  invalid) printf 'P3\n1 1\n255\n123'; exit 0 ;;
  wrong-size) printf 'P6\n2 1\n255\n123456'; exit 0 ;;
  whitespace-pixel) printf 'P6\n1 1\n255\n\x0a\x20\x09' ;;
  *) printf 'P6\n1 1\n255\n\x12\x34\x56' ;;
esac
[[ ${COLOR_TEST_MODE:-valid} != failed ]]
EOF
cat >"$test_root/bin/wl-copy" <<'EOF'
#!/bin/bash
cat >"$COLOR_TEST_ROOT/clipboard"
EOF
cat >"$test_root/bin/monarch-notification-send" <<'EOF'
#!/bin/bash
touch "$COLOR_TEST_ROOT/notified"
EOF
cat >"$test_root/bin/monarch-i18n" <<'EOF'
#!/bin/bash
printf '%s\n' "$1"
EOF
chmod +x "$test_root/bin/"*
export PATH="$test_root/bin:$PATH"

run_picker() {
  rm -f "$test_root/clipboard" "$test_root/notified"
  timeout 3 bash "$ROOT/bin/monarch-capture-color" >"$test_root/output" 2>"$test_root/error"
}

run_picker || fail "valid pixel capture failed" "$(cat "$test_root/error")"
[[ $(cat "$test_root/clipboard") == '#123456' ]] || fail "wrong pixel copied"
[[ $(cat "$test_root/output") == '#123456' && -f $test_root/notified ]] || fail "successful capture not reported"
pass "slurp geometry is passed intact, including negative coordinates"

COLOR_TEST_MODE=whitespace-pixel run_picker || fail "whitespace-valued pixel rejected"
[[ $(cat "$test_root/clipboard") == '#0a2009' ]] || fail "pixel bytes consumed as header whitespace"
pass "binary whitespace pixel values are preserved"

for mode in empty truncated short-pixel invalid wrong-size failed; do
  if COLOR_TEST_MODE=$mode run_picker; then
    fail "$mode capture accepted"
  else
    status=$?
    ((status != 124)) || fail "$mode capture hung"
  fi
  [[ ! -e $test_root/clipboard && ! -e $test_root/notified ]] || fail "$mode capture reported success or changed clipboard"
  pass "$mode capture fails without hanging or changing clipboard"
done

COLOR_TEST_MODE=cancel run_picker || fail "cancel is not a clean exit"
[[ ! -e $test_root/clipboard && ! -e $test_root/notified ]] || fail "cancel changed clipboard or notified"
pass "cancel leaves clipboard untouched"
