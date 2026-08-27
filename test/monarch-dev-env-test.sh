#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/home"
export HOME="$TEST_ROOT/home"
export TEST_LOG="$TEST_ROOT/calls"
export PATH="$TEST_ROOT/bin:$ROOT/bin:/usr/bin"

cat >"$TEST_ROOT/bin/mise" <<'EOF'
#!/bin/bash
printf 'mise %s\n' "$*" >>"$TEST_LOG"
EOF

cat >"$TEST_ROOT/bin/curl" <<'EOF'
#!/bin/bash
printf 'curl %s\n' "$*" >>"$TEST_LOG"
printf '#!/bin/bash\nexit 0\n'
EOF

cat >"$TEST_ROOT/bin/monarch-pkg-drop" <<'EOF'
#!/bin/bash
printf 'drop %s\n' "$*" >>"$TEST_LOG"
EOF

chmod +x "$TEST_ROOT/bin/"*

"$ROOT/bin/monarch-install-dev-env" python >/dev/null
grep -qx 'mise use --global python@latest' "$TEST_LOG"
grep -qx 'curl -fsSL https://astral.sh/uv/install.sh' "$TEST_LOG"

"$ROOT/bin/monarch-remove-dev-env" php >/dev/null
"$ROOT/bin/monarch-remove-dev-env" symfony >/dev/null
grep -qx 'drop php composer php-sqlite xdebug' "$TEST_LOG"
grep -qx 'drop symfony-cli' "$TEST_LOG"

grep -qF '$HOME/.local/share/mise/shims' "$ROOT/default/shells/envs"
grep -qF '$HOME/.local/share/mise/shims' "$ROOT/config/uwsm/env"
grep -qF '@{HOME}/.local/share/mise/shims' "$ROOT/install/config/ssh-command-path.sh"

shell_home="$TEST_ROOT/shell-home"
shell_path=$(HOME="$shell_home" MONARCH_PATH= PATH=/usr/bin bash -c 'unset MONARCH_PATH; . "$1"; . "$1"; printf "%s" "$PATH"' sh "$ROOT/default/shells/envs")
[[ $shell_path == "/usr/share/monarch/bin:/usr/bin:$shell_home/.local/share/mise/shims:$shell_home/.local/bin" ]]

checkout="$shell_home/checkout"
override_path=$(HOME="$shell_home" MONARCH_PATH="$checkout" PATH=/usr/bin bash -c '. "$1"; . "$1"; printf "%s" "$PATH"' sh "$ROOT/default/shells/envs")
[[ $override_path == "$checkout/bin:/usr/bin:$shell_home/.local/share/mise/shims:$shell_home/.local/bin" ]]

echo "All development environment tests passed."
