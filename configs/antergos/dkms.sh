#!/bin/bash

_KERNVER_STR="$(pacman -Q linux)"
_KERNVER="${_KERNVER_STR/linux }-ARCH"

echo '>>> Updating module dependencies. Please wait ...'

{ dkms install -k "${_KERNVER}" "spl/0.6.5.4" && dkms install -k "${_KERNVER}" "zfs/0.6.5.4"; } || exit 1

{ modprobe -a spl zfs && mkinitcpio -p linux && exit 0; } || exit 1

