#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export MONARCH_PATH="$ROOT" TEST_ACTIVATION="$test_tmp"
mkdir -p "$test_tmp/bin"
ln -s "$ROOT/bin/monarch-cmd-present" "$test_tmp/bin/monarch-cmd-present"
printf '#!/bin/bash\nexit "${TEST_CODEXBAR_FAILURE:-0}"\n' >"$test_tmp/bin/codexbar"
cat >"$test_tmp/bin/noctalia" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_ACTIVATION/calls"
if [[ $* == 'msg status' ]]; then
  [[ ${TEST_ACTIVATION_FAILURE:-} != unavailable ]]
elif [[ $* == "${TEST_ACTIVATION_FAILURE:-}" ]]; then
  exit 42
elif [[ $* == 'config export merged' ]]; then
  python3 - <<'PY'
import os
from pathlib import Path
import tomllib

home = Path.home()
config = Path(os.environ.get('XDG_CONFIG_HOME') or home / '.config') / 'noctalia'
state = Path(os.environ.get('XDG_STATE_HOME') or home / '.local/state') / 'noctalia/settings.toml'
paths = sorted(config.glob('*.toml'))
if state.exists():
  paths.append(state)
shell = {}
for path in paths:
  shell.update(tomllib.loads(path.read_text()).get('shell', {}))
key = 'niri_overview_close_on_launch_enabled'
if key in shell:
  print(f'[shell]\n{key} = {str(shell[key]).lower()}')
PY
elif [[ $* == 'msg config-set shell.niri_overview_close_on_launch_enabled true' ]]; then
  mkdir -p "$XDG_STATE_HOME/noctalia"
  printf '[shell]\nniri_overview_close_on_launch_enabled = true\n' >"$XDG_STATE_HOME/noctalia/settings.toml"
elif [[ $* == 'config export full' && ${TEST_PLUGINS_PRE_ENABLED:-0} == "1" ]]; then
  cat "$MONARCH_PATH/config/noctalia/config.toml"
fi
EOF
printf '#!/bin/bash\nexit 0\n' >"$test_tmp/bin/sleep"
printf '#!/bin/bash\nexit 0\n' >"$test_tmp/bin/mise"
printf '#!/bin/bash\nexit 0\n' >"$test_tmp/bin/monarch-restart-noctalia"
printf '#!/bin/bash\nprintf complete >"$TEST_ACTIVATION/completed"\n' >"$test_tmp/bin/complete"
printf '#!/bin/bash\nexit 0\n' >"$test_tmp/bin/monarch-theme-apply"
printf '#!/bin/bash\nexit 0\n' >"$test_tmp/bin/systemctl"
printf '#!/bin/bash\nexit 1\n' >"$test_tmp/bin/pacman"
cat >"$test_tmp/bin/python3" <<'EOF'
#!/bin/bash
if [[ ${TEST_TEMPLATE_FAILURE:-0} == "1" && $1 == */noctalia-templates.py ]]; then
  echo 'simulated template seed failure' >&2
  exit 42
fi
exec /usr/bin/python3 "$@"
EOF
chmod +x "$test_tmp/bin/"*
export PATH="$test_tmp/bin:/usr/bin" MONARCH_RECONCILE_BIN="$test_tmp/bin/complete"

(
  export HOME="$test_tmp/overview" XDG_CONFIG_HOME="$test_tmp/overview/config" XDG_STATE_HOME="$test_tmp/overview/state"
  source "$ROOT/install/reconcile/noctalia-activation.sh"
  mkdir -p "$XDG_CONFIG_HOME/noctalia" "$XDG_STATE_HOME/noctalia"
  config="$XDG_CONFIG_HOME/noctalia/config.toml"
  overlay="$XDG_CONFIG_HOME/noctalia/custom.toml"
  state="$XDG_STATE_HOME/noctalia/settings.toml"
  printf '[shell]\nclipboard_enabled = true\n' >"$config"
  cp "$config" "$test_tmp/overview-original"
  for file in "$config" "$overlay" "$state"; do
    for value in true false; do
      printf '[shell]\nniri_overview_close_on_launch_enabled = %s\n' "$value" >"$file"
      : >"$test_tmp/calls"
      monarch_noctalia_reconcile_overview
      if grep -q '^msg config-set ' "$test_tmp/calls"; then
        fail "explicit $value in $file is preserved"
      fi
    done
    rm "$file"
  done
  cp "$test_tmp/overview-original" "$config"
  printf '[invalid\n' >"$overlay"
  if monarch_noctalia_reconcile_overview 2>/dev/null; then
    fail "malformed configuration must not be treated as an absent preference"
  fi
  if grep -q '^msg config-set ' "$test_tmp/calls"; then
    fail "invalid configuration causes no IPC writes"
  fi
  rm "$overlay"
  if TEST_ACTIVATION_FAILURE='msg config-set shell.niri_overview_close_on_launch_enabled true' \
    monarch_noctalia_reconcile_overview; then
    fail "IPC failure must remain retryable"
  fi
  [[ ! -e $state ]] || fail "failed IPC must not record completion"
  : >"$test_tmp/calls"
  monarch_noctalia_reconcile_overview
  monarch_noctalia_reconcile_overview
  [[ $(grep -c '^msg config-set ' "$test_tmp/calls") == 1 ]] || fail "overview default is seeded once"
  cmp "$config" "$test_tmp/overview-original" || fail "existing config is preserved"
  pass "overview reconciliation preserves explicit choices and retries missing defaults idempotently"
)

export HOME="$test_tmp/legacy" XDG_STATE_HOME="$test_tmp/legacy/.local/state"
legacy="$HOME/.local/share/noctalia/plugins/monarch-agents"
mkdir -p "$legacy"
printf 'legacy collector\n' >"$legacy/service.luau"
if TEST_CODEXBAR_FAILURE=1 bash "$ROOT/install/reconcile/user.sh" >/dev/null 2>&1; then
  fail "invalid CodexBar configuration stops reconciliation"
fi
[[ $(cat "$legacy/service.luau") == "legacy collector" ]] || fail "failed migration preserves the old collector"
[[ ! -f $legacy/data.luau ]] || fail "failed migration does not seed the replacement"
cat >"$test_tmp/bin/cp" <<'EOF'
#!/bin/bash
if [[ ${TEST_AGENTS_COPY_FAIL:-0} == "1" && $* == *"monarch-agents/."* ]]; then exit 1; fi
exec /usr/bin/cp "$@"
EOF
chmod +x "$test_tmp/bin/cp"
if TEST_AGENTS_COPY_FAIL=1 bash "$ROOT/install/reconcile/user.sh" >/dev/null 2>&1; then
  fail "replacement copy failure stops reconciliation"
fi
[[ $(cat "$legacy/service.luau") == "legacy collector" ]] || fail "replacement copy failure retains the live collector"
[[ -f $XDG_STATE_HOME/monarch/backups/noctalia/monarch-agents/service.luau ]] || fail "archive is retained for a retry"
bash "$ROOT/install/reconcile/user.sh" >/dev/null
[[ $(cat "$XDG_STATE_HOME/monarch/backups/noctalia/monarch-agents/service.luau") == "legacy collector" ]] ||
  fail "successful migration archives the collector before replacement"
[[ -f $legacy/data.luau && ! -f $legacy/service.luau ]] || fail "successful migration installs the replacement"
TEST_CODEXBAR_FAILURE=1 bash "$ROOT/install/reconcile/user.sh" >/dev/null
pass "invalid provider configuration no longer blocks ordinary plugin reconciliation"
pass "CodexBar migration validates before replacement and archives the legacy collector"

for entrypoint in first-run reconcile deferred; do
  export HOME="$test_tmp/$entrypoint"
  export XDG_STATE_HOME="$HOME/.local/state"
  mkdir -p "$XDG_STATE_HOME/noctalia/community-templates/neovim"
  printf 'partial user cache\n' >"$XDG_STATE_HOME/noctalia/community-templates/neovim/template.toml"
  if [[ $entrypoint == "reconcile" ]]; then
    mkdir -p "$HOME/.config/noctalia"
    printf '[hooks]\nstarted = "my-startup-command"\ncolors_changed = "my-theme-command"\n' >"$HOME/.config/noctalia/config.toml"
    cp "$HOME/.config/noctalia/config.toml" "$test_tmp/user-config"
    mkdir -p "$HOME/.local/state/monarch"
    touch "$HOME/.local/state/monarch/reboot-required"
  fi
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
  if [[ $entrypoint == "reconcile" ]]; then
    [[ ! -e $HOME/.config/noctalia/monarch-state.toml ]] ||
      fail "reconciliation installs a fragment overriding the user's started hook"
    cmp "$HOME/.config/noctalia/config.toml" "$test_tmp/user-config" ||
      fail "state cleanup hook installation rewrites user configuration"
    [[ $(cat "$HOME/.local/state/monarch/reboot-required") == $(cat /proc/sys/kernel/random/boot_id) ]] ||
      fail "reconciliation does not associate legacy markers with the boot before the next restart"
    pass "reconciliation adopts legacy markers without changing user hooks"
  fi
  [[ $(grep -c '^msg plugins enable ' "$test_tmp/calls") == 9 ]]
  grep -qx 'msg plugins enable monarch/theme' "$test_tmp/calls"
  [[ $(tail -1 "$test_tmp/calls") == 'msg config-reload' ]] || fail "$entrypoint reloads after activation"
  grep '^msg plugins enable ' "$test_tmp/calls" | sort >"$test_tmp/$entrypoint-plugins"
  [[ ! -e $hook ]]

  for failure in unavailable 'config export merged' 'msg config-set shell.niri_overview_close_on_launch_enabled true' 'config export full' 'msg plugins enable monarch/menu' 'msg config-reload'; do
    rm -f "$XDG_STATE_HOME/noctalia/settings.toml"
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

: >"$test_tmp/calls"
TEST_PLUGINS_PRE_ENABLED=1 bash "$ROOT/install/user/first-run/enable-noctalia-plugins.sh" >/dev/null
if grep -q '^msg plugins enable ' "$test_tmp/calls"; then
  fail "fresh accounts do not re-enable active plugins through remote catalog discovery"
fi
[[ $(tail -1 "$test_tmp/calls") == 'msg config-reload' ]]
pass "fresh accounts skip catalog-backed enablement for plugins already active in their initial config"

for script in "$ROOT/install/user/first-run/enable-noctalia-plugins.sh" \
  "$ROOT/install/reconcile/user.sh" "$ROOT/install/reconcile/noctalia-plugins.sh"; do
  : >"$test_tmp/calls"
  cp "$script" "$test_tmp/template-failure.sh"
  TEST_TEMPLATE_FAILURE=1 bash "$test_tmp/template-failure.sh" >/dev/null 2>&1
  [[ $(grep -c '^msg plugins enable ' "$test_tmp/calls") == 9 ]] ||
    fail "template seeding failure prevents plugin activation"
done
pass "optional template seeding failures do not block reconciliation or plugin activation"
