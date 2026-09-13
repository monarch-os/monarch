monarch_font_validate_family() {
  local family="$1"

  if [[ -z $family || $family == *[[:cntrl:]]* || $family == [[:space:]]* || $family == *[[:space:]] ||
    $family == *:* || $family == *,* || $family == *\\* ]]; then
    echo "Font family must be a nonempty name without control characters, surrounding whitespace, colons, commas or backslashes." >&2
    return 1
  fi
}

monarch_font_sed_replacement() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//&/\\&}
  value=${value//|/\\|}
  printf '%s' "$value"
}
