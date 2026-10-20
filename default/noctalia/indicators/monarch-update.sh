#!/bin/bash

set -uo pipefail

root=${MONARCH_PATH:-/usr/share/monarch}
export MONARCH_PATH="$root"
export PATH="$root/bin:$PATH"
# shellcheck source=default/i18n/i18n.sh
source "$("$root/bin/monarch-i18n" --helper)"

idle_interval=${MONARCH_UPDATE_INTERVAL:-21600} # 6h while up to date
busy_interval=600                               # 10min for pending updates or failed checks
offline_interval=60

network_state() {
  local connectivity
  connectivity=$(LC_ALL=C nmcli -t -f STATE,CONNECTIVITY general 2>/dev/null) || connectivity=""
  case $connectivity in
    connected:full) echo "online" ;;
    asleep:* | disconnected:* | disconnecting:* | connecting:* | *:none | *:portal) echo "offline" ;;
    *) echo "unknown" ;;
  esac
}

confirm_online() {
  local connectivity
  [[ $(network_state) == "online" ]] || return 1
  connectivity=$(LC_ALL=C timeout --kill-after=2s 15s nmcli --wait 10 networking connectivity check 2>/dev/null) || return 1
  [[ $connectivity == "full" ]]
}

prev=""
last_available=""
while true; do
  if [[ $(network_state) == "offline" ]]; then
    line='{}'
    [[ $line != "$prev" ]] && printf '%s\n' "$line" && prev="$line"
    sleep "$offline_interval"
    continue
  fi
  # Respect Monarch's language independently of Noctalia's locale.
  MONARCH_I18N_READY=false
  monarch_i18n_load
  status=0
  result=$("$root/bin/monarch-update-available" --all --json 2>/dev/null) || status=$?
  interval=$busy_interval
  if (( status == 0 )) && jq -e '
    def counter: type == "number" and . >= 0 and . == floor;
    .status == "available" and (.count | type == "number") and .count > 0
    and (.packages | type == "array") and (.counts | type == "object")
    and (.complete | type == "boolean")
    and (.counts.monarch | counter) and (.counts.repo | counter)
    and (if .complete then (.counts.aur | counter) and .aur == .counts.aur
         else .counts.aur == null and .aur == null end)
    and .count == (.packages | length)
    and .count == (.counts.monarch + .counts.repo + (.counts.aur // 0))
    and all(.packages[];
      (.name | type == "string") and (.installed | type == "string")
      and (.available | type == "string")
      and (.category == "monarch" or .category == "repo" or .category == "aur"))
  ' >/dev/null 2>&1 <<< "$result"; then
    line=$(jq -c --arg title "$(monarch_t 'updates.indicator.available')" \
      --arg monarch "Monarch" --arg repo "$(monarch_t 'updates.indicator.repositories')" \
      --arg aur "AUR" --arg unknown "$(monarch_t 'updates.indicator.unknown')" \
      --arg partial "$(monarch_t 'updates.indicator.partial')" \
      --arg more "$(monarch_t 'updates.indicator.more')" \
      --arg action "$(monarch_t 'updates.indicator.action')" '
      def short: tostring | gsub("[[:cntrl:]]"; " ") | .[0:100];
      {text:(" " + (if .complete == false then "≥" else "" end) + (.count|tostring)),
       textColor:(if (.counts.monarch // 0) > 0 then "primary"
                  elif (.counts.repo // 0) > 0 then "secondary" else "tertiary" end),
       tooltip:([
         ($title + ": " + (if .complete == false then "≥" else "" end) + (.count|tostring)),
         ($monarch + ": " + (.counts.monarch // 0|tostring) + " · " +
          $repo + ": " + (.counts.repo // 0|tostring) + " · " +
          $aur + ": " + (if .aur == null then $unknown else (.counts.aur // 0|tostring) end)),
         (if .complete == false then $partial else empty end),
         "",
         (.packages | sort_by([({monarch:0,repo:1,aur:2}[.category] // 3), .name]) | .[:12][] |
           (.name|short) + "  " + (.installed|short) + " → " + (.available|short)),
         (if (.packages|length) > 12 then $more + ": " + ((.packages|length)-12|tostring) else empty end),
         "", $action
       ] | join("\n"))}
    ' <<< "$result") || line=""
    if [[ -n $line ]]; then last_available=$line; fi
  elif (( status == 1 )) && jq -e '.status == "current" and .count == 0 and .complete == true' >/dev/null 2>&1 <<< "$result"; then
    line='{}'
    last_available=""
    interval=$idle_interval
  else
    line=""
  fi
  if [[ -z $line ]]; then
    if ! confirm_online; then
      line='{}'
      interval=$offline_interval
    else
      warning=$(monarch_t 'updates.indicator.failed')
      if [[ -n $last_available ]]; then
        line=$(jq -c --arg warning "$warning" --arg stale "$(monarch_t 'updates.indicator.stale')" \
          '.text="" | .textColor="on_surface_variant" | .tooltip=($warning + "\n" + $stale + "\n\n" + .tooltip)' <<< "$last_available")
      else
        line=$(jq -cn --arg tooltip "$warning" '{text:"",textColor:"on_surface_variant",tooltip:$tooltip}')
      fi
    fi
  fi
  [[ $line != "$prev" ]] && printf '%s\n' "$line" && prev="$line"
  sleep "$interval"
done
