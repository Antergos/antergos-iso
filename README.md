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

## Instructions ##

 - Use `--recursive` when clonning this repository
 - Enter into antergos-iso folder and install our modified mkarchiso by running `sudo make install`
 - Create destination folder `/out` : `sudo mkdir /out`
 - Go to de configs dir and choose which iso do you want to build entering to its folder (6dots, antergos, minimal) and running `sudo ./build.sh build`.
 
If you want to try to build the iso again, please remember to clean all generated files first: `sudo ./build.sh clean`
