source $MONARCH_INSTALL/preflight/guard.sh
source $MONARCH_INSTALL/preflight/begin.sh
run_logged $MONARCH_INSTALL/preflight/show-env.sh
run_logged $MONARCH_INSTALL/preflight/pacman.sh
run_logged $MONARCH_INSTALL/preflight/migrations.sh
run_logged $MONARCH_INSTALL/preflight/first-run-mode.sh
run_logged $MONARCH_INSTALL/preflight/disable-mkinitcpio.sh
