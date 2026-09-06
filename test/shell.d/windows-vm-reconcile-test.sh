#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export MONARCH_WINDOWS_DIR="$test_tmp/runtime"
set -- help
source "$ROOT/bin/monarch-windows-vm" >/dev/null

(
  set --
  source "$ROOT/bin/monarch-windows-vm"
  declare -F sync_vm_container >/dev/null
) >"$test_tmp/source-output"
[[ ! -s $test_tmp/source-output ]] || fail "sourcing the Windows VM helper invoked its command dispatcher"
pass "the packaged Windows VM helper can be sourced without command arguments or dispatcher output"

CALLER_HOME="$test_tmp/home/alice"
CALLER_UID=1000
CALLER_GID=1000
CALLER_DATA_ROOT="$RUNTIME_DIR/mounts/users/$CALLER_UID"
EXPECTED_STORAGE="$CALLER_DATA_ROOT/storage"
EXPECTED_SHARED="$CALLER_DATA_ROOT/shared"
LEGACY_STORAGE="$CALLER_HOME/.windows"
LEGACY_SHARED="$CALLER_HOME/Windows"
OLD_EXPECTED_STORAGE="$test_tmp/home/.monarch-windows/users/$CALLER_UID/storage"
OLD_EXPECTED_SHARED="$test_tmp/home/.monarch-windows/users/$CALLER_UID/shared"
LEGACY_COMPOSE_FILE="$CALLER_HOME/.config/windows/docker-compose.yml"
CREDENTIALS_FILE="$CALLER_HOME/.config/windows/credentials"
mkdir -p "$LEGACY_STORAGE" "$LEGACY_SHARED" "$EXPECTED_STORAGE" "$EXPECTED_SHARED" \
  "$OLD_EXPECTED_STORAGE" "$OLD_EXPECTED_SHARED" "$CALLER_HOME/.config/windows"

fake_json="$test_tmp/container.json"
fake_trace="$test_tmp/trace"
fake_mutations="$test_tmp/mutations"
fake_initial_id=$(printf 'a%.0s' {1..64})
fake_recreated_id=$(printf 'b%.0s' {1..64})
fake_other_id=$(printf 'c%.0s' {1..64})

resolve_caller() { :; }
assert_mounts_safe() { [[ $fake_failure != mounts ]]; }
mounts_ready() { [[ $fake_failure != mounts ]]; }

write_container() {
  local status=$1 origin=$2 profile=$3 id=${4:-$fake_initial_id}
  local workdir storage shared restart protect
  case "$origin" in
  legacy)
    workdir="$CALLER_HOME/.config/windows"
    storage=$LEGACY_STORAGE
    shared=$LEGACY_SHARED
    ;;
  old)
    workdir=$RUNTIME_DIR
    storage=$OLD_EXPECTED_STORAGE
    shared=$OLD_EXPECTED_SHARED
    ;;
  protected)
    workdir=$RUNTIME_DIR
    storage=$EXPECTED_STORAGE
    shared=$EXPECTED_SHARED
    ;;
  esac
  if [[ $profile == safe ]]; then
    restart=no
    protect=Y
  else
    restart=unless-stopped
    protect=N
  fi
  jq -n --arg id "$id" --arg status "$status" --arg workdir "$workdir" \
    --arg storage "$storage" --arg shared "$shared" --arg restart "$restart" \
    --arg protect "$protect" '[{
      Id: $id,
      Name: "/monarch-windows",
      Config: {
        Image: "dockurr/windows",
        Env: ["PROTECT=" + $protect, "USERNAME=alice", "PASSWORD=example"],
        Labels: {
          "com.docker.compose.project": "windows",
          "com.docker.compose.service": "windows",
          "com.docker.compose.project.working_dir": $workdir,
          "com.docker.compose.project.config_files": ($workdir + "/docker-compose.yml")
        }
      },
      HostConfig: {RestartPolicy: {Name: $restart, MaximumRetryCount: 0}},
      State: {
        Status: $status,
        Running: ($status == "running"),
        Restarting: ($status == "restarting"),
        StartedAt: (if $status == "created" then "0001-01-01T00:00:00Z" else "2026-09-05T00:00:00Z" end)
      },
      Mounts: [
        {Type: "bind", Source: $storage, Destination: "/storage", RW: true},
        {Type: "bind", Source: $shared, Destination: "/shared", RW: true}
      ]
    }]' >"$fake_json"
}

change_container() {
  jq "$@" "$fake_json" >"$fake_json.next"
  mv "$fake_json.next" "$fake_json"
}

add_replacement() {
  local original_json original_id
  original_json=$(<"$fake_json")
  original_id=$(jq -r '.[] | select(.Name == "/monarch-windows") | .Id' "$fake_json")
  write_container created protected safe "$fake_recreated_id"
  change_container --arg name "/${original_id:0:12}_monarch-windows" '
    .[0].Name = $name |
    .[0].Config.Labels["com.docker.compose.replace"] = "monarch-windows"'
  if [[ $1 == keep ]]; then
    change_container --argjson original "$original_json" '$original + .'
  fi
}

reset_case() {
  fake_failure=
  fake_compose_effect=converge
  fake_extra_container=0
  : >"$fake_trace"
  : >"$fake_mutations"
  rm -f "$RUNTIME_DIR/reconcile-pending"
  write_container "${1:-running}" "${2:-legacy}" "${3:-legacy}"
}

docker() {
  printf 'docker %s\n' "$*" >>"$fake_trace"
  case "${1:-} ${2:-}" in
  "container ls")
    [[ $fake_failure != daemon ]] || return 1
    [[ " $* " == *" --all "* && " $* " == *" --no-trunc "* ]] || return 1
    [[ " $* " == *" --format {{.ID}} "* ]] || return 1
    if [[ " $* " == *' --filter name=^/monarch-windows$ '* ]]; then
      jq -r '.[] | select(.Name == "/monarch-windows") | .Id' "$fake_json"
    elif [[ " $* " == *" --filter label=com.docker.compose.project=windows "* &&
      " $* " == *" --filter label=com.docker.compose.service=windows "* ]]; then
      [[ $fake_failure != service_query ]] || return 1
      jq -r '.[] | select(.Config.Labels["com.docker.compose.project"] == "windows" and
        .Config.Labels["com.docker.compose.service"] == "windows") | .Id' "$fake_json"
      ((fake_extra_container == 0)) || printf '%s\n' "$fake_other_id"
    else
      return 1
    fi
    ;;
  "container inspect")
    [[ $fake_failure != inspect ]] || return 1
    [[ $# == 3 ]] && jq -e --arg id "$3" 'any(.[]; .Id == $id)' "$fake_json" >/dev/null || return 1
    if [[ $fake_failure == postinspect ]] && rg -q '^compose ' "$fake_mutations"; then
      return 1
    fi
    if [[ $fake_failure == malformed ]]; then
      printf 'not-json\n'
    else
      jq --arg id "$3" 'map(select(.Id == $id))' "$fake_json"
    fi
    ;;
  "container update")
    [[ $# == 4 && $3 == --restart=no ]] &&
      jq -e --arg id "$4" 'any(.[]; .Id == $id)' "$fake_json" >/dev/null || return 1
    printf 'docker %s\n' "$*" >>"$fake_mutations"
    [[ $fake_failure != update ]] || return 1
    change_container --arg id "$4" 'map(if .Id == $id then .HostConfig.RestartPolicy.Name = "no" else . end)'
    ;;
  "container rm")
    [[ $# == 3 ]] && jq -e --arg id "$3" 'any(.[]; .Id == $id)' "$fake_json" >/dev/null || return 1
    printf 'docker %s\n' "$*" >>"$fake_mutations"
    [[ $fake_failure != remove_replacement ]] || return 1
    change_container --arg id "$3" 'map(select(.Id != $id))'
    ;;
  "container rename")
    [[ $# == 4 && $4 == monarch-windows ]] &&
      jq -e --arg id "$3" 'any(.[]; .Id == $id)' "$fake_json" >/dev/null || return 1
    printf 'docker %s\n' "$*" >>"$fake_mutations"
    [[ $fake_failure != rename_replacement ]] || return 1
    change_container --arg id "$3" 'map(if .Id == $id then .Name = "/monarch-windows" else . end)'
    ;;
  "inspect --format={{.State.Status}}")
    jq -r '.[0].State.Status // empty' "$fake_json"
    ;;
  "inspect --format={{.State.StartedAt}}")
    printf '2026-09-05T00:00:00Z\n'
    ;;
  "logs --since")
    printf 'Windows started successfully\n'
    ;;
  *)
    printf 'Unexpected Docker call: %s\n' "$*" >&2
    return 1
    ;;
  esac
}

docker-compose() {
  [[ $# -ge 7 && $1 == --project-name && $2 == windows && $3 == --env-file &&
    $4 == /dev/null && $5 == -f && $6 == "$COMPOSE_FILE" && $PWD == "$RUNTIME_DIR" ]] || return 1
  shift 6
  printf 'compose %s\n' "$*" >>"$fake_trace"
  printf 'compose %s\n' "$*" >>"$fake_mutations"
  [[ $fake_failure != compose ]] || return 1
  local state id=$fake_initial_id
  case "$*" in
  down)
    [[ $fake_failure != down ]] || return 1
    printf '[]\n' >"$fake_json"
    return 0
    ;;
  "up -d --no-deps --timeout 120 windows" | "up -d --no-deps --timeout 120 --force-recreate windows") state=running ;;
  "create --no-build --pull never windows" | "create --no-build --pull never --force-recreate windows") state=created ;;
  *) return 1 ;;
  esac
  case "$fake_compose_effect" in
  replacement_pair) add_replacement keep; return 1 ;;
  replacement_only) add_replacement only; return 1 ;;
  replacement_stopped_original)
    change_container '.[0].State.Status = "exited" | .[0].State.Running = false'
    add_replacement keep
    return 1
    ;;
  esac
  if [[ $fake_compose_effect == stale ]]; then
    return 0
  fi
  if [[ " $* " == *" --force-recreate "* ]] || [[ $(jq length "$fake_json") == 0 ]]; then
    [[ $(jq -r '.[0].Id // empty' "$fake_json") != "$fake_initial_id" ]] || id=$fake_recreated_id
    write_container "$state" protected safe "$id"
  else
    change_container --arg state "$state" '.[0].State.Status = $state | .[0].State.Running = ($state == "running")'
  fi
  case "$fake_compose_effect" in
  start_failure)
    change_container '.[0].State.Status = "created" | .[0].State.Running = false |
      .[0].State.StartedAt = "0001-01-01T00:00:00Z"'
    return 1
    ;;
  stopped) change_container '.[0].State.Status = "exited" | .[0].State.Running = false' ;;
  running) change_container '.[0].State.Status = "running" | .[0].State.Running = true' ;;
  unprotected) change_container '.[0].Config.Env = ["PROTECT=N"]' ;;
  restart) change_container '.[0].HostConfig.RestartPolicy.Name = "always"' ;;
  foreign) change_container '.[0].Config.Labels["com.docker.compose.project"] = "other"' ;;
  missing) printf '[]\n' >"$fake_json" ;;
  esac
}

assert_hardened() {
  jq -e --arg storage "$EXPECTED_STORAGE" --arg shared "$EXPECTED_SHARED" '
    length == 1 and
    (.[0] | .HostConfig.RestartPolicy.Name == "no" and
      ([.Config.Env[] | select(startswith("PROTECT="))] == ["PROTECT=Y"]) and
      (.Mounts | length == 2 and
        any(.[]; .Type == "bind" and .Source == $storage and .Destination == "/storage") and
        any(.[]; .Type == "bind" and .Source == $shared and .Destination == "/shared")))
  ' "$fake_json" >/dev/null || fail "$1 did not harden the runtime container"
}

assert_mutation() {
  rg -q -x -F -- "$1" "$fake_mutations" || fail "missing mutation: $1" "$(<"$fake_mutations")"
}

assert_no_mutations() {
  [[ ! -s $fake_mutations ]] || fail "$1 mutated Docker" "$(<"$fake_mutations")"
}

for state in running restarting; do
  reset_case "$state"
  __priv_reconcile || fail "$state legacy reconciliation failed"
  assert_hardened "$state legacy reconciliation"
  [[ $(jq -r '.[0].State.Status' "$fake_json") == running ]] || fail "$state VM was not preserved as active"
  [[ $(head -n1 "$fake_mutations") == "docker container update --restart=no $fake_initial_id" ]] ||
    fail "$state reconciliation did not disable automatic restart before Compose"
  assert_mutation 'compose up -d --no-deps --timeout 120 --force-recreate windows'
  [[ $(jq -r '.[0].Id' "$fake_json") == "$fake_recreated_id" ]] || fail "fixture did not recreate the container"
done
pass "running and restarting legacy containers are hardened before remaining active"

: >"$fake_mutations"
__priv_reconcile || fail "second reconciliation failed"
assert_hardened "second reconciliation"
rg -q -- '--force-recreate' "$fake_mutations" && fail "second reconciliation forced another recreation"
rg -q '^compose ' "$fake_mutations" && fail "second reconciliation invoked Compose despite unchanged security settings"
[[ $(jq -r '.[0].Id' "$fake_json") == "$fake_recreated_id" ]] || fail "second reconciliation changed the container ID"
pass "repeated reconciliation preserves an already hardened container"

for state in created exited; do
  reset_case "$state"
  __priv_reconcile || fail "$state legacy reconciliation failed"
  assert_hardened "$state legacy reconciliation"
  [[ $(jq -r '.[0].State.Running' "$fake_json") == false ]] || fail "$state VM was started by reconciliation"
  assert_mutation 'compose create --no-build --pull never --force-recreate windows'
  rg -q '^compose up ' "$fake_mutations" && fail "$state reconciliation started the VM"
done
pass "created and exited legacy containers are hardened without booting or pulling an image"

reset_case
printf '[]\n' >"$fake_json"
__priv_reconcile || fail "absent VM reconciliation failed"
assert_no_mutations "absent VM reconciliation"
__priv_up || fail "explicit launch did not create an absent VM"
assert_hardened "absent VM launch"
assert_mutation 'compose up -d --no-deps --timeout 120 windows'
pass "reconciliation leaves an absent container absent while explicit launch starts it"

for origin in old protected; do
  reset_case running "$origin" legacy
  __priv_reconcile || fail "$origin runtime reconciliation failed"
  assert_hardened "$origin runtime reconciliation"
  assert_mutation 'compose up -d --no-deps --timeout 120 --force-recreate windows'
done
pass "first-generation and current anchors converge when runtime security settings drift"

for mutation in \
  '.[0].Config.Env = []' \
  '.[0].Config.Env = ["PROTECT=N"]' \
  '.[0].Config.Env = ["PROTECT=Y", "PROTECT=N"]'; do
  reset_case running protected safe
  change_container "$mutation"
  __priv_reconcile || fail "unprotected runtime with an already disabled restart policy did not reconcile"
  assert_hardened "unprotected runtime"
  assert_mutation 'compose up -d --no-deps --timeout 120 --force-recreate windows'
done
reset_case running legacy safe
__priv_reconcile || fail "legacy mounts with otherwise hardened settings did not reconcile"
assert_hardened "legacy mounts with hardened settings"
assert_mutation 'compose up -d --no-deps --timeout 120 --force-recreate windows'
pass "each runtime protection and mount invariant is checked independently of restart policy"

reset_case running legacy legacy
mkdir -p "$test_tmp/storage-target" "$test_tmp/shared-target"
mv "$LEGACY_STORAGE" "$LEGACY_STORAGE.saved"
mv "$LEGACY_SHARED" "$LEGACY_SHARED.saved"
ln -s "$test_tmp/storage-target" "$LEGACY_STORAGE"
ln -s "$test_tmp/shared-target" "$LEGACY_SHARED"
change_container --arg storage "$test_tmp/storage-target" --arg shared "$test_tmp/shared-target" \
  '.[0].Mounts[0].Source = $storage | .[0].Mounts[1].Source = $shared'
__priv_reconcile || fail "canonical legacy symlink targets were refused"
assert_hardened "canonical legacy symlink targets"
rm "$LEGACY_STORAGE" "$LEGACY_SHARED"
mv "$LEGACY_STORAGE.saved" "$LEGACY_STORAGE"
mv "$LEGACY_SHARED.saved" "$LEGACY_SHARED"
pass "recognized legacy symlink targets retain their data origin during migration"

for mutation in \
  '.[0].Name = "/unrelated"' \
  '.[0].Config.Image = "unrelated/image"' \
  '.[0].Config.Labels["com.docker.compose.project"] = "other"' \
  '.[0].Config.Labels["com.docker.compose.service"] = "other"' \
  'del(.[0].Config.Labels["com.docker.compose.project.working_dir"])' \
  '.[0].Config.Labels["com.docker.compose.project.working_dir"] = "/home/other/.config/windows"' \
  '.[0].Config.Labels["com.docker.compose.project.config_files"] = "/tmp/docker-compose.yml"' \
  '.[0].Config.Labels["com.docker.compose.project.config_files"] += ",/tmp/override.yml"' \
  '.[0].Mounts[0].Source = "/home/other/.windows"' \
  '.[0].Mounts[1].Source = "/"' \
  '.[0].Mounts[0].Type = "volume"' \
  '.[0].Mounts[1].Destination = "/storage"' \
  '.[0].Mounts += [{Type: "bind", Source: "/", Destination: "/host"}]'; do
  reset_case
  change_container "$mutation"
  if __priv_reconcile >/dev/null 2>&1; then
    fail "unrecognized container accepted: $mutation"
  fi
  assert_no_mutations "$mutation"
done
pass "unknown names, images, compose origins, owners, and mounts fail before Docker mutations"

reset_case
fake_extra_container=1
__priv_reconcile >/dev/null 2>&1 && fail "another container from the windows project/service was accepted"
assert_no_mutations "extra project/service container"
printf '[]\n' >"$fake_json"
__priv_up >/dev/null 2>&1 && fail "absent named VM hid another project/service container"
assert_no_mutations "unnamed project/service container"
pass "Compose cannot adopt a second container from the same project and service"

for failure in daemon service_query inspect malformed; do
  reset_case
  fake_failure=$failure
  __priv_reconcile >/dev/null 2>&1 && fail "$failure was treated as successful reconciliation"
  assert_no_mutations "$failure"
done
pass "daemon, discovery, and inspect failures remain retryable without Docker mutations"

reset_case
fake_failure=mounts
__priv_reconcile >/dev/null 2>&1 && fail "mount verification failure was ignored"
rg -q '^compose ' "$fake_mutations" && fail "Compose ran after mount verification failed"
fake_failure=
__priv_reconcile || fail "mount verification failure could not be retried"
assert_hardened "mount verification retry"
pass "mount verification failure prevents Compose and succeeds on retry"

reset_case
fake_failure=update
__priv_reconcile >/dev/null 2>&1 && fail "restart-policy update failure was ignored"
rg -q '^compose ' "$fake_mutations" && fail "Compose ran after restart-policy update failed"
fake_failure=
__priv_reconcile || fail "restart-policy update failure could not be retried"
assert_hardened "restart-policy retry"
pass "a failed restart-policy update prevents Compose and succeeds on retry"

for failure in compose postinspect; do
  reset_case
  fake_failure=$failure
  __priv_reconcile >/dev/null 2>&1 && fail "$failure was treated as successful reconciliation"
  fake_failure=
  __priv_reconcile || fail "$failure could not be retried"
  assert_hardened "$failure retry"
done
pass "Compose and final inspection failures propagate and can be retried"

for state in running exited; do
  reset_case "$state"
  fake_compose_effect=replacement_pair
  __priv_reconcile >/dev/null 2>&1 && fail "Compose failure with both original and replacement was ignored"
  [[ $(jq length "$fake_json") == 2 ]] || fail "fixture did not retain the original and replacement"
  [[ -f $RUNTIME_DIR/reconcile-pending ]] || fail "failed replacement lost the reconciliation journal"
  : >"$fake_mutations"
  fake_compose_effect=converge
  __priv_reconcile || fail "replacement pair could not be recovered on retry"
  assert_hardened "replacement pair retry"
  [[ $(head -n1 "$fake_mutations") == "docker container rm $fake_recreated_id" ]] ||
    fail "retry did not remove only the verified, never-started replacement first"
  [[ ! -e $RUNTIME_DIR/reconcile-pending ]] || fail "successful replacement retry left its journal"
  if [[ $state == running ]]; then
    [[ $(jq -r '.[0].State.Status' "$fake_json") == running ]] || fail "replacement retry forgot an active VM"
  else
    [[ $(jq -r '.[0].State.Running' "$fake_json") == false ]] || fail "replacement retry booted a stopped VM"
  fi
done
pass "a Compose failure leaving original and replacement recovers on retry without losing activity state"

reset_case running
fake_compose_effect=replacement_stopped_original
__priv_reconcile >/dev/null 2>&1 && fail "Compose failure after stopping the original was ignored"
[[ $(jq -r '.[0].State.Status' "$fake_json") == exited ]] || fail "fixture did not stop the original"
: >"$fake_mutations"
fake_compose_effect=converge
__priv_reconcile || fail "retry could not recover after Compose stopped the original"
assert_hardened "stopped original retry"
assert_mutation "docker container rm $fake_recreated_id"
[[ $(jq -r '.[0].State.Status' "$fake_json") == running ]] || fail "retry forgot the original was active before Compose stopped it"
[[ ! -e $RUNTIME_DIR/reconcile-pending ]] || fail "successful stopped-original retry left its journal"
pass "retry restores an active VM even when Compose already stopped its original container"

for state in running exited; do
  reset_case "$state"
  fake_compose_effect=replacement_only
  __priv_reconcile >/dev/null 2>&1 && fail "Compose failure leaving only a temporary replacement was ignored"
  [[ $(jq -r '.[0].Name' "$fake_json") == "/${fake_initial_id:0:12}_monarch-windows" ]] ||
    fail "fixture did not leave the temporary replacement alone"
  [[ -f $RUNTIME_DIR/reconcile-pending ]] || fail "orphan replacement lost the reconciliation journal"
  : >"$fake_mutations"
  fake_compose_effect=converge
  __priv_reconcile || fail "orphan replacement could not be recovered on retry"
  assert_hardened "orphan replacement retry"
  [[ $(head -n1 "$fake_mutations") == "docker container rename $fake_recreated_id monarch-windows" ]] ||
    fail "retry did not rename the verified orphan replacement"
  [[ $(jq -r '.[0].Name' "$fake_json") == /monarch-windows ]] || fail "recovered replacement retained its temporary name"
  [[ ! -e $RUNTIME_DIR/reconcile-pending ]] || fail "successful orphan retry left its journal"
  if [[ $state == running ]]; then
    [[ $(jq -r '.[0].State.Status' "$fake_json") == running ]] || fail "orphan replacement retry forgot an active VM"
    assert_mutation 'compose up -d --no-deps --timeout 120 windows'
  else
    [[ $(jq -r '.[0].State.Running' "$fake_json") == false ]] || fail "orphan replacement retry booted a stopped VM"
    rg -q '^compose up ' "$fake_mutations" && fail "stopped orphan recovery invoked Compose up"
  fi
done
pass "a verified orphan replacement is renamed and restores the activity state recorded before Compose failed"

reset_case running
fake_compose_effect=start_failure
__priv_reconcile >/dev/null 2>&1 && fail "Compose failure after recreation but before start was ignored"
[[ $(jq -r '.[0].State.Status' "$fake_json") == created ]] || fail "fixture did not simulate a failed start"
[[ -f $RUNTIME_DIR/reconcile-pending ]] || fail "failed start lost the reconciliation journal"
: >"$fake_mutations"
fake_compose_effect=converge
__priv_reconcile || fail "failed start could not be retried"
assert_hardened "failed start retry"
assert_mutation 'compose up -d --no-deps --timeout 120 windows'
[[ $(jq -r '.[0].State.Status' "$fake_json") == running ]] || fail "retry treated a failed start as an intentionally stopped VM"
[[ ! -e $RUNTIME_DIR/reconcile-pending ]] || fail "successful start retry left its journal"
pass "retry starts a hardened replacement when the first reconciliation failed before booting it"

for mutation in \
  '.[-1].Name = "/not-an-id_monarch-windows"' \
  '.[-1].Name = "/dddddddddddd_monarch-windows"' \
  'del(.[-1].Config.Labels["com.docker.compose.replace"])' \
  '.[-1].Config.Labels["com.docker.compose.replace"] = "unrelated"' \
  '.[-1].Config.Env = ["PROTECT=N"]' \
  '.[-1].Config.Env = ["PROTECT=Y", "PROTECT=N"]' \
  '.[-1].HostConfig.RestartPolicy.Name = "always"' \
  '.[-1].Mounts[0].Source = "/unrelated/storage"' \
  '.[-1].Mounts[1].RW = false' \
  '.[-1].Mounts += [{Type: "bind", Source: "/", Destination: "/host", RW: true}]' \
  '.[-1].State.Status = "running" | .[-1].State.Running = true' \
  '.[-1].State.Status = "exited"' \
  '.[-1].State.StartedAt = "2026-09-05T00:00:00Z"' \
  'del(.[-1].State.StartedAt)' \
  '.[-1].Config.Image = "unrelated/image"' \
  '.[-1].Config.Labels["com.docker.compose.project.working_dir"] = "/unrelated"' \
  '.[-1].Config.Labels["com.docker.compose.project.config_files"] = "/tmp/other-compose.yml"'; do
  reset_case
  add_replacement keep
  change_container "$mutation"
  __priv_reconcile >/dev/null 2>&1 && fail "unverified Compose replacement was accepted: $mutation"
  assert_no_mutations "$mutation"
done
reset_case
add_replacement keep
change_container --arg legacy "$CALLER_HOME/.config/windows" \
  '.[-1].Config.Labels["com.docker.compose.project.working_dir"] = $legacy |
    .[-1].Config.Labels["com.docker.compose.project.config_files"] = ($legacy + "/docker-compose.yml")'
__priv_reconcile >/dev/null 2>&1 && fail "replacement from a user-owned legacy compose was accepted"
assert_no_mutations "legacy-origin replacement"
reset_case
add_replacement keep
change_container --arg storage "$LEGACY_STORAGE" --arg shared "$LEGACY_SHARED" \
  '.[-1].Mounts[0].Source = $storage | .[-1].Mounts[1].Source = $shared'
__priv_reconcile >/dev/null 2>&1 && fail "replacement with legacy mount paths was accepted"
assert_no_mutations "legacy-mount replacement"
pass "replacement recovery rejects wrong identifiers, origins, protection, mounts, and any previously started container"

reset_case
add_replacement keep
change_container '.[0].Config.Image = "unrelated/image"'
__priv_reconcile >/dev/null 2>&1 && fail "a valid temporary replacement hid an unrelated original container"
assert_no_mutations "unrelated original with a valid replacement"
reset_case
add_replacement keep
change_container --arg id "$fake_other_id" '. + [.[-1] | .Id = $id]'
__priv_reconcile >/dev/null 2>&1 && fail "multiple temporary replacements were accepted"
assert_no_mutations "multiple temporary replacements"
reset_case
add_replacement only
__priv_reconcile >/dev/null 2>&1 && fail "an orphan replacement without a reconciliation journal was adopted"
assert_no_mutations "orphan replacement without a journal"
pass "replacement recovery requires an owned original or journal and refuses multiple replacements"

for failure in remove_replacement rename_replacement; do
  reset_case
  if [[ $failure == remove_replacement ]]; then
    fake_compose_effect=replacement_pair
  else
    fake_compose_effect=replacement_only
  fi
  __priv_reconcile >/dev/null 2>&1 && fail "replacement fixture did not fail Compose"
  fake_compose_effect=converge
  fake_failure=$failure
  : >"$fake_mutations"
  __priv_reconcile >/dev/null 2>&1 && fail "$failure was ignored"
  rg -q '^compose ' "$fake_mutations" && fail "Compose ran after $failure failed"
  [[ -f $RUNTIME_DIR/reconcile-pending ]] || fail "$failure removed the reconciliation journal"
  fake_failure=
  __priv_reconcile || fail "$failure could not be retried"
  assert_hardened "$failure retry"
  [[ $(jq -r '.[0].State.Status' "$fake_json") == running ]] || fail "$failure retry forgot an active VM"
  [[ ! -e $RUNTIME_DIR/reconcile-pending ]] || fail "$failure retry left the reconciliation journal"
done
pass "replacement removal and rename failures propagate while retaining enough state for a successful retry"

reset_case running
fake_compose_effect=start_failure
__priv_reconcile >/dev/null 2>&1 && fail "failed-start fixture did not leave pending reconciliation"
fake_compose_effect=converge
fake_failure=down
__priv_down >/dev/null 2>&1 && fail "failed explicit stop was ignored"
[[ -f $RUNTIME_DIR/reconcile-pending ]] || fail "failed explicit stop discarded the pending reconciliation"
fake_failure=
__priv_down || fail "explicit stop could not be retried"
[[ ! -e $RUNTIME_DIR/reconcile-pending ]] || fail "successful explicit stop retained an instruction to restart the VM"
: >"$fake_mutations"
__priv_reconcile || fail "reconciliation failed after an explicit stop"
assert_no_mutations "reconciliation following an explicit stop"
pass "an explicit stop cancels pending restart intent only after Docker confirms success"

for effect in stale unprotected restart foreign missing stopped; do
  reset_case
  fake_compose_effect=$effect
  __priv_reconcile >/dev/null 2>&1 && fail "postcheck accepted $effect Compose result"
done
reset_case exited
fake_compose_effect=running
__priv_reconcile >/dev/null 2>&1 && fail "postcheck accepted a stopped VM unexpectedly starting"
pass "successful Compose exit is insufficient when runtime security or activity state is wrong"

reset_case running legacy legacy
__priv_up || fail "explicit launch of a running legacy container failed"
assert_hardened "explicit launch"
assert_mutation 'compose up -d --no-deps --timeout 120 --force-recreate windows'
reset_case running legacy legacy
__priv_up_wait || fail "readiness launch of a running legacy container failed"
assert_hardened "readiness launch"
assert_mutation 'compose up -d --no-deps --timeout 120 --force-recreate windows'
pass "both launch paths reconcile already running containers before reporting readiness"

(
  : >"$fake_trace"
  priv_target() { printf '%s\n' "$test_tmp/verified-helper"; }
  sudo() { printf 'sudo %s\n' "$*" >>"$fake_trace"; }
  pkexec() { fail "reconciliation tried to open a polkit prompt"; }
  WINDOWS_VM_USE_SUDO=true priv reconcile || fail "sudo reconciliation dispatch failed"
  [[ $(<"$fake_trace") == "sudo $test_tmp/verified-helper __priv reconcile" ]] ||
    fail "sudo did not receive the verified packaged helper"
  : >"$fake_trace"
  priv_target() { return 1; }
  WINDOWS_VM_USE_SUDO=true priv reconcile >/dev/null 2>&1 && fail "unverified privilege target was accepted"
  [[ ! -s $fake_trace ]] || fail "sudo ran despite an unverified privilege target"
)
for action in prepare_reconcile reconcile; do
  valid_priv_action "$action" || fail "$action is missing from the privileged action allowlist"
done
pass "reconciliation elevates its verified helper through sudo without a polkit prompt"

(
  printf '%s\n' 'services:' '  windows:' '    environment:' \
    '      RAM_SIZE: "4G"' '      CPU_CORES: "2"' '      DISK_SIZE: "64G"' \
    '      USERNAME: "alice"' '      PASSWORD: "example"' '      TZ: "UTC"' >"$LEGACY_COMPOSE_FILE"
  rm -f "$COMPOSE_FILE"
  prepare_user_mount_sources() { :; }
  write_credentials() { printf '%s\n' "$1" "$2" >"$CREDENTIALS_FILE"; }
  write_compose() { printf 'protected runtime fixture\n' >"$COMPOSE_FILE"; }
  migrate_legacy_compose defer || fail "deferred legacy migration failed"
  [[ -f $COMPOSE_FILE && -f $LEGACY_COMPOSE_FILE ]] || fail "deferred migration removed legacy configuration"
  rm "$COMPOSE_FILE"
  migrate_legacy_compose || fail "ordinary legacy migration failed"
  [[ -f $COMPOSE_FILE && ! -e $LEGACY_COMPOSE_FILE ]] || fail "ordinary migration stopped cleaning up legacy configuration"
)
pass "deferred migration preserves the legacy retry marker while ordinary migration retains its cleanup behavior"

packaged_fixture="$test_tmp/packaged"
leaf_fixture="$test_tmp/reconcile-leaf"
mkdir -p "$packaged_fixture/bin" "$leaf_fixture"
printf '%s\n' '#!/bin/bash' \
  '[[ ${BASH_SOURCE[0]} != "$0" ]] || exit 90' \
  'LEGACY_COMPOSE_FILE="$WINDOWS_RECONCILE_TEST_ROOT/legacy"' \
  'CREDENTIALS_FILE="$WINDOWS_RECONCILE_TEST_ROOT/credentials"' \
  'priv() {' \
  '  [[ ${WINDOWS_VM_USE_SUDO:-false} == true ]] || return 91' \
  '  printf "priv %s\n" "$*" >>"$WINDOWS_RECONCILE_TEST_ROOT/trace"' \
  '  [[ ${WINDOWS_RECONCILE_TEST_FAILURE:-} != "$1" ]]' \
  '}' \
  'migrate_legacy_compose() {' \
  '  [[ $# == 1 && $1 == defer ]] || return 92' \
  '  printf "migrate %s\n" "$*" >>"$WINDOWS_RECONCILE_TEST_ROOT/trace"' \
  '  [[ ${WINDOWS_RECONCILE_TEST_FAILURE:-} != migrate ]] || return 23' \
  '  : >"$CREDENTIALS_FILE"' \
  '}' >"$packaged_fixture/bin/monarch-windows-vm"

run_reconcile_leaf() {
  MONARCH_PATH="$packaged_fixture" WINDOWS_RECONCILE_TEST_ROOT="$leaf_fixture" \
    WINDOWS_RECONCILE_TEST_FAILURE="${1:-}" bash "$ROOT/install/reconcile/windows-vm.sh"
}

reset_leaf() {
  rm -f "$leaf_fixture/legacy" "$leaf_fixture/credentials"
  : >"$leaf_fixture/trace"
}

reset_leaf
run_reconcile_leaf || fail "system reconciliation without a Windows installation did not return success"
[[ ! -s $leaf_fixture/trace ]] || fail "system reconciliation elevated or migrated without an installation marker"
[[ ! -e $leaf_fixture/legacy && ! -e $leaf_fixture/credentials ]] ||
  fail "system reconciliation created configuration without an installation marker"
pass "system reconciliation does nothing without a legacy compose or credentials marker"

if ((EUID == 0)); then
  : >"$leaf_fixture/legacy"
  run_reconcile_leaf >/dev/null 2>&1 && fail "system reconciliation accepted root as the VM owner"
  [[ ! -s $leaf_fixture/trace ]] || fail "root system reconciliation reached privileged VM actions"
  [[ -f $leaf_fixture/legacy ]] || fail "root rejection removed the legacy compose"
  pass "system reconciliation rejects root before privileged VM actions"
else
  expected_leaf_trace=$'priv prepare_reconcile\nmigrate defer\npriv reconcile'
  for marker in legacy credentials; do
    reset_leaf
    : >"$leaf_fixture/$marker"
    run_reconcile_leaf || fail "system reconciliation failed for the $marker marker"
    [[ $(<"$leaf_fixture/trace") == "$expected_leaf_trace" ]] ||
      fail "system reconciliation did not prepare, defer migration, and converge in order for $marker"
    [[ ! -e $leaf_fixture/legacy && -f $leaf_fixture/credentials ]] ||
      fail "successful system reconciliation did not clean up legacy configuration for $marker"
  done
  pass "system reconciliation recognizes both supported markers and cleans up legacy configuration after convergence"

  for stage in prepare_reconcile migrate reconcile; do
    reset_leaf
    printf 'legacy configuration\n' >"$leaf_fixture/legacy"
    run_reconcile_leaf "$stage" >/dev/null 2>&1 && fail "system reconciliation ignored $stage failure"
    [[ $(<"$leaf_fixture/legacy") == 'legacy configuration' ]] || fail "$stage failure changed the legacy retry marker"
    case "$stage" in
    prepare_reconcile) expected_failure_trace='priv prepare_reconcile' ;;
    migrate) expected_failure_trace=$'priv prepare_reconcile\nmigrate defer' ;;
    reconcile) expected_failure_trace=$expected_leaf_trace ;;
    esac
    [[ $(<"$leaf_fixture/trace") == "$expected_failure_trace" ]] ||
      fail "system reconciliation continued after $stage failed"
    : >"$leaf_fixture/trace"
    run_reconcile_leaf || fail "system reconciliation could not retry $stage failure"
    [[ $(<"$leaf_fixture/trace") == "$expected_leaf_trace" ]] ||
      fail "system reconciliation retry skipped a required phase after $stage failure"
    [[ ! -e $leaf_fixture/legacy && -f $leaf_fixture/credentials ]] ||
      fail "successful $stage retry did not retire the legacy compose"
  done
  pass "system reconciliation propagates preparation, migration, and convergence failures and preserves configuration for retry"
fi
rg -q -F 'bash "$MONARCH_PATH/install/reconcile/windows-vm.sh"' "$ROOT/install/reconcile/system.sh" ||
  fail "system reconciliation does not run the Windows VM helper"
pass "system reconciliation runs the Windows VM leaf"
