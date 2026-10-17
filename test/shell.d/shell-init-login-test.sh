#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

for command in mise starship zoxide fzf try-rs exegol register-python-argcomplete; do
  printf '#!/bin/bash\nexit 0\n' >"$test_tmp/$command"
  chmod +x "$test_tmp/$command"
done

output=$(env -u SHELL PATH="$test_tmp:$PATH" bash -lc \
  "source '$ROOT/default/shells/init'; printf '%s' \"\$SHELL_NAME\"")
[[ $output == bash ]]

# The login shell must never override the running interpreter, in either direction.
output=$(SHELL=/bin/zsh PATH="$test_tmp:$PATH" bash --noprofile --norc -c \
  'source "$1"; printf "%s" "$SHELL_NAME"' bash "$ROOT/default/shells/init")
[[ $output == bash ]]

command -v zsh >/dev/null || { echo "zsh is required for shell initialization tests" >&2; exit 1; }
for login_shell in /bin/bash /bin/zsh ""; do
  output=$(SHELL="$login_shell" PATH="$test_tmp:$PATH" zsh -f -c \
    'autoload -Uz compinit; compinit -D; source "$1"; print -rn -- "$SHELL_NAME"' zsh "$ROOT/default/shells/init" 2>"$test_tmp/stderr")
  [[ $output == zsh ]]
  [[ ! -s $test_tmp/stderr ]]
done

echo "login shell initialization: ok"
