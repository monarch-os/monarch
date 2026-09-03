set -euo pipefail

transition="$MONARCH_PATH/install/reconcile/schema/1-to-2"

bash "$transition/legacy-noctalia.sh"
bash "$transition/agents.sh"
bash "$transition/desktop-config.sh"
bash "$transition/nvim.sh"
bash "$transition/provision-noctalia.sh"
bash "$transition/runtime-hook.sh"
