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
 - Copy the antergos folder from `/usr/share/antergos-iso/configs` to your working directory (`/home/antergos`, for instance).
 - Create destination folder `/out` : `sudo mkdir /out`
 - Create a symlink to your working directory and call it `/start` : `sudo ln -s /home/antergos /start`
 - Build the iso (run the command inside the `/home/antergos` directory): `sudo ./build.sh build dual`
 
/start and /out are defaults. You can change it passing the desired directories as parameters to build.sh
