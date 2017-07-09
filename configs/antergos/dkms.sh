#!/bin/bash

_KERNVER_STR="$(pacman -Q linux)"
_KERNVER="${_KERNVER_STR/linux }-ARCH"
_MODVER_STR="$(pacman -Q zfs)"
_MODVER_STR="${_MODVER_STR/zfs }"
_MODVER="${_MODVER_STR/.r*}"

pacman -S --needed linux-headers

echo '>>> Updating module dependencies. Please wait ...'

if [[ $(dkms status -k "${_KERNVER}" "spl/${_MODVER}") != *'installed'* ]]; then
	{ dkms install -k "${_KERNVER}" "spl/${_MODVER}"; } || exit 1
fi

if [[ $(dkms status -k "${_KERNVER}" "zfs/${_MODVER}") != *'installed'* ]]; then
	{ dkms install -k "${_KERNVER}" "zfs/${_MODVER}"; } || exit 1
fi

{ mkinitcpio -p linux && exit 0; } || exit 1
