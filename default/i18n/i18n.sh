#!/bin/bash

monarch_i18n_language() {
  local candidate=${MONARCH_LANGUAGE:-}
  if [[ -z $candidate ]]; then
    IFS= read -r candidate 2>/dev/null <"${XDG_CONFIG_HOME:-$HOME/.config}/monarch/language" || true
  fi
  if [[ -z $candidate || $candidate == "auto" ]]; then
    candidate=${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}
  fi
  case ${candidate,,} in
    fr | fr_* | fr-* | fr.*) printf 'fr\n' ;;
    *) printf 'en\n' ;;
  esac
}

monarch_i18n_load() {
  if [[ ${MONARCH_I18N_READY:-false} != "true" ]]; then
    declare -gA MONARCH_I18N_STRINGS=()
    MONARCH_I18N_READY=true
    local key value
    while IFS= read -r -d '' key && IFS= read -r -d '' value; do
      MONARCH_I18N_STRINGS["$key"]=$value
    done < <(python "${BASH_SOURCE[0]%/*}/i18n.py" --shell)
  fi
}

monarch_i18n_get() {
  local category=$1 key=$2 fallback=$3
  monarch_i18n_load
  printf '%s' "${MONARCH_I18N_STRINGS["$category:$key"]:-$fallback}"
}

monarch_t() {
  local key=$1 text result="" token index
  shift
  monarch_i18n_load
  monarch_i18n_load
  text=${MONARCH_I18N_STRINGS["strings:$key"]:-$key}
  while [[ $text =~ %([1-9][0-9]*) ]]; do
    token=${BASH_REMATCH[0]}
    index=${BASH_REMATCH[1]}
    result+=${text%%"$token"*}
    if (( ${#index} < 6 && index <= $# )); then
      result+=${!index}
    else
      result+=$token
    fi
    text=${text#*"$token"}
  done
  printf '%s' "$result$text"
}

monarch_message() {
  monarch_t "$@"
  printf '\n'
}
