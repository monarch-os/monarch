#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export PATH="$TEST_ROOT/bin:$PATH"
export MONARCH_PATH="$TEST_ROOT/monarch"
farm="$HOME/.config/monarch/backgrounds/current"
source_dir="$TEST_ROOT/source"
user_dir="$HOME/.config/monarch/backgrounds/monarch"
shipped_dir="$MONARCH_PATH/themes/monarch"
mkdir -p "$farm" "$source_dir" "$user_dir" "$shipped_dir" "$TEST_ROOT/bin"

cp "$ROOT/themes/monarch/1-monarch.png" "$source_dir/first.png"
cp "$ROOT/themes/monarch/2-moon.jpg" "$source_dir/second.jpg"
cp "$ROOT/themes/monarch/1-monarch.png" "$user_dir/imported.png"
cp "$ROOT/themes/monarch/1-monarch.png" "$user_dir/legacy.png"
cp "$ROOT/themes/monarch/1-monarch.png" "$shipped_dir/legacy.png"
ln -s "$source_dir/first.png" "$farm/first.png"
ln -s "$source_dir/second.jpg" "$farm/second.jpg"
ln -s "$user_dir/imported.png" "$farm/imported.png"
ln -s "$user_dir/legacy.png" "$farm/legacy.png"

cat >"$TEST_ROOT/bin/noctalia" <<EOF
#!/bin/bash
if [[ \${1:-} == msg && \${2:-} == wallpaper-get ]]; then
  echo "$source_dir/second.jpg"
elif [[ \${1:-} == msg && \${2:-} == color-scheme-get ]]; then
  echo "custom Monarch"
fi
EOF
cat >"$TEST_ROOT/bin/magick" <<'EOF'
#!/bin/bash
source=${1%\[0\]}
cp "$source" "${@: -1}"
EOF
chmod +x "$TEST_ROOT/bin/noctalia" "$TEST_ROOT/bin/magick"

output=$("$ROOT/bin/monarch-theme-background-list")
expected=$(printf 'false\tfirst.png\t%s\nfalse\timported.png\t%s\nfalse\tlegacy.png\t%s\ntrue\tsecond.jpg\t%s' "$source_dir/first.png" "$user_dir/imported.png" "$user_dir/legacy.png" "$source_dir/second.jpg")
[[ $(cut -f1-3 <<<"$output") == "$expected" ]]
while IFS=$'\t' read -r _current name _path thumbnail removable; do
  [[ -f $thumbnail ]]
  [[ $removable == "$([[ $name == imported.png ]] && echo true || echo false)" ]]
done <<<"$output"

printf 'ok\n'
