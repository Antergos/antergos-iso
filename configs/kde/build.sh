#!/bin/bash

set -e -u

iso_name=antergos
iso_label="ANTERGOS"
iso_version=$(date +%Y.%m.%d)
install_dir="arch"
arch=$(uname -m)
work_dir=work
out_dir=/out
verbose="-v"
cmd_args=""
keep_pacman_packages="y"
pacman_conf="${work_dir}/pacman.conf"
script_path=$(readlink -f ${0%/*})

setup_workdir() {
    #cache_dirs=($(pacman -v 2>&1 | grep '^Cache Dirs:' | sed 's/Cache Dirs:\s*//g'))
    cache_dirs="/var/cache/pacman/pkg"
    mkdir -p "${work_dir}"
    pacman_conf="${work_dir}/pacman.conf"
    sed -r "s|^#?\\s*CacheDir.+|CacheDir = $(echo -n ${cache_dirs[@]})|g" \
        "${script_path}/pacman.conf.${arch}" > "${pacman_conf}"
}

# Base installation (root-image)
make_basefs() {
    mkarchiso ${verbose} -z -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" init
    mkarchiso ${verbose} -z -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" -p "haveged intel-ucode memtest86+ nbd" install
}

# Additional packages (root-image)
make_packages() {
    mkarchiso ${verbose} -z -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" -p "$(grep -h -v ^# ${script_path}/packages.both)" install
}

# Copy mkinitcpio archiso hooks (root-image)
make_setup_mkinitcpio() {
    local _hook
    mkdir -p ${work_dir}/root-image/etc/initcpio/hooks
    mkdir -p ${work_dir}/root-image/etc/initcpio/install
    for _hook in archiso archiso_shutdown archiso_pxe_common archiso_pxe_nbd archiso_pxe_http archiso_pxe_nfs archiso_loop_mnt; do
         cp /usr/lib/initcpio/hooks/${_hook} ${work_dir}/root-image/usr/lib/initcpio/hooks
         cp /usr/lib/initcpio/install/${_hook} ${work_dir}/root-image/usr/lib/initcpio/install
         cp /usr/lib/initcpio/hooks/${_hook} ${work_dir}/root-image/etc/initcpio/hooks
         cp /usr/lib/initcpio/install/${_hook} ${work_dir}/root-image/etc/initcpio/install
    done
    cp /usr/lib/initcpio/install/archiso_kms ${work_dir}/root-image/usr/lib/initcpio/install
    cp /usr/lib/initcpio/archiso_shutdown ${work_dir}/root-image/usr/lib/initcpio
    sed -i "s|/usr/lib/initcpio/|/etc/initcpio/|g" ${work_dir}/root-image/etc/initcpio/install/archiso_shutdown
    cp /usr/lib/initcpio/install/archiso_kms ${work_dir}/root-image/etc/initcpio/install
    cp /usr/lib/initcpio/archiso_shutdown ${work_dir}/root-image/etc/initcpio
    cp -L ${script_path}/mkinitcpio.conf ${work_dir}/root-image/etc/mkinitcpio-archiso.conf
    cp -L ${script_path}/root-image/etc/os-release ${work_dir}/root-image/etc
    cp -L ${script_path}/plymouthd.conf ${work_dir}/root-image/etc/plymouth
    cp -L ${script_path}/plymouth.initcpio_hook ${work_dir}/root-image/etc/initcpio/hooks
    cp -L ${script_path}/plymouth.initcpio_install ${work_dir}/root-image/etc/initcpio/install
    #mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" -r 'plymouth-set-default-theme Antergos-Simple' run 2&>1
    echo '@@@@@@@@@@@@@@@@@@@~~~~~~~~~PLYMOUTH DONE~~~~~~~~~@@@@@@@@@@@@@@@@@@@';
   #sed -i 's|umount "|umount -l "|g' /usr/bin/arch-chroot
    mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" -r 'mkinitcpio -c /etc/mkinitcpio-archiso.conf -k /boot/vmlinuz-linux -g /boot/archiso.img' run 2>&1
    echo '@@@@@@@@@@@@@@@@@@@~~~~~~~~~MKINITCPIO DONE~~~~~~~~~@@@@@@@@@@@@@@@@@@@';
    if [[ -f ${work_dir}/root-image/boot/archiso.img ]]; then
    		echo '@@@@@@@@@@@@@@@@@@@~~~~~~~~~archiso.img EXISTS!!!~~~~~~~~~@@@@@@@@@@@@@@@@@@@';
    else
    		echo '@@@@@@@@@@@@@@@@@@@~~~~~~~~~CANNOT FIND archiso.img!!!~~~~~~~~~@@@@@@@@@@@@@@@@@@@';
    		arch-chroot "${work_dir}/root-image" 'mkinitcpio -c /etc/mkinitcpio-archiso.conf -k /boot/vmlinuz-linux -g /boot/archiso.img' 2>&1
    fi
    		
}

# Prepare ${install_dir}/boot/
make_boot() {
    mkdir -p ${work_dir}/iso/${install_dir}/boot/
    if [[ -f ${work_dir}/root-image/boot/archiso.img ]]; then
    	cp ${work_dir}/root-image/boot/archiso.img ${work_dir}/iso/${install_dir}/boot/archiso.img
    	cp ${work_dir}/root-image/boot/vmlinuz-linux ${work_dir}/iso/${install_dir}/boot/vmlinuz
    else
    	echo '@@@@@@@@@@@@@@@@@@@~~~~~~~~~work_dir is'; echo ${work_dir}; echo '~~~~~~~~~@@@@@@@@@@@@@@@@@@@'
    	ls ${work_dir} && ls ${work_dir}/root-image/ && ls ${work_dir}/root-image/boot/
    fi
}

make_boot_extra() {
    cp ${work_dir}/root-image/boot/memtest86+/memtest.bin ${work_dir}/iso/${install_dir}/boot/memtest
    cp ${work_dir}/root-image/usr/share/licenses/common/GPL2/license.txt ${work_dir}/iso/${install_dir}/boot/memtest.COPYING
    cp ${work_dir}/root-image/boot/intel-ucode.img ${work_dir}/iso/${install_dir}/boot/intel_ucode.img
    cp ${work_dir}/root-image/usr/share/licenses/intel-ucode/LICENSE ${work_dir}/iso/${install_dir}/boot/intel_ucode.LICENSE
}

# Prepare /${install_dir}/boot/syslinux
make_syslinux() {
    mkdir -p ${work_dir}/iso/${install_dir}/boot/syslinux
    for _cfg in ${script_path}/isolinux/*.cfg; do
        sed "s|%ARCHISO_LABEL%|${iso_label}|g;
             s|%INSTALL_DIR%|${install_dir}|g;
             s|%ARCH%|${arch}|g" ${_cfg} > ${work_dir}/iso/${install_dir}/boot/syslinux/${_cfg##*/}
    done
    cp -Lr isolinux ${work_dir}/iso/${install_dir}/boot/syslinux
    cp ${work_dir}/root-image/usr/lib/syslinux/bios/*.c32 ${work_dir}/iso/${install_dir}/boot/syslinux
    cp ${work_dir}/root-image/usr/lib/syslinux/bios/lpxelinux.0 ${work_dir}/iso/${install_dir}/boot/syslinux
    cp ${work_dir}/root-image/usr/lib/syslinux/bios/memdisk ${work_dir}/iso/${install_dir}/boot/syslinux
    mkdir -p ${work_dir}/iso/${install_dir}/boot/syslinux/hdt
    gzip -c -9 ${work_dir}/root-image/usr/share/hwdata/pci.ids > ${work_dir}/iso/${install_dir}/boot/syslinux/hdt/pciids.gz
    gzip -c -9 ${work_dir}/root-image/usr/lib/modules/*-ARCH/modules.alias > ${work_dir}/iso/${install_dir}/boot/syslinux/hdt/modalias.gz
}


make_isolinux() {
        mkdir -p ${work_dir}/iso/isolinux
        cp -Lr isolinux ${work_dir}/iso
        cp -R ${work_dir}/root-image/usr/lib/syslinux/bios/* ${work_dir}/iso/isolinux/
        cp ${work_dir}/root-image/usr/lib/syslinux/bios/*.c32 ${work_dir}/iso/isolinux/
        sed "s|%ARCHISO_LABEL%|${iso_label}|g;
             s|%INSTALL_DIR%|${install_dir}|g;
             s|%ARCH%|${arch}|g" ${script_path}/isolinux/isolinux.cfg > ${work_dir}/iso/isolinux/isolinux.cfg
        cp ${work_dir}/root-image/usr/lib/syslinux/bios/isolinux.bin ${work_dir}/iso/isolinux/
        cp ${work_dir}/root-image/usr/lib/syslinux/bios/isohdpfx.bin ${work_dir}/iso/isolinux/
        cp ${work_dir}/root-image/usr/lib/syslinux/bios/lpxelinux.0 ${work_dir}/iso/isolinux/

}

# Prepare /EFI
make_efi() {
        if [[ ${arch} == "x86_64" ]]; then

            mkdir -p ${work_dir}/iso/EFI/boot
            cp ${work_dir}/root-image/usr/share/efitools/efi/PreLoader.efi ${work_dir}/iso/EFI/boot/bootx64.efi
            cp ${work_dir}/root-image/usr/share/efitools/efi/HashTool.efi ${work_dir}/iso/EFI/boot/
            cp ${script_path}/efiboot/loader/bg.bmp ${work_dir}/iso/EFI/

            cp ${work_dir}/root-image/usr/lib/systemd/boot/efi/systemd-bootx64.efi ${work_dir}/iso/EFI/boot/loader.efi

            mkdir -p ${work_dir}/iso/loader/entries
            cp ${script_path}/efiboot/loader/loader.conf ${work_dir}/iso/loader/
            cp ${script_path}/efiboot/loader/entries/uefi-shell-v2-x86_64.conf ${work_dir}/iso/loader/entries/
            cp ${script_path}/efiboot/loader/entries/uefi-shell-v1-x86_64.conf ${work_dir}/iso/loader/entries/

            for boot_entry in ${script_path}/efiboot/loader/entries/**.conf; do
            	[[ "${boot_entry}" = **'archiso-cd'** ]] && continue
            	fname=$(basename ${boot_entry})
            	sed "s|%ARCHISO_LABEL%|${iso_label}|g;
                 	s|%INSTALL_DIR%|${install_dir}|g" ${boot_entry} > ${work_dir}/iso/loader/entries/${fname}
            done

           # EFI Shell 2.0 for UEFI 2.3+
    curl -o ${work_dir}/iso/EFI/shellx64_v2.efi https://raw.githubusercontent.com/tianocore/edk2/master/ShellBinPkg/UefiShell/X64/Shell.efi
    # EFI Shell 1.0 for non UEFI 2.3+
    curl -o ${work_dir}/iso/EFI/shellx64_v1.efi https://raw.githubusercontent.com/tianocore/edk2/master/EdkShellBinPkg/FullShell/X64/Shell_Full.efi

        fi
}

# Prepare efiboot.img::/EFI for "El Torito" EFI boot mode
make_efiboot() {
        if [[ ${arch} == "x86_64" ]]; then

            mkdir -p ${work_dir}/iso/EFI/archiso
            truncate -s 31M ${work_dir}/iso/EFI/archiso/efiboot.img
            mkfs.fat -n ARCHISO_EFI ${work_dir}/iso/EFI/archiso/efiboot.img

            mkdir -p ${work_dir}/efiboot
            mount ${work_dir}/iso/EFI/archiso/efiboot.img ${work_dir}/efiboot

            mkdir -p ${work_dir}/efiboot/EFI/archiso
            cp ${work_dir}/iso/${install_dir}/boot/vmlinuz ${work_dir}/efiboot/EFI/archiso/vmlinuz.efi
            cp ${work_dir}/iso/${install_dir}/boot/archiso.img ${work_dir}/efiboot/EFI/archiso/archiso.img
            
            cp ${work_dir}/iso/${install_dir}/boot/intel_ucode.img ${work_dir}/efiboot/EFI/archiso/intel_ucode.img

            mkdir -p ${work_dir}/efiboot/EFI/boot
            cp ${work_dir}/root-image/usr/share/efitools/efi/PreLoader.efi ${work_dir}/efiboot/EFI/boot/bootx64.efi
            cp ${work_dir}/root-image/usr/share/efitools/efi/HashTool.efi ${work_dir}/efiboot/EFI/boot/
            cp ${script_path}/efiboot/loader/bg.bmp ${work_dir}/efiboot/EFI/

            cp ${work_dir}/root-image/usr/lib/systemd/boot/efi/systemd-bootx64.efi ${work_dir}/efiboot/EFI/boot/loader.efi
            
            mkdir -p ${work_dir}/efiboot/loader/entries
            cp ${script_path}/efiboot/loader/loader.conf ${work_dir}/efiboot/loader/
            cp ${script_path}/efiboot/loader/entries/uefi-shell-v2-x86_64.conf ${work_dir}/efiboot/loader/entries/
            cp ${script_path}/efiboot/loader/entries/uefi-shell-v1-x86_64.conf ${work_dir}/efiboot/loader/entries/

            for boot_entry in ${script_path}/efiboot/loader/entries/**.conf; do
            	[[ "${boot_entry}" = **'archiso-usb-default'** ]] && continue
            	fname=$(basename ${boot_entry})
            	sed "s|%ARCHISO_LABEL%|${iso_label}|g;
                 	s|%INSTALL_DIR%|${install_dir}|g" ${boot_entry} > ${work_dir}/efiboot/loader/entries/${fname}
            done
            
            for boot_entry in ${work_dir}/efiboot/loader/entries/**.conf; do
            	grep -q '/arch/boot/' "${boot_entry}" || continue
            	sed -i 's|/arch/boot/|/EFI/archiso/|g' "${boot_entry}"
            done

            cp ${work_dir}/iso/EFI/shellx64_v2.efi ${work_dir}/efiboot/EFI/
            cp ${work_dir}/iso/EFI/shellx64_v1.efi ${work_dir}/efiboot/EFI/

            umount -d ${work_dir}/efiboot
    fi
}


# Customize installation (root-image)
make_customize_root_image() {
	part_one() {
        	cp -af ${script_path}/root-image ${work_dir}
        	rm ${work_dir}/root-image/etc/xdg/autostart/pamac-tray.desktop || true
        	ln -sf /usr/share/zoneinfo/UTC ${work_dir}/root-image/etc/localtime
        	chmod 750 ${work_dir}/root-image/etc/sudoers.d
        	chmod 440 ${work_dir}/root-image/etc/sudoers.d/g_wheel
        	mkdir -p ${work_dir}/root-image/etc/pacman.d
        	wget -O ${work_dir}/root-image/etc/pacman.d/mirrorlist 'https://www.archlinux.org/mirrorlist/?country=all&protocol=http&use_mirror_status=on'
        	sed -i "s/#Server/Server/g" ${work_dir}/root-image/etc/pacman.d/mirrorlist
        	#mkdir -p ${work_dir}/root-image/var/run/dbus
        	#mount -o bind /var/run/dbus ${work_dir}/root-image/var/run/dbus
        	# Download opendesktop-fonts
        	#wget --content-disposition -P ${work_dir}/root-image/arch/pkg 'https://www.archlinux.org/packages/community/any/opendesktop-fonts/download/'
        	cp /start/opendesktop**.xz ${work_dir}/root-image/arch/pkg
        	touch /var/tmp/one
        }
        
        part_two() {
        	mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            	-r '/usr/bin/locale-gen' \
            	run
		#mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            #	-r '/usr/bin/localectl set-locale "LANG=en_US.UTF-8" ' \
            #	run || true
            	touch /var/tmp/two 
        }

		part_three() {
			echo "Adding autologin group"
        	mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            	-r 'groupadd -r autologin' \
            	run
            
            echo "Adding nopasswdlogin group"
        	mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            	-r 'groupadd -r nopasswdlogin' \
            	run
	
		echo "Adding antergos user"
        	mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            	-r 'useradd -m -g users -G "audio,disk,optical,wheel,network,autologin,nopasswdlogin" antergos' \
            	run
        
        	mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
           	-r 'passwd -d antergos' \
           	run
           	
           	rm ${work_dir}/root-image/etc/xdg/autostart/vboxclient.desktop
           	
        	touch /var/tmp/three
        }
        
        part_four() {
        	cp ${script_path}/set_password ${work_dir}/root-image/usr/bin
        	chmod +x ${work_dir}/root-image/usr/bin/set_password
        	mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
           	-r '/usr/bin/set_password' \
           	run
           	rm ${work_dir}/root-image/usr/bin/set_password
		#echo "antergos:U6aMy0wojraho" | chpasswd -R /antergos-iso/configs/antergos/${work_dir}/root-image
        	# Configuring pacman
		echo "Configuring Pacman"
        	cp -f ${script_path}/pacman.conf.i686 ${work_dir}/root-image/etc/pacman.conf
        	sed -i 's|^#CheckSpace|CheckSpace|g' ${work_dir}/root-image/etc/pacman.conf
        	sed -i 's|^#SigLevel = Optional TrustedOnly|SigLevel = Optional|g' ${work_dir}/root-image/etc/pacman.conf
        	if [[ ${arch} == 'x86_64' ]]; then
            		echo '' >> ${work_dir}/root-image/etc/pacman.conf
            		echo '[multilib]' >> ${work_dir}/root-image/etc/pacman.conf
            		echo 'SigLevel = PackageRequired' >> ${work_dir}/root-image/etc/pacman.conf
            		echo 'Include = /etc/pacman.d/mirrorlist' >> ${work_dir}/root-image/etc/pacman.conf
        	fi

        	sed -i 's/#\(Storage=\)auto/\1volatile/' ${work_dir}/root-image/etc/systemd/journald.conf
        	sed -i 's|^Exec=|Exec=sudo -E |g' ${work_dir}/root-image/usr/share/applications/gparted.desktop
        	sed -i 's|^Exec=chromium %U|Exec=chromium --user-data-dir=/home/antergos/.config/chromium/Default --start-maximized --homepage=https://antergos.com|g' ${work_dir}/root-image/usr/share/applications/chromium.desktop
        	
        	touch /var/tmp/four
        }
        
        part_five() {
        
        	mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            	-r 'systemctl -fq enable pacman-init lightdm-plymouth plymouth-start NetworkManager ModemManager livecd vboxservice NetworkManager-wait-online ntpd' \
            	run
            	
            mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            	-r 'systemctl -fq disable pamac' \
            	run
            
            # Fix /home permissions
        	mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            	-r 'chown -R antergos:users /home/antergos' \
            	run
            
            # GDK Pixbuf Bug
        	mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            	-r 'gdk-pixbuf-query-loaders --update-cache' \
            	run

            # Pacstrap/Pacman bug where hooks are not run inside the chroot
        	mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            	-r '/usr/bin/update-ca-trust' \
            	run

        	# Fix sudoers
        	chown -R root:root ${work_dir}/root-image/etc/
        	chmod 660 ${work_dir}/root-image/etc/sudoers

        	# Fix QT apps
        	echo 'export GTK2_RC_FILES="$HOME/.gtkrc-2.0"' >> ${work_dir}/root-image/etc/bash.bashrc

        	# Configure powerpill
        	sed -i 's|"ask" : true|"ask" : false|g' ${work_dir}/root-image/etc/powerpill/powerpill.json
        	chmod +x ${work_dir}/root-image/etc/lightdm/Xsession
        
        	# Black list floppy
        	echo "blacklist floppy" > ${work_dir}/root-image/etc/modprobe.d/nofloppy.conf
        	
        	# Install translations for updater script
        	( "${script_path}/translations.sh" $(cd "${out_dir}"; pwd;) $(cd "${work_dir}"; pwd;) $(cd "${script_path}"; pwd;) )
        	
        	touch /var/tmp/five
        }

        parts=(one two three four five)
        for part in ${parts[*]}
        do
        	if [[ ! -f /var/tmp/${part} ]]; then
        		part_${part};
        		sleep 5;
        	fi
        done

}

# Prepare ISO Version Files
make_iso_version_files() {

# Replace <VERSION> with actual iso version in all version files.
base_dir="${work_dir}/root-image/etc"
version_files=('arch-release' 'hostname' 'hosts' 'lsb-release' 'os-release')
year="$(date +'%y')"
month="$(date +'%-m')"
version="${year}.${month}"

echo "${year} ${month} ${version}"

for version_file_name in "${version_files[@]}"
do
	version_file="${base_dir}/${version_file_name}"
	sed -i "s|<VERSION>|${version}|g" "${version_file}"
done
	
}

# Build "dkms" kernel modules.
build_kernel_modules_with_dkms() {

	cp "${script_path}/dkms.sh" "${work_dir}/root-image/usr/bin"
	chmod +x "${work_dir}/root-image/usr/bin/dkms.sh"
	mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
		-r '/usr/bin/dkms.sh' \
		run

}

# Build a single root filesystem
make_prepare() {
    cp -a -l -f ${work_dir}/root-image ${work_dir}

    mkarchiso ${verbose} -z -w "${work_dir}" -D "${install_dir}"  pkglist
    mkarchiso ${verbose} -z -w "${work_dir}" -D "${install_dir}"  prepare

    #rm -rf ${work_dir}/root-image (Always fails and exits the whole build process)
    #rm -rf ${work_dir}/${arch}/root-image (if low space, this helps)
}

# Build ISO
make_iso() {
    #mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" checksum
    if [[ -f "${out_dir}/${iso_name}-${iso_version}-${arch}.iso" ]]; then
        isoName="${iso_name}-${iso_version}-2-${arch}.iso"
    else
        isoName="${iso_name}-${iso_version}-${arch}.iso"
    fi
    mkarchiso ${verbose} -z -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" -L "${iso_label}" -o "${out_dir}" iso "${isoName}"
}

purge_single () {
    if [[ -d ${work_dir} ]]; then
        find ${work_dir} -mindepth 1 -maxdepth 1 \
            ! -path ${work_dir}/iso -prune \
            | xargs rm -rf
    fi
}

clean_single () {
    rm -rf ${work_dir}
    rm -f ${out_dir}/${iso_name}-${iso_version}-*-${arch}.iso
}

# Helper function to run make_*() only one time per architecture.
run_once() {
    if [[ ! -e ${work_dir}/build.${1}_${arch} ]]; then
        $1
        touch ${work_dir}/build.${1}_${arch}
    fi
}

make_common_single() {
    run_once make_basefs
    run_once make_packages
    run_once make_setup_mkinitcpio
    run_once make_customize_root_image
    run_once make_iso_version_files
    run_once build_kernel_modules_with_dkms
    run_once make_boot
    run_once make_boot_extra
    run_once make_syslinux
    run_once make_isolinux
    run_once make_efi
    run_once make_efiboot
    run_once make_prepare
    run_once make_iso
    exit 0;
}

_usage ()
{
    echo "usage ${0} [options] command <command options>"
    echo
    echo " General options:"
    echo "    -N <iso_name>      Set an iso filename (prefix)"
    echo "                        Default: ${iso_name}"
    echo "    -V <iso_version>   Set an iso version (in filename)"
    echo "                        Default: ${iso_version}"
    echo "    -L <iso_label>     Set an iso label (disk label)"
    echo "                        Default: ${iso_label}"
    echo "    -D <install_dir>   Set an install_dir (directory inside iso)"
    echo "                        Default: ${install_dir}"
    echo "    -w <work_dir>      Set the working directory"
    echo "                        Default: ${work_dir}"
    echo "    -o <out_dir>       Set the output directory"
    echo "                        Default: ${out_dir}"
    echo "    -z                 Leave xz packages inside iso"
    echo "    -v                 Enable verbose output"
    echo "    -h                 This help message"
    echo
    echo " Commands:"
    echo "   build <mode>"
    echo "      Build selected .iso by <mode>"
    echo "   purge <mode>"
    echo "      Clean working directory except iso/ directory of build <mode>"
    echo "   clean <mode>"
    echo "      Clean working directory and .iso file in output directory of build <mode>"
    echo
    echo " Command options:"
    echo "         <mode> Valid values 'single', 'dual' or 'all'"
    exit ${1}
}

if [[ ${EUID} -ne 0 ]]; then
    echo "This script must be run as root."
    _usage 1
fi

while getopts 'N:V:L:D:w:o:zvh' arg; do
    case "${arg}" in
        N)
            iso_name="${OPTARG}"
            cmd_args+=" -N ${iso_name}"
            ;;
        V)
            iso_version="${OPTARG}"
            cmd_args+=" -V ${iso_version}"
            ;;
        L)
            iso_label="${OPTARG}"
            cmd_args+=" -L ${iso_label}"
            ;;
        D)
            install_dir="${OPTARG}"
            cmd_args+=" -D ${install_dir}"
            ;;
        w)
            work_dir="${OPTARG}"
            cmd_args+=" -w ${work_dir}"
            ;;
        o)
            out_dir="${OPTARG}"
            cmd_args+=" -o ${out_dir}"
            ;;
        z)
            keep_pacman_packages="y"
            echo "Will keep pacman cache"
            ;;
        v)
            verbose="-v"
            cmd_args+=" -v"
            ;;
        h|?) _usage 0 ;;
        *)
            _msg_error "Invalid argument '${arg}'" 0
            _usage 1
            ;;
    esac
done

shift $((OPTIND - 1))

if [[ $# -lt 1 ]]; then
    echo "No command specified"
    _usage 1
fi
command_name="${1}"


setup_workdir

case "${command_name}" in
    build)
        make_common_single
        ;;
    purge)
        purge_single
        ;;
    clean)
        clean_single
        ;;
esac
