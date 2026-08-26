#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export PATH="$TEST_ROOT/bin:$PATH"
farm="$HOME/.config/monarch/backgrounds/current"
source_dir="$TEST_ROOT/source"
mkdir -p "$farm" "$source_dir" "$TEST_ROOT/bin"

cp "$ROOT/themes/monarch/1-monarch.png" "$source_dir/first.png"
cp "$ROOT/themes/monarch/2-moon.jpg" "$source_dir/second.jpg"
ln -s "$source_dir/first.png" "$farm/first.png"
ln -s "$source_dir/second.jpg" "$farm/second.jpg"

cat >"$TEST_ROOT/bin/noctalia" <<EOF
#!/bin/bash
if [[ \${1:-} == msg && \${2:-} == wallpaper-get ]]; then
  echo "$source_dir/second.jpg"
fi
EOF
cat >"$TEST_ROOT/bin/magick" <<'EOF'
#!/bin/bash
source=${1%\[0\]}
cp "$source" "${@: -1}"
EOF
chmod +x "$TEST_ROOT/bin/noctalia" "$TEST_ROOT/bin/magick"

output=$("$ROOT/bin/monarch-theme-background-list")
expected=$(printf 'false\tfirst.png\t%s\ntrue\tsecond.jpg\t%s' "$source_dir/first.png" "$source_dir/second.jpg")
[[ $(cut -f1-3 <<<"$output") == "$expected" ]]
while IFS=$'\t' read -r _current _name _path thumbnail; do
  [[ -f $thumbnail ]]
done <<<"$output"

printf 'ok\n'
