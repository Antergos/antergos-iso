#!/bin/bash

_KERNVER_STR="$(pacman -Q linux)"
_KERNVER="${_KERNVER_STR/linux }-ARCH"

echo '>>> Updating module dependencies. Please wait ...'

if [[ $(dkms status -k "${_KERNVER}" spl/0.6.5.5) != *'installed'* ]]; then
	{ dkms install -k "${_KERNVER}" "spl/0.6.5.5"; } || exit 1
fi

if [[ $(dkms status -k "${_KERNVER}" zfs/0.6.5.5) != *'installed'* ]]; then
	{ dkms install -k "${_KERNVER}" "zfs/0.6.5.5"; } || exit 1
fi

if [[ $(dkms status -k "${_KERNVER}" vboxguest/5.0.16_OSE) != *'installed'* ]]; then
	{ dkms install -k "${_KERNVER}" "vboxguest/5.0.16_OSE"; } || exit 1
fi

{ mkinitcpio -p linux && exit 0; } || exit 1
