#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Unquoted heredocs expand in the caller's shell before privileged writes, so
# user-controlled paths can be baked into files root later reads or executes.

PRIVILEGED_PREFIXES=(/etc /usr /opt /srv /boot /var/lib)

USER_WRITABLE_VARS=(HOME PWD OLDPWD TMPDIR MONARCH_PATH MONARCH_INSTALL
  XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME XDG_RUNTIME_DIR)

WRITE_COMMANDS=(tee dd install cp mv)
ELEVATORS=(sudo as_root pkexec doas run0)

# An unquoted `(` inside a bracket expression is invalid in [[ =~ ]].
EXPANSION_RE='\$[A-Za-z_{(0-9@*#?$!-]'

EXPANSION_SCAN_RE='^([^$]*)\$(\{[^}]*\}|\([^)]*\)|[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?|[0-9@*#?$!-])(.*)$'

COMMAND_SUBSTITUTION="command-substitution"

# Exemptions must enumerate every path-shaped expansion, so later additions
# invalidate an outdated annotation instead of inheriting it.
ANNOTATION_RE='^[[:space:]]*#[[:space:]]*monarch:heredoc-expands[[:space:]]+paths=([A-Za-z_][A-Za-z0-9_-]*(,[A-Za-z_][A-Za-z0-9_-]*)*|none)[[:space:]]+--[[:space:]]+([^[:space:]].*)$'

FINDINGS=()

starts_with_privileged_prefix() {
  local candidate="$1" prefix

  for prefix in "${PRIVILEGED_PREFIXES[@]}"; do
    [[ $candidate == "$prefix"/* ]] && return 0
  done

  return 1
}

in_list() {
  local needle="$1" item
  shift

  for item in "$@"; do
    [[ $needle == "$item" ]] && return 0
  done

  return 1
}

# Escaped backslashes go first, otherwise "\\$TERM" looks like an escaped dollar.
strip_escapes() {
  local text="$1"

  text=${text//\\\\/}
  text=${text//\\$/}
  text=${text//\\\`/}

  printf '%s' "$text"
}

# Whole-line masking keeps parameter-substitution operators from looking like
# paths and preserves the placeholder-to-name ordering.
mask_and_names() {
  local text="$1" masked="" body inner tail name guard=0 nested_masked
  local -a names=() nested_scan=() nested_names=()

  while ((guard++ < 64)) && [[ $text =~ ^([^\`]*)\`([^\`]*)\`(.*)$ ]]; do
    body=${BASH_REMATCH[2]//[()]/}
    text="${BASH_REMATCH[1]}\$($body)${BASH_REMATCH[3]}"
  done

  guard=0
  while ((guard++ < 128)) && [[ $text =~ $EXPANSION_SCAN_RE ]]; do
    masked+="${BASH_REMATCH[1]}"$'\001'
    body=${BASH_REMATCH[2]}
    text=${BASH_REMATCH[4]}
    nested_masked=""
    nested_names=()

    if [[ $body == \(* ]]; then
      name=$COMMAND_SUBSTITUTION
    elif [[ $body == \{* ]]; then
      inner=${body:1:${#body}-2}
      inner=${inner#[\#!]}
      if [[ $inner =~ ^([A-Za-z_][A-Za-z0-9_]*) ]]; then
        name=${BASH_REMATCH[1]}
        tail=${inner#"$name"}
      elif [[ $inner =~ ^[0-9@*#?$!-] ]]; then
        name="shell-parameter"
        tail=${inner:1}
      else
        name=$COMMAND_SUBSTITUTION
        tail=$inner
      fi

      # Operator payloads expand independently; keep their placeholders aligned.
      if [[ $tail =~ $EXPANSION_RE || $tail == *'`'* ]]; then
        mapfile -t nested_scan < <(mask_and_names "$tail")
        nested_masked=${nested_scan[0]}
        nested_names=("${nested_scan[@]:1}")
      fi
    else
      name=${body%%\[*}
      [[ $name =~ ^[A-Za-z_] ]] || name="shell-parameter"
    fi

    names+=("$name")
    if ((${#nested_names[@]} > 0)); then
      masked+=" $nested_masked"
      names+=("${nested_names[@]}")
    fi
  done

  printf '%s\n' "$masked$text"
  if ((${#names[@]} > 0)); then
    printf '%s\n' "${names[@]}"
  fi
}

declare -A VARS=()
declare -A VARS_TAINTED=()

# The first literal assignment resolves destinations; taint persists across all
# assignments so a later user-writable value cannot hide behind that first value.
collect_vars() {
  local -n source_lines="$1"
  local line name value append

  VARS=()
  VARS_TAINTED=()
  for line in "${source_lines[@]}"; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    [[ $line =~ ^[[:space:]]*(local|declare|export|readonly|typeset)?[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)(\+?)=(.*)$ ]] || continue

    name=${BASH_REMATCH[2]}
    append=${BASH_REMATCH[3]}
    value=${BASH_REMATCH[4]}
    value=${value%%[[:space:]]#*}
    value=${value%[[:space:]]}
    if [[ $value == \"*\" || $value == \'*\' ]]; then
      value=${value:1:${#value}-2}
    fi

    mentions_user_writable_root "$value" && VARS_TAINTED["$name"]=1

    # Appends carry taint but do not provide a resolvable scalar value.
    [[ -n $append ]] && continue
    [[ -v VARS[$name] ]] || VARS["$name"]=$value
  done
}

# Resolve local assignments and mktemp templates far enough to classify paths.
resolve_value() {
  local value="$1" outer=0 inner before name default replacement

  while ((outer++ < 8)); do
    before=$value

    inner=0
    while ((inner++ < 32)) && [[ $value =~ \$\{([A-Za-z_][A-Za-z0-9_]*):?-([^}]*)\} ]]; do
      name=${BASH_REMATCH[1]}
      default=${BASH_REMATCH[2]}
      if [[ -v VARS[$name] && ${VARS[$name]} != *"\$$name"* ]]; then
        replacement=${VARS[$name]}
      else
        replacement=$default
      fi
      value=${value/"${BASH_REMATCH[0]}"/$replacement}
    done

    inner=0
    while ((inner++ < 32)) && [[ $value =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*) ]]; do
      name=${BASH_REMATCH[1]}
      [[ -n $name ]] || name=${BASH_REMATCH[2]}
      [[ -v VARS[$name] && ${VARS[$name]} != *"\$$name"* ]] || break
      value=${value/"${BASH_REMATCH[0]}"/${VARS[$name]}}
    done

    if [[ $value =~ \$\(mktemp[^\)]*[[:space:]]\"?([^\"\)]+)\"?\) ]]; then
      value=${BASH_REMATCH[1]}
    fi

    [[ $value == "$before" ]] && break
  done

  printf '%s' "$value"
}

literal_head() {
  local text="$1"

  [[ $text =~ ^[A-Za-z_][A-Za-z0-9_]*\+?= ]] && text=${text#*=}
  text=${text#[\"\']}

  printf '%s' "$text"
}

# Command substitutions are opaque; their command paths do not describe output.
literal_value() {
  local name="$1"

  [[ -v VARS[$name] ]] || return 0
  [[ ${VARS[$name]} != *'$('* && ${VARS[$name]} != *'`'* ]] || return 0

  resolve_value "${VARS[$name]}"
}

mentions_user_writable_root() {
  local text="$1" name pattern

  for name in "${USER_WRITABLE_VARS[@]}"; do
    # Whole-name matching separates MONARCH_INSTALL from MONARCH_INSTALL_USER.
    pattern='\$\{?'"$name"'([^A-Za-z0-9_]|$)'
    [[ $text =~ $pattern ]] && return 0
  done

  return 1
}

# Classify only the containing token so an unrelated root-owned path elsewhere
# on the line cannot legitimize a user-writable path.
classify_expansion() {
  local masked="$1" name="$2" head literal piece
  local path_shape=""

  head=$(literal_head "$masked")
  head=${head%%$'\001'*}
  literal=$(literal_value "$name")

  [[ $masked == */* ]] && path_shape+="token "
  in_list "$name" "${USER_WRITABLE_VARS[@]}" && path_shape+="user-root "
  [[ -v VARS_TAINTED[$name] ]] && path_shape+="tainted "
  [[ -n $literal && $literal == */* ]] && path_shape+="literal "

  [[ -n $path_shape ]] || return 1

  starts_with_privileged_prefix "$head" && return 1

  # Literal-only values are safe only when every resolved path is root-owned;
  # tainted or unresolved user roots never take this exception.
  if [[ $path_shape == "literal " ]]; then
    for piece in $literal; do
      piece=$(literal_head "$piece")
      if mentions_user_writable_root "$piece"; then
        return 0
      fi
      if [[ $piece == /* ]] && ! starts_with_privileged_prefix "$piece"; then
        return 0
      fi
    done
    return 1
  fi

  return 0
}

# Emit destinations plus an elevation marker for privileged command lines.
command_destinations() {
  local line="$1" token target elevated=1 copy_like=1 last="" index scan
  local -a tokens=()

  # Scanned destination paths cannot contain spaces.
  line=${line//\"/ }
  line=${line//\'/ }
  # Treat noclobber's bar as part of the redirect, not as a pipeline.
  line=${line//">|"/">"}
  # Preserve append redirects while separating operators from targets.
  line=${line//>>/$'\003'}
  line=${line//>/ > }
  line=${line//$'\003'/" >> "}

  read -r -a tokens <<<"$line"

  index=0
  while ((index < ${#tokens[@]})); do
    token=${tokens[index]}
    index=$((index + 1))

    in_list "$token" "${ELEVATORS[@]}" && elevated=0

    if [[ $token == ">" || $token == ">>" ]]; then
      target=${tokens[index]:-}
      index=$((index + 1))
      [[ -n $target && $target != "&"* && $target != /dev/* ]] && printf '%s\n' "$target"
      continue
    fi

    if [[ $token == of=* ]]; then
      printf '%s\n' "${token#of=}"
      continue
    fi

    if in_list "$token" "${WRITE_COMMANDS[@]}"; then
      if [[ $token == "tee" ]]; then
        scan=$index
        while ((scan < ${#tokens[@]})); do
          target=${tokens[scan]}
          scan=$((scan + 1))
          [[ $target == "|" || $target == "&&" || $target == ";" ]] && break
          [[ $target == -* || $target == "<"* || $target == ">" || $target == of=* ]] && continue
          [[ $target == /dev/* ]] && continue
          printf '%s\n' "$target"
        done
      elif [[ $token != "dd" ]]; then
        copy_like=0
      fi
      continue
    fi

    [[ $token != -* && $token != "|" && $token != "<"* && $token != ">" ]] && last=$token
  done

  if ((copy_like == 0)) && [[ -n $last ]]; then
    printf '%s\n' "$last"
  fi

  if ((elevated == 0)); then
    printf '%s\n' $'\002elevated'
  fi
}

# Compare resolved tokens so aliases and braced spellings identify one file.
line_carries_destination() {
  local line="$1" dest="$2" resolved token candidate
  local -a tokens=()

  resolved=$(resolve_value "$dest")
  line=${line//\"/ }
  line=${line//\'/ }
  read -r -a tokens <<<"$line"

  for token in "${tokens[@]}"; do
    token=${token#[<>]}
    token=${token%;}
    candidate=$(resolve_value "$token")
    [[ $candidate == "$resolved" ]] && return 0
  done

  return 1
}

# Follow direct destinations and one later copy from a scratch file.
privileged_destination() {
  local line="$1" start_index="$2"
  local -n scan_lines="$3"
  local dest resolved elevated=1 follow hop hop_dest
  local -a unresolved=()

  while IFS= read -r dest; do
    if [[ $dest == $'\002elevated' ]]; then
      elevated=0
      continue
    fi

    resolved=$(resolve_value "$dest")
    resolved=${resolved#\~}
    if starts_with_privileged_prefix "$resolved"; then
      printf '%s' "$resolved"
      return 0
    fi

    if [[ $resolved == *'$'* ]]; then
      unresolved+=("$dest")
    fi

    follow=$start_index
    while ((follow < ${#scan_lines[@]})); do
      hop=${scan_lines[follow]}
      follow=$((follow + 1))
      [[ $hop =~ (^|[[:space:]])(install|cp|mv)([[:space:]]|$) ]] || continue
      line_carries_destination "$hop" "$dest" || continue
      while IFS= read -r hop_dest; do
        [[ $hop_dest == $'\002elevated' ]] && continue
        [[ $hop_dest == "$dest" ]] && continue
        hop_dest=$(resolve_value "$hop_dest")
        if starts_with_privileged_prefix "$hop_dest"; then
          printf '%s' "$hop_dest"
          return 0
        fi
      done < <(command_destinations "$hop")
    done
  done < <(command_destinations "$line")

  # An unresolved elevated destination fails closed.
  if ((elevated == 0)) && ((${#unresolved[@]} > 0)); then
    printf '%s' "${unresolved[0]} (unresolved destination of an elevated write)"
    return 0
  fi

  return 1
}

# A continued pipeline may place its privileged consumer after the terminator.
continued_heredoc_command() {
  local command="$1" next="$2"
  local -n source_lines="$3"

  while [[ $command =~ (\|\||&&|\|)[[:space:]]*$ ]] && ((next < ${#source_lines[@]})); do
    while ((next < ${#source_lines[@]})) && [[ ${source_lines[next]} =~ ^[[:space:]]*(#.*)?$ ]]; do
      next=$((next + 1))
    done
    ((next < ${#source_lines[@]})) || break
    command+=" ${source_lines[next]}"
    next=$((next + 1))
  done

  printf '%s' "$command"
}

count_placeholders() {
  local text="$1" count=0

  while [[ $text == *$'\001'* ]]; do
    count=$((count + 1))
    text=${text#*$'\001'}
  done

  printf '%s' "$count"
}

normalize_path_set() {
  local value="$1"
  local -a names=()

  if [[ $value == "none" ]]; then
    printf 'none'
    return 0
  fi

  IFS=, read -ra names <<<"$value"
  mapfile -t names < <(printf '%s\n' "${names[@]}" | sort -u)
  (
    IFS=,
    printf '%s' "${names[*]}"
  )
}

inside_same_line_arithmetic() {
  local prefix="$1" opens=0 closes=0

  while [[ $prefix == *"(("* ]]; do
    opens=$((opens + 1))
    prefix=${prefix#*"(("}
  done
  while [[ $prefix == *"))"* ]]; do
    closes=$((closes + 1))
    prefix=${prefix#*"))"}
  done

  ((opens > closes))
}

scan_file() {
  local file="$1" display="${2:-$1}"
  local -a lines=()
  local index lineno line command scan rest raw operator match prefix guard slot delim candidate candidate_delim body_start
  local body_text unescaped destination destination_command body_line masked_line token name
  local declared_paths annotation look shown_paths shown_plain count next slots terminated
  local hd_re='(<<-?)[[:space:]]*("[A-Za-z_][A-Za-z0-9_]*"|'"'"'[A-Za-z_][A-Za-z0-9_]*'"'"'|[A-Za-z_][A-Za-z0-9_]*)'

  mapfile -t lines <"$file"
  collect_vars lines

  index=0
  while ((index < ${#lines[@]})); do
    line=${lines[index]}
    lineno=$((index + 1))
    index=$((index + 1))

    [[ $line =~ ^[[:space:]]*# ]] && continue

    # Bash removes escaped newlines before collecting heredoc bodies.
    command=$line
    while [[ $command == *\\ ]] && ((index < ${#lines[@]})); do
      command=${command%\\}
      command+=" ${lines[index]}"
      index=$((index + 1))
    done

    # Blanking herestrings preserves offsets for the heredoc matcher.
    scan=${command//<<</   }
    [[ $scan == *"<<"* ]] || continue

    # Track quoted delimiters too so their bodies are not parsed as commands.
    local -a delims=() quoted=() strip_tabs=()
    rest=$scan
    guard=0
    while ((guard++ < 8)) && [[ $rest =~ $hd_re ]]; do
      match=${BASH_REMATCH[0]}
      operator=${BASH_REMATCH[1]}
      raw=${BASH_REMATCH[2]}
      prefix=${rest%%"$match"*}
      rest=${rest#*"$match"}

      # Arithmetic shifts are not heredoc delimiters.
      inside_same_line_arithmetic "$prefix" && continue

      if [[ $raw == \"*\" || $raw == \'*\' ]]; then
        delims+=("${raw:1:${#raw}-2}")
        quoted+=(0)
      else
        delims+=("$raw")
        quoted+=(1)
      fi
      [[ $operator == "<<-" ]] && strip_tabs+=(1) || strip_tabs+=(0)
    done

    ((${#delims[@]} > 0)) || continue

    for slot in "${!delims[@]}"; do
      delim=${delims[slot]}
      local -a body=()
      body_start=$index
      terminated=1

      while ((index < ${#lines[@]})); do
        candidate=${lines[index]}
        index=$((index + 1))
        candidate_delim=$candidate
        if ((strip_tabs[slot] == 1)); then
          while [[ $candidate_delim == $'\t'* ]]; do
            candidate_delim=${candidate_delim#$'\t'}
          done
        fi
        if [[ $candidate_delim == "$delim" ]]; then
          terminated=0
          break
        fi
        body+=("$candidate")
      done

      # Resume after unmatched lightweight candidates instead of swallowing EOF.
      if ((terminated != 0)); then
        index=$body_start
        continue
      fi

      ((quoted[slot] == 1)) || continue

      printf -v body_text '%s\n' "${body[@]:-}"
      unescaped=$(strip_escapes "$body_text")
      [[ $unescaped =~ $EXPANSION_RE || $unescaped == *'`'* ]] || continue

      destination_command=$(continued_heredoc_command "$command" "$index" lines)
      destination=$(privileged_destination "$destination_command" "$index" lines) || continue

      local -a path_expansions=() plain_expansions=() scanned=() names=()
      while IFS= read -r body_line; do
        mapfile -t scanned < <(mask_and_names "$body_line")
        masked_line=${scanned[0]}
        names=("${scanned[@]:1}")
        next=0

        for token in $masked_line; do
          count=$(count_placeholders "$token")
          ((count > 0)) || continue

          for ((slots = 0; slots < count; slots++)); do
            name=${names[next]:-}
            next=$((next + 1))
            [[ -n $name ]] || continue

            if classify_expansion "$token" "$name"; then
              in_list "$name" "${path_expansions[@]:-}" || path_expansions+=("$name")
            else
              in_list "$name" "${plain_expansions[@]:-}" || plain_expansions+=("$name")
            fi
          done
        done
      done <<<"$unescaped"

      declared_paths=""
      annotation=""
      look=$((lineno - 2))
      while ((look >= 0)) && [[ ${lines[look]} =~ ^[[:space:]]*# ]]; do
        if [[ ${lines[look]} =~ $ANNOTATION_RE ]]; then
          declared_paths=${BASH_REMATCH[1]}
          annotation=${BASH_REMATCH[3]}
        fi
        look=$((look - 1))
      done

      shown_paths="none"
      if ((${#path_expansions[@]} > 0)); then
        shown_paths=$(
          IFS=,
          printf '%s' "${path_expansions[*]}"
        )
      fi
      shown_plain="none"
      if ((${#plain_expansions[@]} > 0)); then
        shown_plain=$(
          IFS=,
          printf '%s' "${plain_expansions[*]}"
        )
      fi

      if [[ -z $annotation ]]; then
        FINDINGS+=("$display:$lineno: unquoted heredoc <<$delim expands values at install time and its output reaches $destination
    path-shaped expansions: $shown_paths
    other expansions:       $shown_plain
    Whatever expands here is baked into a file root owns. If it is a path the
    installing user can replace, root later reads or executes attacker-controlled
    content -- that is a local privilege escalation.
    Fix, in order of preference:
      1. quote the delimiter (<<'$delim') so nothing expands at install time;
      2. hardcode an absolute root-owned path instead of expanding one;
      3. if the expansion is genuinely required, declare it above the heredoc:
           # monarch:heredoc-expands paths=<expansions used as paths, or none> -- <why this is safe>
         Decide that list yourself. The scan's own reading of it is above, and
         where the scan is most likely wrong is exactly here -- a path it could
         not follow reads as an ordinary value -- so pasting its verdict back
         signs off on the case worth checking by hand.")
        continue
      fi

      if [[ $(normalize_path_set "$declared_paths") != $(normalize_path_set "$shown_paths") ]]; then
        FINDINGS+=("$display:$lineno: heredoc annotation declares paths=$declared_paths but the path-shaped expansions are $shown_paths
    Writing to: $destination
    Every expansion used as a path outside a root-owned prefix has to be named,
    so adding one to an already-annotated heredoc trips this check again instead
    of inheriting the old exemption.
    Fix: drop the path expansion (hardcode an absolute root-owned path), or name
    every path-shaped expansion in the declaration and say why root using it is
    safe.")
      fi
    done
  done
}

# Scan every shipped shell source that can participate in setup or upgrades.
shell_sources() {
  local file first

  while IFS= read -r -d '' file; do
    grep -Iq '<<' "$file" 2>/dev/null || continue

    case $file in
      *.sh | *.hook)
        printf '%s\0' "$file"
        continue
        ;;
    esac

    IFS= read -r first <"$file" || true
    if [[ $first =~ ^#!.*[[:space:]/](bash|sh)$ ]]; then
      printf '%s\0' "$file"
    fi
  done < <(find "$ROOT/bin" "$ROOT/install" "$ROOT/migrations" "$ROOT/default" \
    -type f -print0 2>/dev/null | sort -z)
}

command -v find >/dev/null || fail "find is required"
command -v grep >/dev/null || fail "grep is required"

sources=()
while IFS= read -r -d '' file; do
  sources+=("$file")
done < <(shell_sources)

((${#sources[@]} > 10)) || fail "the scan reaches the privileged-write scripts" \
  "only ${#sources[@]} shell sources found under bin/, install/, migrations/ and default/"
pass "the scan reaches the privileged-write scripts (${#sources[@]} files)"

for file in "${sources[@]}"; do
  scan_file "$file" "${file#"$ROOT"/}"
done

if ((${#FINDINGS[@]} > 0)); then
  fail "no privileged write embeds an install-time expansion through an unquoted heredoc" \
    "$(printf '%s\n\n' "${FINDINGS[@]}")"
fi
pass "no privileged write embeds an install-time expansion through an unquoted heredoc"

# Fixtures prove both the scanner's positive and negative boundaries.

FIXTURES="$SHELL_TEST_DIR/fixtures/privileged-heredoc"

fixture_flags() {
  local fixture="$1" description="$2" expected="${3:-}"

  FINDINGS=()
  scan_file "$FIXTURES/$fixture" "$fixture"

  ((${#FINDINGS[@]} > 0)) || fail "$description" "$fixture produced no finding"
  if [[ -n $expected ]]; then
    printf '%s\n' "${FINDINGS[@]}" | grep -qF -- "$expected" ||
      fail "$description" "expected \"$expected\" in:$(printf '\n%s' "${FINDINGS[@]}")"
  fi
  pass "$description"
}

fixture_passes() {
  local fixture="$1" description="$2"

  FINDINGS=()
  scan_file "$FIXTURES/$fixture" "$fixture"

  ((${#FINDINGS[@]} == 0)) || fail "$description" "$(printf '%s\n' "${FINDINGS[@]}")"
  pass "$description"
}

# Historical installer shapes remain verbatim so the regressions stay realistic.
fixture_flags udev-rule-home-path.sh \
  "flags a power-profile udev rule whose RUN+= resolves under \$HOME" \
  "path-shaped expansions: HOME"
fixture_flags wifi-rule-home-path.sh \
  "flags a wifi-powersave udev rule whose RUN+= resolves under \$HOME" \
  "path-shaped expansions: HOME"
fixture_flags shutdown-unit-home-execstop.sh \
  "flags a shutdown unit with ExecStop=\$HOME/..." \
  "path-shaped expansions: HOME"

fixture_flags annotated-paths-none-still-fails.sh \
  "an annotation claiming paths=none cannot silence a baked \$HOME path" \
  "declares paths=none but the path-shaped expansions are HOME"
fixture_flags annotated-special-parameter-before-home.sh \
  "a shell special parameter cannot hide a later baked \$HOME path" \
  "declares paths=none but the path-shaped expansions are HOME"

fixture_flags hop-variable-home-path.sh \
  "an annotation cannot exempt a home path carried one variable hop away" \
  "declares paths=none but the path-shaped expansions are helper"
fixture_flags hop-twice-home-path.sh \
  "an annotation cannot exempt a home path carried two variable hops away" \
  "declares paths=none but the path-shaped expansions are helper"
fixture_flags shadowed-assignment-home-path.sh \
  "a later assignment under \$HOME is judged, not the packaged value it shadowed" \
  "declares paths=none but the path-shaped expansions are target"

fixture_flags route-redirect.sh "flags a plain redirect into /etc"
fixture_flags route-sudo-dd.sh "flags sudo dd of= into a privileged path"
fixture_flags route-variable-path.sh \
  "flags an elevated write whose destination is a variable resolving under /etc"
fixture_flags route-install-hop.sh \
  "flags a scratch file that install(1) later copies into /usr"
fixture_flags route-install-hop-literal.sh \
  "flags a literal scratch file that install(1) later copies into /etc"
fixture_flags route-install-hop-braced.sh \
  "flags a scratch-file hop whose variable uses braces at the privileged copy"
fixture_flags route-install-hop-alias.sh \
  "flags a scratch-file hop carried through an alias variable"
fixture_flags route-continued-pipeline.sh \
  "flags a privileged pipeline command continued after the heredoc terminator"
fixture_flags route-prebody-escaped-pipeline.sh \
  "flags an escaped-line pipeline consumer before the heredoc body"
fixture_flags route-dash-delimiter.sh "flags an indented <<- heredoc"
fixture_flags route-append-redirect.sh "flags an append redirect into /etc"
fixture_flags route-noclobber-redirect.sh \
  "flags a noclobber-override redirect into /etc"
fixture_flags arithmetic-left-shift-before-heredoc.sh \
  "an arithmetic left shift does not swallow a later privileged heredoc" \
  "path-shaped expansions: HOME"
fixture_flags plain-heredoc-indented-pseudo-delimiter.sh \
  "an indented delimiter does not terminate a plain heredoc" \
  "path-shaped expansions: HOME"
fixture_flags nested-parameter-default.sh \
  "a nested parameter default cannot hide a baked home path" \
  "path-shaped expansions are HOME"

mapfile -t dd_destinations < <(command_destinations \
  'sudo dd if=/tmp/input bs=4M status=none of=/etc/monarch/image')
[[ ${dd_destinations[0]:-} == "/etc/monarch/image" && ${dd_destinations[1]:-} == $'\002elevated' && ${#dd_destinations[@]} == 2 ]] ||
  fail "dd emits only its of= destination" "$(printf '%q\n' "${dd_destinations[@]:-}")"
pass "dd emits only its of= destination"

fixture_passes safe-quoted-delimiter.sh "a quoted delimiter passes"
fixture_passes safe-user-destination.sh \
  "an unquoted heredoc expanding into the user's own ~/.config passes"
fixture_passes safe-no-expansion.sh \
  "a privileged write with no expansion in the body passes"
fixture_passes safe-runtime-expansion.sh \
  "an escaped \\\$VAR left for a root daemon to expand passes"
fixture_passes safe-annotated.sh "a declared, reasoned exemption passes"
fixture_passes safe-annotated-reordered-paths.sh \
  "path declarations compare as sets rather than traversal order"
fixture_passes safe-root-anchored.sh \
  "a path expansion anchored under /etc is truthfully declared paths=none"
fixture_passes safe-herestring.sh "a herestring is not mistaken for a heredoc"
