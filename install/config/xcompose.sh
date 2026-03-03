# Set default XCompose that is triggered with CapsLock
tee ~/.XCompose >/dev/null <<EOF
# Run monarch-restart-xcompose to apply changes

# Include fast emoji access
include "%H/.local/share/monarch/default/xcompose"

# Identification
<Multi_key> <space> <n> : "$MONARCH_USER_NAME"
<Multi_key> <space> <e> : "$MONARCH_USER_EMAIL"
EOF
