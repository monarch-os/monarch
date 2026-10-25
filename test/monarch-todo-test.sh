#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" MONARCH_PATH="$ROOT" PATH="$TMP/bin:$ROOT/bin:$PATH"
mkdir -p "$HOME/.config/niri" "$TMP/bin"

cat >"$TMP/bin/monarch-todo" <<'EOF'
#!/bin/bash
[[ ${TODO_OLD:-false} != "true" ]] || exit 1
[[ ${TODO_FAIL_SETUP:-false} != "true" || $* != "setup-desktop" ]] || exit 2
printf '%s\n' "$*" >>"$HOME/todo.log"
EOF
cat >"$TMP/bin/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$HOME/systemctl.log"
EOF
cat >"$TMP/bin/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
cat >"$TMP/bin/pacman" <<'EOF'
#!/bin/bash
[[ $* == "-Q monarch-todo" ]] || exit 2
[[ ${TODO_PACKAGE_MISSING:-false} != "true" ]] || exit 1
printf 'monarch-todo %s\n' "${TODO_PACKAGE_VERSION:-0.2.0-1}"
EOF
cat >"$TMP/bin/vercmp" <<'EOF'
#!/bin/bash
[[ $2 == "0.2.0" ]] || exit 2
[[ ${VERCMP_FAIL:-false} != "true" ]] || exit 3
printf '%s\n' "$*" >>"$HOME/vercmp.log"
case $1 in
  0.1.2-1 | 0.2.0rc1-1) echo -1 ;;
  0.2.0) echo 0 ;;
  0.2.0-1 | 0.2.0-12 | 0.2.1-1 | 0.10.0-1 | 1:0.2.0-1) echo 1 ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$TMP/bin/"*
source "$ROOT/install/reconcile/todo.sh"

TODO_PACKAGE_MISSING=true monarch_reconcile_todo "$ROOT"
[[ ! -e $HOME/todo.log && ! -e $HOME/.config/niri/monarch-todo.kdl ]]
for version in 0.1.2-1 0.2.0rc1-1; do
  TODO_PACKAGE_VERSION="$version" monarch_reconcile_todo "$ROOT"
  [[ ! -e $HOME/todo.log && ! -e $HOME/.config/niri/monarch-todo.kdl ]]
done
if VERCMP_FAIL=true monarch_reconcile_todo "$ROOT"; then
  echo "version comparison failure was hidden" >&2
  exit 1
fi
[[ ! -e $HOME/todo.log ]]
echo "ok - absent/older packages never execute the backend; comparison errors stop reconciliation"

TODO_OLD=true monarch_reconcile_todo "$ROOT"
[[ ! -f $HOME/.local/share/applications/Todo.desktop ]]
echo "ok - old backends keep the old integration"

printf '%s\n' 'custom old todo binding' >"$HOME/.config/niri/monarch-todo.kdl"
monarch_reconcile_todo "$ROOT"
monarch_reconcile_todo "$ROOT"
grep -Fqx 'setup-desktop' "$HOME/todo.log"
[[ $(grep -c 'include "./monarch-todo.kdl"' "$HOME/.config/niri/user.kdl") == "1" ]]
[[ $(<"$HOME/.config/niri/monarch-todo.kdl.pre-panel") == "custom old todo binding" ]]
grep -Fq 'spawn "monarch-todo" "panel"' "$HOME/.config/niri/monarch-todo.kdl"
! grep -q 'spawn-at-startup\|window-rule' "$HOME/.config/niri/monarch-todo.kdl"
[[ ! -e $HOME/.local/share/applications/Todo.desktop ]]
[[ ! -e $HOME/.config/systemd/user/monarch-todo-reminders.service ]]
[[ ! -e $HOME/.local/share/noctalia/plugins/monarch-todo ]]
echo "ok - Monarch delegates optional integration and only owns the shortcut"

for version in 0.2.0 0.2.0-12 0.2.1-1 0.10.0-1 1:0.2.0-1; do
  before=$(grep -c '^setup-desktop$' "$HOME/todo.log")
  TODO_PACKAGE_VERSION="$version" monarch_reconcile_todo "$ROOT"
  [[ $(grep -c '^setup-desktop$' "$HOME/todo.log") == "$((before + 1))" ]]
  [[ $(tail -n 1 "$HOME/vercmp.log") == "$version 0.2.0" ]]
done
echo "ok - 0.2.0 and newer package versions use vercmp, including releases and epochs"

[[ ! -e $ROOT/bin/monarch-launch-todo ]]
echo "ok - shortcut invokes the package directly without a Monarch launcher"

printf '%s\n' 'keep on failure' >"$HOME/.config/niri/monarch-todo.kdl"
if TODO_FAIL_SETUP=true monarch_reconcile_todo "$ROOT"; then
  echo "setup failure was hidden" >&2
  exit 1
fi
[[ $(<"$HOME/.config/niri/monarch-todo.kdl") == "keep on failure" ]]
echo "ok - failed replacement activation preserves the old shortcut"

cat >"$TMP/bin/monarch-pkg-add" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$HOME/packages.log"
exit "${PKG_STATUS:-0}"
EOF
chmod +x "$TMP/bin/monarch-pkg-add"
"$ROOT/bin/monarch-install-todo"
grep -Fqx 'monarch-todo' "$HOME/packages.log"
grep -Fq 'spawn "monarch-todo" "panel"' "$HOME/.config/niri/monarch-todo.kdl"
! grep -q 'install/reconcile' "$ROOT/bin/monarch-install-todo"
echo "ok - installer uses current setup without depending on reconciliation"
mkdir -p "$TMP/untrusted/default/i18n" "$TMP/untrusted/install/helpers"
touch "$TMP/untrusted/default/i18n/i18n.py"
printf '%s\n' 'touch "$HOME/untrusted-helper-ran"' >"$TMP/untrusted/install/helpers/todo.sh"
MONARCH_PATH="$TMP/untrusted" "$ROOT/bin/monarch-install-todo"
[[ ! -e $HOME/untrusted-helper-ran ]]
echo "ok - installer ignores environment-selected helpers after package installation"

before=$(wc -l <"$HOME/todo.log")
if PKG_STATUS=1 "$ROOT/bin/monarch-install-todo"; then
  echo "package failure was hidden" >&2
  exit 1
fi
[[ $(wc -l <"$HOME/todo.log") == "$before" ]]
if TODO_OLD=true "$ROOT/bin/monarch-install-todo"; then
  echo "installer silently accepted an unsupported backend" >&2
  exit 1
fi
echo "ok - fresh install fails explicitly on package/setup errors"

cat >"$TMP/bin/monarch-pkg-drop" <<'EOF'
#!/bin/bash
exit 9
EOF
chmod +x "$TMP/bin/monarch-pkg-drop"
printf '%s\n' 'keep shortcut if pacman fails' >"$HOME/.config/niri/monarch-todo.kdl"
if "$ROOT/bin/monarch-remove-todo"; then
  echo "failed package removal reported success" >&2
  exit 1
fi
[[ $(<"$HOME/.config/niri/monarch-todo.kdl") == "keep shortcut if pacman fails" ]]
[[ $(tail -n 1 "$HOME/todo.log") == "setup-desktop" ]]
echo "ok - failed removal restores desktop integration and retains the shortcut"
