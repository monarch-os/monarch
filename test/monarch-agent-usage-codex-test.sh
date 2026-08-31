#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/bin" "$TEST_HOME/cache"

cat >"$TEST_HOME/bin/codex" <<'SCRIPT'
#!/bin/bash

if [[ $* == *"untrusted"* ]]; then
  echo "error: invalid value 'untrusted' for '--ask-for-approval <APPROVAL_POLICY>'" >&2
  exit 2
fi

[[ $* == *"-a never"* ]] || exit 3

if [[ ${CODEX_FAKE_FAILURE:-} == "1" ]]; then
  echo "error: approval policy changed again" >&2
  exit 2
fi

if [[ ${CODEX_FAKE_NOISY:-} == "1" ]]; then
  head -c 1048576 /dev/zero | tr '\0' x >&2
fi

while IFS= read -r request; do
  id=$(jq -r '.id // empty' <<<"$request")
  method=$(jq -r '.method' <<<"$request")
  case "$method" in
    initialize)
      jq -cn --argjson id "$id" '{id:$id,result:{}}'
      ;;
    account/read)
      jq -cn --argjson id "$id" '{id:$id,result:{account:{planType:"plus"}}}'
      ;;
    account/rateLimits/read)
      jq -cn --argjson id "$id" '{id:$id,result:{rateLimits:{planType:"plus",primary:{usedPercent:25,windowDurationMins:300,resetsAt:1788159600}}}}'
      ;;
  esac
done
SCRIPT
chmod +x "$TEST_HOME/bin/codex"

record=$(env -u CODEX_HOME -u XDG_DATA_HOME HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/cache" PATH="$TEST_HOME/bin:/usr/bin" \
  "$ROOT/bin/monarch-agent-usage-codex" --limits-only)

jq -e '
  .ready == true and
  .tierLabel == "plus" and
  .usageStatusText == "" and
  .authHelpText == "Run `codex login` to authenticate." and
  (.limits | length) == 1 and
  .limits[0].label == "5h window" and
  .limits[0].percent == 0.25
' <<<"$record" >/dev/null

failed_record=$(env -u CODEX_HOME -u XDG_DATA_HOME HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/cache" \
  CODEX_FAKE_FAILURE=1 PATH="$TEST_HOME/bin:/usr/bin" "$ROOT/bin/monarch-agent-usage-codex" --limits-only)

jq -e '
  .usageStatusText == "Codex limits unavailable" and
  .authHelpText == "error: approval policy changed again"
' <<<"$failed_record" >/dev/null

noisy_record=$(env -u CODEX_HOME -u XDG_DATA_HOME HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/cache" \
  CODEX_FAKE_NOISY=1 PATH="$TEST_HOME/bin:/usr/bin" "$ROOT/bin/monarch-agent-usage-codex" --limits-only)

jq -e '.tierLabel == "plus" and (.limits | length) == 1' <<<"$noisy_record" >/dev/null

echo "monarch-agent-usage-codex tests passed"
