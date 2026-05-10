# Place in each assistant's global skills directory so the Monarch skill is available on first install
mkdir -p ~/.agents/skills ~/.claude/skills ~/.codex/skills ~/.pi/agent/skills
ln -sfn "$MONARCH_PATH/default/monarch-skill" ~/.agents/skills/monarch
ln -sfn "$MONARCH_PATH/default/monarch-skill" ~/.claude/skills/monarch
ln -sfn "$MONARCH_PATH/default/monarch-skill" ~/.codex/skills/monarch
ln -sfn "$MONARCH_PATH/default/monarch-skill" ~/.pi/agent/skills/monarch
