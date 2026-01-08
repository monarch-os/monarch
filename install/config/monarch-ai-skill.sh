# Place in ~/.claude/skills since all tools populate from there as well as their own sources
mkdir -p ~/.claude/skills
ln -s $MONARCH_PATH/default/monarch-skill ~/.claude/skills/monarch
