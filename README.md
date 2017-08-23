# Antergos ISO (antiso)
Modified version of archiso to build the Antergos ISO (livecd)

## Dependencies ##
- antergos-gfxboot for a graphical boot (or isolinux/syslinux)
- arch-install-scripts
- cpio
- dosfstools
- gfxboot
- libisoburn
- mkinitcpio-nfs-utils
- make
- opendesktop-fonts
- patch
- squashfs-tools
- wget

## Free space

Please, check that you have 5GB (or more) of free harddisk space in your root partition:
`df -h /`

## Instructions (without docker)

1. Install dependencies:
`sudo pacman -S arch-install-scripts cpio dosfstools gfxboot libisoburn mkinitcpio-nfs-utils make patch squashfs-tools wget`
2. Clone this repository using `--recursive` like this:
`git clone https://github.com/antergos/antergos-iso.git --recursive`
3. Enter into antergos-iso folder and change to the testing branch:
`cd antergos-iso` and then `git checkout testing`.
4. Install our modified mkarchiso and configurations by running:
`sudo make install`.
5. While inside `antergos-iso` folder, clone antergos-gfxboot and use antergos-gfxboot `colors` branch :
`git clone https://github.com/antergos/antergos-gfxboot` and `git checkout colors`.
7. Create /work and /out destination folders:
`sudo mkdir /work` and `sudo mkdir /out`
8. Go to the config directory you wish to build from.
- The "official" iso is in `cd /home/USER/antergos-iso/configs/antergos/`
- The "minimal" iso is in `cd /home/USER/antergos-iso/configs/minimal/`
9. Check text configuration file `config` with your favourite text editor.
10. Build the iso:
`sudo ./build.sh build`

 **If you want to try to build the iso again, please remember to clean all generated files first:** `sudo ./build.sh clean`

## Instructions (with Docker)

#### Install docker and setup your user
1. Install docker if you don't have it installed yet: `sudo pacman -S docker`
2. Add your user to the docker group (change USER for your username): `sudo usermod -aG docker USER`

#### Setup docker images and container
1. Clone this repository : `git clone https://github.com/antergos/antergos-iso.git`
2. Enter into antergos-iso folder and change to the testing branch: `cd antergos-iso` and then `git checkout testing`.
3. Go into docker directory : `cd docker`
4. Create antergos-base and antergos-iso docker images: `sudo ./build`
5. Run a container based on the antergos-iso image:
`docker run -it --mount source=outvol,target=/out --mount source=workvol,target=/work --name antergos-iso-build antergos-iso`

#### Once inside the container, create the iso image
1. Go to /antergos-iso folder : `cd /antergos-iso`
2. Go to the config directory you wish to build from.
- The "official" iso is in `cd /antergos-iso/configs/antergos/`
- The "minimal" iso is in `cd /antergos-iso/configs/minimal/`
3. Check text configuration file `config` with your favourite text editor
4. Build the iso: `sudo ./build.sh build`
