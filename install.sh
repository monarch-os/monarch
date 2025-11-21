#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -eEo pipefail

# Define Monarch locations
export MONARCH_PATH="$HOME/.local/share/monarch"
export MONARCH_INSTALL="$MONARCH_PATH/install"
export MONARCH_INSTALL_LOG_FILE="/var/log/monarch-install.log"
export PATH="$MONARCH_PATH/bin:$PATH"

# Install
source "$MONARCH_INSTALL/helpers/all.sh"
source "$MONARCH_INSTALL/preflight/all.sh"
source "$MONARCH_INSTALL/packaging/all.sh"
source "$MONARCH_INSTALL/config/all.sh"
source "$MONARCH_INSTALL/login/all.sh"
source "$MONARCH_INSTALL/post-install/all.sh"
