set -euo pipefail

if monarch-pkg-present openai-codex-desktop; then
  # ALPM_QUESTION_CONFLICT_PKG (4) accepts replacement in one atomic transaction.
  sudo pacman -S --needed --noconfirm --ask=4 cachyos/chatgpt-desktop-bin
fi
