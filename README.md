Modified version of archiso to build the Antergos ISO

## Dependencies ##

- antergos-gfxboot for a graphical boot (or isolinux/syslinux)
- arch-install-scripts
- dosfstools
- libisoburn
- mkinitcpio-nfs-utils
- make
- openfonts (tgz file)
- patch
- squashfs-tools
- wget

## Instructions ##

 - `sudo make install`
 - Copy the antergos folder from `/usr/share/antergos-iso/configs` to your working directory (`/var/tmp/antergos`, for instance).
 - Clone antergos-gfxboot : `git clone https://github.com/antergos/antergos-gfxboot /var/tmp/antergos/antergos-gfxboot`
 (or setup isolinux/syslinux).
 - Create destination folder `/out` : `sudo mkdir /out`
 - Create a symlink to your working directory and call it `/start` : `sudo ln -s /var/tmp/antergos /start`
  - Download `opendesktop-fonts-X.X.X-X-any.pkg.tar.xz` from https://www.archlinux.org/packages/community/any/opendesktop-fonts/ (Download from Mirror) and move it in `/start`
 - Build the iso (run the command inside the `/var/tmp/antergos` directory): `sudo ./build.sh build dual`
 
/start and /out are defaults. You can change it passing the desired directories as parameters to build.sh

If you want to try to build the iso again, please remember to clean all generated files first: `sudo ./build.sh clean`
