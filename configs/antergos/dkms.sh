#!/bin/bash

_KERNVER_STR="$(pacman -Q linux)"
_KERNVER="${_KERNVER_STR/linux }"

check_initramfs() {
	echo '>>> Updating module dependencies. Please wait ...'
	
	dkms add -k "${_KERNVER}" "zfs/${_PKGVER}"
	dkms install -k "${_KERNVER}" "zfs/${_PKGVER}"
	modprobe -a zfs

	echo '>>> Generating initial ramdisk, using mkinitcpio. Please wait...'

	mkinitcpio -p linux
}