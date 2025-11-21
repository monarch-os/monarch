# Set identification from install inputs
if [[ -n "${MONARCH_USER_NAME//[[:space:]]/}" ]]; then
  git config --global user.name "$MONARCH_USER_NAME"
fi

if [[ -n "${MONARCH_USER_EMAIL//[[:space:]]/}" ]]; then
  git config --global user.email "$MONARCH_USER_EMAIL"
fi
