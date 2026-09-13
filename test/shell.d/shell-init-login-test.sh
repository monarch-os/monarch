#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

for command in mise starship zoxide fzf try-rs exegol; do
  printf '#!/bin/bash\nexit 0\n' >"$test_tmp/$command"
  chmod +x "$test_tmp/$command"
done

output=$(env -u SHELL PATH="$test_tmp:$PATH" bash -lc \
  "source '$ROOT/default/shells/init'; printf '%s' \"\$SHELL_NAME\"")
[[ $output == bash ]]

echo "login shell initialization: ok"
