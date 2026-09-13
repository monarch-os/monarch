run_logged "$MONARCH_INSTALL/user/theme.sh"
run_logged "$MONARCH_INSTALL/user/git.sh"
run_logged "$MONARCH_INSTALL/user/xcompose.sh"
run_logged "$MONARCH_INSTALL/user/mise-work.sh"

# Monarch desktop adapters: Niri keyboard generation and MIME defaults are
# dynamic user state and cannot be seeded by monarch-settings.
run_logged "$MONARCH_INSTALL/user/detect-keyboard-layout.sh"
run_logged "$MONARCH_INSTALL/user/niri.sh"
run_logged "$MONARCH_INSTALL/user/exegol.sh"
run_logged "$MONARCH_INSTALL/user/mimetypes.sh"

run_logged "$MONARCH_INSTALL/user/hardware/asus/fix-audio-mixer.sh"
run_logged "$MONARCH_INSTALL/user/hardware/asus/fix-mic.sh"
run_logged "$MONARCH_INSTALL/user/hardware/framework/fix-f13-amd-audio-input.sh"
run_logged "$MONARCH_INSTALL/user/hardware/dell/xps13-text-scaling.sh"

run_logged "$MONARCH_INSTALL/user/default-keyring.sh"
run_logged "$MONARCH_INSTALL/user/mise.sh"
