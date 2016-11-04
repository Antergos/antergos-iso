Modified version of archiso to build the Antergos ISO

## Dependencies ##

- arch-install-scripts
- dosfstools
- libisoburn
- mkinitcpio-nfs-utils
- make
- patch
- squashfs-tools
- wget
- openfonts

## Instructions ##

 - `sudo make install`
 - Copy the config folder from `/usr/share/antergos-iso` to your working directory
 - Create destination folder `/out`
 - Create a symlink to your working directory and call it `/start`
 - Build the iso (run the command inside the config/antergos directory): `sudo ./build.sh build dual`
 
