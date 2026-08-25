echo "Move coding agent wrappers from npx to mise"

monarch-mise-install codex
monarch-mise-install claude
monarch-mise-install crush
monarch-mise-install antigravity-cli agy
monarch-mise-install copilot
monarch-mise-install opencode
monarch-mise-install pi
monarch-mise-install github:can1357/oh-my-pi omp
monarch-mise-install npm:@xai-official/grok grok
monarch-mise-install github:OpenRouterLabs/ori-releases ori
monarch-mise-install npm:playwright playwright-cli playwright
monarch-mise-install npm:@kitlangton/ghui ghui

rm -f "$HOME/.local/bin/gemini"
