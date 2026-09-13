#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

stub_bin="$test_dir/bin"
home="$test_dir/home"
sudo_calls="$test_dir/sudo-calls"
target_calls="$test_dir/target-calls"
systemd_calls="$test_dir/systemd-calls"
mkdir -p "$stub_bin" "$home"

cat >"$stub_bin/id" <<'STUB'
#!/bin/bash
case "$1" in
  -nG) printf '%s\n' "${STUB_GROUPS:-wheel}" ;;
  -un) /usr/bin/id -un ;;
  *) /usr/bin/id "$@" ;;
esac
STUB

cat >"$stub_bin/getent" <<'STUB'
#!/bin/bash
if [[ $1 == group && $2 == docker && ${STUB_DOCKER_GROUP:-true} == true ]]; then
  printf 'docker:x:968:\n'
else
  exit 2
fi
STUB

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
printf '<%s>\n' "$@" >>"${SUDO_CALLS:?}"

if [[ $1 == /usr/bin/systemctl ]]; then
  exit 0
fi

while [[ $1 != /usr/bin/env ]]; do shift; done
exec "$@"
STUB

cat >"$stub_bin/docker-target" <<'STUB'
#!/bin/bash
printf '%s\t%s\t%s\n' "${DOCKER_HOST:-}" "${DOCKER_CONTEXT-unset}" "$*" >>"${TARGET_CALLS:?}"
STUB

cat >"$stub_bin/systemd-run" <<'STUB'
#!/bin/bash
printf '<%s>\n' "$@" >"${SYSTEMD_CALLS:?}"
STUB

cat >"$stub_bin/xdg-terminal-exec" <<'STUB'
#!/bin/bash
exit 0
STUB

chmod +x "$stub_bin"/*

sudo_check="$ROOT/bin/monarch-sudo-docker"
session="$ROOT/bin/monarch-launch-docker-session"
reachable_socket="$test_dir/reachable.sock"
blocked_socket="$test_dir/blocked.sock"
touch "$reachable_socket" "$blocked_socket"
chmod 600 "$reachable_socket"
chmod 400 "$blocked_socket"

run_check() {
  STUB_GROUPS="$2" MONARCH_DOCKER_SOCKET="$1" PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$sudo_check" "${3:-}"
}

run_check "$blocked_socket" wheel || fail "an inaccessible socket must require authentication"
if run_check "$reachable_socket" wheel; then
  fail "an accessible socket must use the current session"
fi
pass "runtime access follows the socket rather than configured groups"

if run_check "$blocked_socket" "wheel docker" --configured; then
  fail "configured Docker membership must select removal"
fi
run_check "$reachable_socket" wheel --configured || fail "an account outside docker must select setup"
pass "configured access follows account membership rather than the current session"

status=0
run_check "$reachable_socket" wheel --invalid >/dev/null 2>&1 || status=$?
(( status == 2 )) || fail "an invalid Docker access query must exit 2"
pass "invalid Docker access queries fail distinctly"

run_session() {
  rm -f "$sudo_calls" "$target_calls"
  HOME="$home" PATH="$stub_bin:$ROOT/bin:$PATH" MONARCH_DOCKER_SOCKET="$1" \
    SUDO_CALLS="$sudo_calls" TARGET_CALLS="$target_calls" STUB_DOCKER_GROUP="${2:-true}" \
    DOCKER_CONTEXT=remote "$session" docker-target one "two words"
}

run_session "$reachable_socket"
[[ ! -e $sudo_calls ]] || fail "direct Docker access unexpectedly invoked sudo"
grep -qxF $'\tremote\tone two words' "$target_calls" || fail "direct Docker access changed the caller environment"
pass "a session with socket access launches directly"

run_session "$blocked_socket"
uid=$(/usr/bin/id -u)
gid=$(/usr/bin/id -g)
groups=$(/usr/bin/id -G "$USER" | tr ' ' ',')
[[ ,$groups, == *,968,* ]] || groups+=",968"
grep -qxF "<--reuid=$uid>" "$sudo_calls" ||
  fail "temporary Docker access did not drop back to the invoking account"
grep -qxF "<--regid=$gid>" "$sudo_calls" ||
  fail "temporary Docker access did not preserve the invoking primary group"
grep -qxF "<--groups=$groups>" "$sudo_calls" ||
  fail "temporary Docker access did not preserve normal groups and add docker"
grep -qxF '<--inh-caps=-all>' "$sudo_calls" ||
  fail "temporary Docker access did not clear inheritable capabilities"
grep -qxF "unix://$blocked_socket"$'\tunset\tone two words' "$target_calls" ||
  fail "temporary Docker access did not pin the rootful socket and clear the context"
pass "an authenticated session grants only transient docker-group access"

rm -f "$sudo_calls" "$target_calls"
status=0
HOME="$home" PATH="$stub_bin:$ROOT/bin:$PATH" MONARCH_DOCKER_SOCKET="$blocked_socket" \
  SUDO_CALLS="$sudo_calls" TARGET_CALLS="$target_calls" STUB_DOCKER_GROUP=false \
  "$session" docker-target >/dev/null 2>&1 || status=$?
(( status == 1 )) || fail "a missing docker group must stop before sudo"
[[ ! -e $sudo_calls ]] || fail "a missing docker group still invoked sudo"
pass "temporary access fails closed when the docker group is unavailable"

terminal="$ROOT/bin/monarch-launch-docker-terminal"
HOME="$home" PATH="$stub_bin:$ROOT/bin:$PATH" SYSTEMD_CALLS="$systemd_calls" \
  "$terminal" --app-id=org.monarch.pentest --title="Pentest tools" docker-target "two words"

expected=$'<--user>\n<--scope>\n<--slice=app-graphical.slice>\n<--quiet>\n<--collect>\n<--same-dir>\n<--expand-environment=no>\n<-->\n'
expected+="<$stub_bin/xdg-terminal-exec>"$'\n<--app-id=org.monarch.pentest>\n<--title=Pentest tools>\n<-e>\n'
expected+="<$ROOT/bin/monarch-launch-docker-session>"$'\n<docker-target>\n<two words>'
[[ $(<"$systemd_calls") == "$expected" ]] || fail "the Docker terminal did not preserve its scope and arguments"
pass "Docker terminals inherit access through a caller-owned systemd scope"
