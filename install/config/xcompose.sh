# Set default XCompose that is triggered with CapsLock
tee ~/.XCompose >/dev/null <<EOF
include "%H/.local/share/monarch/default/xcompose"

# Identification
<Multi_key> <space> <n> : "$MONARCH_USER_NAME"
<Multi_key> <space> <e> : "$MONARCH_USER_EMAIL"
EOF
