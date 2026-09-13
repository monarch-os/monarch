#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

script="$ROOT/install/reconcile/schema/1-to-2/kitty.sh"
fixture="$ROOT/test/fixtures/kitty-v4/stock.conf"
host_default="$ROOT/config/kitty/kitty.conf"
exegol_default="$ROOT/default/exegol/my-resources/setup/kitty/kitty.conf"

if rg -q '^\s*allow_remote_control\s+yes\s*$' "$host_default" "$exegol_default"; then
  fail "Kitty defaults permit remote control"
fi
pass "Kitty defaults disable remote control"

[[ $(sha256sum "$fixture" | cut -d' ' -f1) == 0cb2131c21332a602db00fb53a16c4295c76541e0d7ea54f421212493356a67a ]] ||
  fail "stock Kitty fixture no longer matches its V4 provenance"

run_reconcile() {
  HOME="$1" MONARCH_PATH="$ROOT" bash "$script"
}

stock_home="$test_tmp/stock-home"
stock_config="$stock_home/.config/kitty/kitty.conf"
mkdir -p "${stock_config%/*}"
cp "$fixture" "$stock_config"

run_reconcile "$stock_home"
cmp "$host_default" "$stock_config" || fail "stock V4 Kitty config was not adopted"
run_reconcile "$stock_home"
cmp "$host_default" "$stock_config" || fail "stock Kitty config changed after reconciliation"
pass "stock V4 Kitty config adopts the safe packaged default idempotently"

custom_home="$test_tmp/custom-home"
custom_config="$custom_home/.config/kitty/kitty.conf"
mkdir -p "${custom_config%/*}"
sed 's/^font_size        9.0$/font_size        11.0/' "$fixture" >"$custom_config"
cp "$custom_config" "$test_tmp/custom-expected.conf"

run_reconcile "$custom_home"
cmp "$test_tmp/custom-expected.conf" "$custom_config" ||
  fail "a customized V4 Kitty config was overwritten"
pass "customized V4 Kitty config remains user-owned"

symlink_home="$test_tmp/symlink-home"
symlink_config="$symlink_home/.config/kitty/kitty.conf"
symlink_source="$test_tmp/symlink-source.conf"
mkdir -p "${symlink_config%/*}"
cp "$fixture" "$symlink_source"
ln -s "$symlink_source" "$symlink_config"

run_reconcile "$symlink_home"
[[ -L $symlink_config && $(readlink "$symlink_config") == $symlink_source ]] ||
  fail "a user-managed Kitty symlink was replaced"
cmp "$fixture" "$symlink_source" ||
  fail "the target of a user-managed Kitty symlink was modified"
pass "user-managed Kitty symlink remains untouched"
