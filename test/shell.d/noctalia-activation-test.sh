#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export MONARCH_PATH="$ROOT" TEST_ACTIVATION="$test_tmp"
mkdir -p "$test_tmp/bin"
cat >"$test_tmp/bin/noctalia" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_ACTIVATION/calls"
if [[ $* == 'msg status' ]]; then
  [[ ${TEST_ACTIVATION_FAILURE:-} != unavailable ]]
elif [[ $* == "${TEST_ACTIVATION_FAILURE:-}" ]]; then
  exit 42
fi
EOF
printf '#!/bin/bash\nexit 0\n' >"$test_tmp/bin/sleep"
printf '#!/bin/bash\nprintf complete >"$TEST_ACTIVATION/completed"\n' >"$test_tmp/bin/complete"
printf '#!/bin/bash\nexit 0\n' >"$test_tmp/bin/monarch-theme-apply"
chmod +x "$test_tmp/bin/"*
export PATH="$test_tmp/bin:/usr/bin" MONARCH_RECONCILE_BIN="$test_tmp/bin/complete"

for entrypoint in first-run reconcile deferred; do
  export HOME="$test_tmp/$entrypoint"
  hook="$HOME/.config/monarch/hooks/post-boot.d/noctalia-v5-plugins"
  mkdir -p "${hook%/*}"
  case $entrypoint in
    first-run) script="$ROOT/install/user/first-run/enable-noctalia-plugins.sh" ;;
    reconcile) script="$ROOT/install/reconcile/user.sh" ;;
    deferred)
      script="$hook"
      cp "$ROOT/install/reconcile/noctalia-plugins.sh" "$hook"
      ;;
  esac
  : >"$test_tmp/calls"
  bash "$script" >/dev/null
  [[ $(grep -c '^msg plugins enable ' "$test_tmp/calls") == 7 ]]
  grep -qx 'msg plugins enable monarch/theme' "$test_tmp/calls"
  [[ $(tail -1 "$test_tmp/calls") == 'msg config-reload' ]] || fail "$entrypoint reloads after activation"
  grep '^msg plugins enable ' "$test_tmp/calls" | sort >"$test_tmp/$entrypoint-plugins"
  [[ ! -e $hook ]]

  for failure in unavailable 'msg plugins enable monarch/menu' 'msg config-reload'; do
    export TEST_ACTIVATION_FAILURE="$failure"
    rm -f "$test_tmp/completed"
    : >"$test_tmp/calls"
    if [[ $entrypoint == deferred ]]; then
      cp "$ROOT/install/reconcile/noctalia-plugins.sh" "$hook"
    fi
    if bash "$script" >/dev/null 2>&1; then
      [[ $entrypoint != first-run ]] || fail "first-run propagates $failure"
    else
      [[ $entrypoint == first-run ]] || fail "$entrypoint defers $failure"
    fi
    if [[ $entrypoint != first-run ]]; then
      [[ -f $hook ]] || fail "$entrypoint retains its retry hook after $failure"
      [[ ! -e $test_tmp/completed ]] || fail "deferred activation cannot complete on $failure"
    fi
    unset TEST_ACTIVATION_FAILURE
  done
  bash "$script" >/dev/null
  [[ ! -e $hook ]]
  pass "$entrypoint enables all plugins, reloads, and retains its failure/retry policy"
done
cmp "$test_tmp/first-run-plugins" "$test_tmp/reconcile-plugins"
cmp "$test_tmp/first-run-plugins" "$test_tmp/deferred-plugins"
python3 <<'PY'
import os
from pathlib import Path
import tomllib

runtime = Path(os.environ["MONARCH_PATH"])
expected = sorted(
  "msg plugins enable " + tomllib.loads(path.read_text())["id"]
  for path in (runtime / "default/noctalia/plugins").glob("monarch-*/plugin.toml")
)
actual = (Path(os.environ["TEST_ACTIVATION"]) / "first-run-plugins").read_text().splitlines()
assert actual == expected
PY
pass "all entrypoints use the same plugin inventory"
