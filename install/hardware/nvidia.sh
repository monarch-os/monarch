# The offline mirror carries the Turing+ driver only, so a pre-Turing card
# installs without one. install.sh traps ERR, so leave a marker for first-run to
# report rather than failing the install over a driver the machine can fetch.
if lspci | grep -qi 'nvidia' && ! monarch-install-nvidia; then
  mkdir -p ~/.local/state/monarch
  touch ~/.local/state/monarch/nvidia-driver-pending
fi
