#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home"
export MONARCH_PATH="$ROOT"
export USER=tester
export PATH="$TEST_ROOT/bin:$PATH"
mkdir -p "$HOME" "$TEST_ROOT/bin"

fail() {
  echo "not ok - $1" >&2
  exit 1
}

pass() {
  echo "ok - $1"
}

for command_name in monarch-pkg-add monarch-pkg-drop monarch-webapp-install monarch-webapp-remove systemctl tailscale; do
  cat >"$TEST_ROOT/bin/$command_name" <<EOF
#!/bin/bash
printf '%s %s\n' '$command_name' "\$*" >>'$TEST_ROOT/calls'
[[ '$command_name' != monarch-pkg-add || \${PKG_FAIL:-0} == 0 ]]
EOF
done
cat >"$TEST_ROOT/bin/sudo" <<'EOF'
#!/bin/bash
"$@"
EOF
chmod +x "$TEST_ROOT/bin/"*

if PKG_FAIL=1 "$ROOT/bin/monarch-install-tailscale" >/dev/null 2>&1; then
  fail "installer succeeds after package failure"
fi
[[ $(wc -l <"$TEST_ROOT/calls") == 1 ]] || fail "installer continued after package failure"
pass "installer stops after package failure"

: >"$TEST_ROOT/calls"
"$ROOT/bin/monarch-install-tailscale" >/dev/null
grep -Fx 'tailscale set --operator=tester' "$TEST_ROOT/calls" >/dev/null || fail "installer omits operator permission"
grep -Fx 'systemctl --user enable --now monarch-tailscale-receive.service' "$TEST_ROOT/calls" >/dev/null || fail "installer omits receiver activation"
[[ -f $HOME/.config/systemd/user/monarch-tailscale-receive.service ]] || fail "installer omits the receiver unit"
pass "installer configures operator access and receiver"

cat >"$TEST_ROOT/bin/monarch-cmd-present" <<'EOF'
#!/bin/bash
[[ ${TAILSCALE_PRESENT:-0} == 1 ]]
EOF
cat >"$TEST_ROOT/bin/jq" <<'EOF'
#!/bin/bash
grep -q '"BackendState":"Running"'
EOF
cat >"$TEST_ROOT/bin/tailscale" <<EOF
#!/bin/bash
if [[ \${TAILSCALE_RUNNING:-0} == 1 ]]; then
  printf '{"BackendState":"Running"}\n'
else
  printf '{"BackendState":"NeedsLogin"}\n'
fi
EOF
cat >"$TEST_ROOT/bin/systemctl" <<'EOF'
#!/bin/bash
[[ ${SYSTEMD_ACTIVE:-0} == 1 ]]
EOF
chmod +x "$TEST_ROOT/bin/monarch-cmd-present" "$TEST_ROOT/bin/jq" "$TEST_ROOT/bin/tailscale" "$TEST_ROOT/bin/systemctl"

if TAILSCALE_PRESENT=1 TAILSCALE_RUNNING=0 SYSTEMD_ACTIVE=1 "$ROOT/bin/monarch-tailscale-installed"; then
  fail "incomplete login is considered installed"
fi
if TAILSCALE_PRESENT=1 TAILSCALE_RUNNING=1 SYSTEMD_ACTIVE=0 "$ROOT/bin/monarch-tailscale-installed"; then
  fail "inactive services are considered installed"
fi
TAILSCALE_PRESENT=1 TAILSCALE_RUNNING=1 SYSTEMD_ACTIVE=1 "$ROOT/bin/monarch-tailscale-installed" || fail "operational integration is not detected"
pass "installed state requires a running tailnet and receiver"

mkdir -p "$HOME/Downloads/.monarch-taildrop"
printf 'received' >"$HOME/Downloads/file.txt"
printf 'partial' >"$HOME/Downloads/.monarch-taildrop/partial.txt"
"$ROOT/bin/monarch-remove-service-tailscale" >/dev/null
[[ ! -f $HOME/.config/systemd/user/monarch-tailscale-receive.service ]] || fail "removal leaves its user unit"
[[ -f $HOME/Downloads/file.txt && -f $HOME/Downloads/.monarch-taildrop/partial.txt ]] || fail "removal deletes received data"
pass "removal disables integration without deleting files"
