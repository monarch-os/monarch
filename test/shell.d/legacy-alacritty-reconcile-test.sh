#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

script="$ROOT/install/reconcile/schema/1-to-2/alacritty.sh"
fixture_dir="$ROOT/test/fixtures/alacritty-v4"
fixture_names=(
  d868275e-final.toml
  bd7b475b-final.toml
  2e4723fa-final.toml
  6905f31f-final.toml
  e1ae3efc-final.toml
)
fixture_checksums=(
  5a15d6a6321988ba67917136157344ebe61c687997ddb2c8b03cbcc64c03daf3
  5739e8e39c949b5a2a6a92e53a4f1b94a7a42863b76329e49c19c4b6f88b6c42
  c2e6ff8f390fe2357e29353f3d8469a9df45fd277f8ce1ddc047de26eb3494d6
  89c50d171ea925d9b1c854428f6e56ce2ddc4a13702a55d5e97cf7da7cd73164
  68452eefa068191e149defa9ddf16bfce0d7c69393376afc293495e30a9937e4
)

run_reconcile() {
  HOME="$1" MONARCH_PATH="$ROOT" bash "$script"
}

for index in "${!fixture_names[@]}"; do
  fixture="$fixture_dir/${fixture_names[$index]}"
  [[ $(sha256sum "$fixture" | cut -d' ' -f1) == "${fixture_checksums[$index]}" ]] ||
    fail "${fixture_names[$index]} no longer matches its V4 provenance"

  stock_home="$test_tmp/stock-$index"
  stock_config="$stock_home/.config/alacritty/alacritty.toml"
  mkdir -p "${stock_config%/*}"
  cp "$fixture" "$stock_config"

  run_reconcile "$stock_home"
  cmp "$ROOT/config/alacritty/alacritty.toml" "$stock_config" ||
    fail "${fixture_names[$index]} was not adopted"
  run_reconcile "$stock_home"
  cmp "$ROOT/config/alacritty/alacritty.toml" "$stock_config" ||
    fail "${fixture_names[$index]} changed on a second reconciliation"
done
pass "every stock V4 Alacritty lineage adopts the packaged default idempotently"

fixture="$fixture_dir/e1ae3efc-final.toml"

custom_home="$test_tmp/custom-home"
custom_config="$custom_home/.config/alacritty/alacritty.toml"
mkdir -p "${custom_config%/*}"
sed 's/^size = 9$/size = 11/' "$fixture" >"$custom_config"
cp "$custom_config" "$test_tmp/custom-expected.toml"

run_reconcile "$custom_home"
cmp "$test_tmp/custom-expected.toml" "$custom_config" ||
  fail "a customized V4 Alacritty config was overwritten"
pass "customized V4 Alacritty config remains user-owned"

symlink_home="$test_tmp/symlink-home"
symlink_config="$symlink_home/.config/alacritty/alacritty.toml"
symlink_source="$test_tmp/symlink-source.toml"
mkdir -p "${symlink_config%/*}"
cp "$fixture" "$symlink_source"
ln -s "$symlink_source" "$symlink_config"

run_reconcile "$symlink_home"
[[ -L $symlink_config && $(readlink "$symlink_config") == $symlink_source ]] ||
  fail "a user-managed Alacritty symlink was replaced"
cmp "$fixture" "$symlink_source" ||
  fail "the target of a user-managed Alacritty symlink was modified"
pass "user-managed Alacritty symlink remains untouched"
