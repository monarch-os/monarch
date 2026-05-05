# Overwrite parts of the monarch-menu with user-specific submenus.
# See $MONARCH_PATH/bin/monarch-menu for functions that can be overwritten.
#
# WARNING: Overwritten functions will obviously not be updated when Monarch changes.
#
# Example of minimal system menu:
#
# show_system_menu() {
#   case $(menu "System" "  Lock\n󰐥  Shutdown") in
#   *Lock*) monarch-system-lock ;;
#   *Shutdown*) monarch-system-shutdown ;;
#   *) back_to show_main_menu ;;
#   esac
# }
#
# Example of overriding just the about menu action: (Using zsh instead of bash (default))
#
# show_about() {
#   exec monarch-launch-or-focus-tui "zsh -c 'fastfetch; read -k 1'"
# }
