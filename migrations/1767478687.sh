echo "Add opencode with system themeing"

monarch-pkg-add opencode

# Add config using monarch theme by default
if [[ ! -f ~/.config/opencode/opencode.json ]]; then
  mkdir -p ~/.config/opencode
  cp $MONARCH_PATH/config/opencode/opencode.json ~/.config/opencode/opencode.json
fi
