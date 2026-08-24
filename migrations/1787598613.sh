echo "Skip Noctalia's redundant first-run setup panel"

mkdir -p "$HOME/.local/state/noctalia"
touch "$HOME/.local/state/noctalia/.setup-complete"
