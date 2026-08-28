#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

run_migrations() {
  HOME="$1/home" MONARCH_PATH="$ROOT" PATH="$1/bin:/usr/bin" \
    bash "$ROOT/bin/monarch-migrate" >/dev/null
}

prepare_fixture() {
  local fixture=$1 status=$2

  mkdir -p "$fixture/bin" "$fixture/home/.local/state/monarch/migrations"
  touch "$fixture/home/.local/state/monarch/migrations/1784734532.sh"
  printf '%s\n' "$status" >"$fixture/status"

  cat >"$fixture/bin/noctalia" <<'EOF'
#!/bin/bash

if [[ $1 == "msg" && $2 == "status" ]]; then
  [[ $(<"$TEST_FIXTURE/status") == "ready" ]]
  exit
fi

printf '%s\n' "$*" >>"$TEST_FIXTURE/calls"
EOF
  chmod +x "$fixture/bin/noctalia"
  export TEST_FIXTURE=$fixture
}

immediate="$TEST_ROOT/immediate"
prepare_fixture "$immediate" ready
run_migrations "$immediate"

plugin="$immediate/home/.local/share/noctalia/plugins/monarch-theme"
[[ -f $plugin/plugin.toml ]]
grep -qx 'msg plugins enable monarch/theme' "$immediate/calls"
[[ -f $immediate/home/.local/state/monarch/migrations/1787731970.sh ]]

run_migrations "$immediate"
[[ $(wc -l <"$immediate/calls") == 1 ]]

deferred="$TEST_ROOT/deferred"
prepare_fixture "$deferred" unavailable
run_migrations "$deferred"

hook="$deferred/home/.config/monarch/hooks/post-boot.d/noctalia-theme-plugin"
[[ -x $hook ]]
[[ ! -e $deferred/calls ]]

printf '%s\n' ready >"$deferred/status"
HOME="$deferred/home" PATH="$deferred/bin:/usr/bin" TEST_FIXTURE="$deferred" bash "$hook"
grep -qx 'msg plugins enable monarch/theme' "$deferred/calls"
[[ ! -e $hook ]]

[[ $(find "$ROOT/migrations" -maxdepth 1 -type f -name '*.sh' | wc -l) == 2 ]]

echo "All migration tests passed."
