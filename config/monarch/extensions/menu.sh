# Overwrite parts of the monarch-menu with user-specific submenus.
# See $MONARCH_PATH/bin/monarch-menu for functions that can be overwritten.
#
# WARNING: Overwritten functions will obviously not be updated when Monarch changes.
#
# Example of minimal system menu:
#
# show_system_menu() {
#   case $(menu "System" "  Lock\n󰐥  Shutdown") in
#   *Lock*) monarch-lock-screen ;;
#   *Shutdown*) monarch-cmd-shutdown ;;
#   *) back_to show_main_menu ;;
#   esac
# }
