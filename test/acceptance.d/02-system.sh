#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base.sh"

runtime=$(realpath -e -- "$MONARCH_PATH") || fail "installed runtime resolves"
[[ $runtime != "$ROOT" ]] || fail "acceptance uses the installed tree, not its test checkout"
[[ $(realpath -e -- /usr/bin/monarch) == "$runtime/bin/monarch" ]] ||
  fail "/usr/bin/monarch resolves into the installed runtime"
bad_runtime=$(find "$runtime" -xdev \( ! -user root -o -perm /022 \) -print -quit)
[[ -z $bad_runtime ]] || fail "installed runtime is root-owned and not writable by users" "$bad_runtime"
pass "acceptance uses a protected installed runtime"

manifest="$runtime/install/monarch-base.packages"
[[ -f $manifest ]] || fail "installed package manifest exists" "$manifest"
missing=()
while IFS= read -r package; do
  [[ -z $package || $package == \#* ]] && continue
  pacman -Q "$package" >/dev/null 2>&1 || missing+=("$package")
done <"$manifest"
((${#missing[@]} == 0)) || fail "all Monarch packages are installed" "${missing[*]}"
pass "all Monarch packages are installed"

for unit in cups.service avahi-daemon.service docker.socket NetworkManager.service \
  power-profiles-daemon.service sddm.service systemd-resolved.service ufw.service; do
  systemctl is-enabled --quiet "$unit" || fail "core services are enabled" "$unit"
done
pass "core services are enabled"

for unit in NetworkManager.service sddm.service systemd-resolved.service ufw.service; do
  systemctl is-active --quiet "$unit" || fail "critical services are running" "$unit"
done
pass "critical services are running"

[[ -s $HOME/.config/niri/config.kdl ]] || fail "Niri user configuration exists"
[[ -s $HOME/.config/noctalia/config.toml ]] || fail "Noctalia user configuration exists"
[[ -e $HOME/.local/state/noctalia/.setup-complete ]] || fail "Noctalia setup is complete"
[[ $(monarch-default-terminal) == "alacritty" ]] || fail "Alacritty is the default terminal"
[[ $(xdg-mime query default inode/directory) == "org.gnome.Nautilus.desktop" ]] ||
  fail "Nautilus handles directories"
pass "desktop defaults and user state are provisioned"

command -v docker >/dev/null || fail "Docker CLI is installed"
if id -nG | grep -qw docker || timeout 10 docker info >/dev/null 2>&1; then
  fail "Docker remains privileged until the user opts in"
fi
pass "Docker remains privileged until the user opts in"
