echo "Replace the custom libfprint-git package with stock libfprint"

# Monarch now uses stock libfprint (extra) for fingerprint auth instead of the
# custom libfprint-git package. On systems that still have libfprint-git, swap
# it: libfprint-git provides+conflicts libfprint and satisfies fprintd's
# dependency, so remove it with -Rdd (skip dep checks) then install stock
# libfprint to re-satisfy fprintd.
#
# NOTE: stock libfprint 1.94.10 does not yet carry the FocalTech FT9349 PID
# 0xa97a, so the ASUS ExpertBook B9406 sensor is no longer matched until a
# newer libfprint release ships it.
if monarch-pkg-present libfprint-git; then
  sudo pacman -Rdd --noconfirm libfprint-git
  sudo pacman -S --needed --noconfirm libfprint
fi
