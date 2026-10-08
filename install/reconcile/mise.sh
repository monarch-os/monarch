mise settings set upgrade.auto_prune false

work_config="$HOME/Work/.mise.toml"
if [[ -f $work_config && ! -L $work_config ]] &&
  cmp -s "$work_config" <(printf '%s\n' '[env]' '_.path = "{{ cwd }}/bin"'); then
  rm -f -- "$work_config"
elif [[ -f $work_config && ! -L $work_config ]]; then
  python3 "${BASH_SOURCE[0]%/*}/mise-work-path.py" "$work_config"
fi
