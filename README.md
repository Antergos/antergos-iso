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
 - Copy the antergos folder from `/usr/share/antergos-iso/configs` to your working directory (`/home/antergos`, for instance).
 - Clone antergos-gfxboot into `/home/antergos/antergos-gfxboot` :
 `git clone https://github.com/antergos/antergos-gfxboot`
 (or setup isolinux/syslinux).
 - Create destination folder `/out` : `sudo mkdir /out`
 - Create a symlink to your working directory and call it `/start` : `sudo ln -s /home/antergos /start`
 - Build the iso (run the command inside the `/home/antergos` directory): `sudo ./build.sh build dual`
 
/start and /out are defaults. You can change it passing the desired directories as parameters to build.sh
