Modified version of archiso to build the Antergos ISO

## Dependencies ##

- antergos-gfxboot for a graphical boot (or isolinux/syslinux)
- arch-install-scripts
- dosfstools
- libisoburn
- mkinitcpio-nfs-utils
- make
- opendesktop-fonts
- patch
- squashfs-tools
- wget

Install: `sudo pacman -S arch-install-scripts dosfstools libisoburn mkinitcpio-nfs-utils make patch squashfs-tools wget`

## Instructions ##

 - Use `--recursive` when clonning this repository like this: `git clone https://github.com/antergos/antergos-iso.git --recursive`

 - Enter into antergos-iso folder and install our modified mkarchiso by running `cd antergos-iso` and then `sudo make install`

  - Run `cd`, `sudo pacman -S cpio gfxboot` and then clone antergos-gfxboot : `sudo git clone https://github.com/antergos/antergos-gfxboot /antergos-iso/antergos-gfxboot` (or setup isolinux/syslinux). `cd /antergos-iso/antergos-gfxboot` and then `sudo make` (with all content)

 - Become root by typing `su` (and then your password) and `cd`, and then enter this command: `cp -R /antergos-iso/antergos-gfxboot/isolinux /home/user/antergos-iso/configs/antergos`. Or, open Nautilus and go to"Other Locations" "antergos-iso" "antergos-gfxboot" and copy "isolinux" folder to /home/user/antergos-iso/configs/antergos

 - Create destination folder `/out` : `cd` and then `sudo mkdir /out`

 - Download openfonts package: https://www.archlinux.org/packages/community/any/opendesktop-fonts/download/ Next, copy this to antergos-iso/configs/antergos (or whatever version you want to build)

 - Run `cd /home/user/antergos-iso/configs/antergos/` and then `sudo git clone https://github.com/Antergos/iso-hotfix-utility`

 - Build the iso (run the command inside the `cd antergos-iso/configs/antergos/` directory): `sudo ./build.sh build`

 **If you want to try to build the iso again, please remember to clean all generated files first:** `sudo ./build.sh clean`
