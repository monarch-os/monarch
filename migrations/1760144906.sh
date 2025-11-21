echo "Change monarch-screenrecord to use gpu-screen-recorder"

monarch-pkg-drop wf-recorder wl-screenrec

# Add slurp in case it hadn't been picked up from an old migration
monarch-pkg-add slurp gpu-screen-recorder