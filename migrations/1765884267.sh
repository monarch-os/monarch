echo "Change to openai-codex instead of openai-codex-bin"

if monarch-pkg-present openai-codex-bin; then
  monarch-pkg-remove openai-codex-bin
  monarch-pkg-add openai-codex
fi
