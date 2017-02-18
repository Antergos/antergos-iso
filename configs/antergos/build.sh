#!/bin/bash

set -e -u

iso_name="antergos"
iso_label="ANTERGOS"

year="$(date +'%y')"
month="$(date +'%-m')"
iso_version="${year}.${month}"

install_dir="arch"
work_dir=work
out_dir=/out

arch=$(uname -m)
verbose="-v"
script_path=$(readlink -f ${0%/*})

# To keep pacman xz packages use keep="-z"
keep=""
pacman_conf="${work_dir}/pacman.conf"


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
    echo "    -z                 Keep xz packages inside iso"
    echo "    -v                 Enable verbose output"
    echo "    -h                 This help message"
    echo
    echo " Commands:"
    echo "   build"
    echo "      Build selected .iso"
    echo "   clean"
    echo "      Clean working directory"
    echo "   purge"
    echo "      Clean working directory and .iso file in output directory of build"
    echo
    exit ${1}
}

# Helper function to run make_*() only one time per architecture.
run_once() {
    if [[ ! -e ${work_dir}/build.${1}_${arch} ]]; then
        $1
        touch ${work_dir}/build.${1}_${arch}
    fi
}

# Setup custom pacman.conf with current cache directories.
make_pacman_conf() {
    cache_dirs="/var/cache/pacman/pkg"
    pacman_conf="${work_dir}/pacman.conf"
    sed -r "s|^#?\\s*CacheDir.+|CacheDir = $(echo -n ${cache_dirs[@]})|g" "${script_path}/pacman.conf" > "${pacman_conf}"
}

# Base installation, plus needed packages (root-image)
make_basefs() {
    mkarchiso ${verbose} ${keep} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" init
    mkarchiso ${verbose} ${keep} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" -p "haveged intel-ucode nbd" install
}

# Additional packages (root-image)
make_packages() {
    for _file in ${script_path}/packages/*.packages
    do
        echo
        echo ">>> Installing packages from ${_file}..."
        mkarchiso ${verbose} ${keep} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" -p "$(grep -h -v ^# ${_file})" install
    done
}

# Needed packages for x86_64 EFI boot
make_packages_efi() {
    mkarchiso ${verbose} ${keep} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" -p "efitools" install
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

    if [ -f "${script_path}/plymouth/plymouthd.conf" ]; then
        cp -L ${script_path}/plymouth/plymouthd.conf ${work_dir}/root-image/etc/plymouth
        cp -L ${script_path}/plymouth/plymouth.initcpio_hook ${work_dir}/root-image/etc/initcpio/hooks
        cp -L ${script_path}/plymouth/plymouth.initcpio_install ${work_dir}/root-image/etc/initcpio/install
        #mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" -r 'plymouth-set-default-theme Antergos-Simple' run 2&>1
        echo '>>> Plymouth done!'
    else
        sed -i 's|plymouth||g' ${work_dir}/root-image/etc/mkinitcpio-archiso.conf
    fi

    mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
        -r 'mkinitcpio -c /etc/mkinitcpio-archiso.conf -k /boot/vmlinuz-linux -g /boot/archiso.img' run
    echo '>>> Mkinitcpio done!'
    if [[ ! -f ${work_dir}/root-image/boot/archiso.img ]]; then
    		echo '>>> Building archiso.img!'
    		arch-chroot "${work_dir}/root-image" 'mkinitcpio -c /etc/mkinitcpio-archiso.conf -k /boot/vmlinuz-linux -g /boot/archiso.img' 2>&1
    fi

}

# Customize installation (root-image)
make_customize_rootfs() {
    part_one() {
        cp -afLR ${script_path}/root-image ${work_dir}
        if [ -f "${work_dir}/root-image/etc/xdg/autostart/pamac-tray.desktop" ]; then
            rm ${work_dir}/root-image/etc/xdg/autostart/pamac-tray.desktop
        fi
        ln -sf /usr/share/zoneinfo/UTC ${work_dir}/root-image/etc/localtime
        chmod 750 ${work_dir}/root-image/etc/sudoers.d
        chmod 440 ${work_dir}/root-image/etc/sudoers.d/g_wheel

        iso_hotfix_utility

        #mkdir -p ${work_dir}/root-image/etc/pacman.d
        #wget -O ${work_dir}/root-image/etc/pacman.d/mirrorlist 'https://www.archlinux.org/mirrorlist/?country=all&protocol=http&use_mirror_status=on'
        #sed -i "s/#Server/Server/g" ${work_dir}/root-image/etc/pacman.d/mirrorlist

        #mkdir -p ${work_dir}/root-image/var/run/dbus
        #mount -o bind /var/run/dbus ${work_dir}/root-image/var/run/dbus

        # Download opendesktop-fonts
        #wget --content-disposition -P ${work_dir}/root-image/arch/pkg 'https://www.archlinux.org/packages/community/any/opendesktop-fonts/download/'
        #cp /start/opendesktop**.xz ${work_dir}/root-image/arch/pkg
        touch /var/tmp/customize_${iso_name}_rootfs.one
    }

    part_two() {
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r '/usr/bin/locale-gen' run
        touch /var/tmp/customize_${iso_name}_rootfs.two
    }

    part_three() {
        echo "Adding autologin group"
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r 'groupadd -r autologin' run

        echo "Adding nopasswdlogin group"
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r 'groupadd -r nopasswdlogin' run

        echo "Adding antergos user"
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r 'useradd -m -g users -G "audio,disk,optical,wheel,network,autologin,nopasswdlogin" antergos' run

        # Set antergos account passwordless
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r 'passwd -d antergos' run

        echo "Set systemd target"
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r 'systemctl set-default -f graphical.target' run

       	rm ${work_dir}/root-image/etc/xdg/autostart/vboxclient.desktop
    	touch /var/tmp/customize_${iso_name}_rootfs.three
    }

    part_four() {
        cp -L ${script_path}/set_password ${work_dir}/root-image/usr/bin
        chmod +x ${work_dir}/root-image/usr/bin/set_password
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r '/usr/bin/set_password' run

        rm ${work_dir}/root-image/usr/bin/set_password
        #echo "antergos:U6aMy0wojraho" | chpasswd -R /antergos-iso/configs/antergos/${work_dir}/root-image

        # Configuring pacman
        echo "Configuring Pacman"
        cp -f ${script_path}/pacman.conf ${work_dir}/root-image/etc/pacman.conf
        sed -i 's|^#CheckSpace|CheckSpace|g' ${work_dir}/root-image/etc/pacman.conf
        sed -i 's|^#SigLevel = Optional TrustedOnly|SigLevel = Optional|g' ${work_dir}/root-image/etc/pacman.conf

        # Setup journal
        sed -i 's/#\(Storage=\)auto/\1volatile/' ${work_dir}/root-image/etc/systemd/journald.conf
        # Setup gparted execution method
        sed -i 's|^Exec=|Exec=sudo -E |g' ${work_dir}/root-image/usr/share/applications/gparted.desktop

        # Setup Chromium start page if installed
        if [ -f "${work_dir}/root-image/usr/share/applications/chromium.desktop" ]; then
            sed -i 's|^Exec=chromium %U|Exec=chromium --user-data-dir=/home/antergos/.config/chromium/Default --start-maximized --homepage=https://antergos.com|g' ${work_dir}/root-image/usr/share/applications/chromium.desktop
        else
            echo ">>> Chromium not installed."
        fi

        # Setup Midori start page if installed
        if [ -f "${work_dir}/root-image/usr/share/applications/midori.desktop" ]; then
            sed -i 's|^Exec=midori %U|Exec=midori https://www.antergos.com|g' ${work_dir}/root-image/usr/share/applications/midori.desktop
        fi

        touch /var/tmp/customize_${iso_name}_rootfs.four
    }

    part_five() {
        # Enable services
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r 'systemctl -fq enable pacman-init NetworkManager livecd vboxservice NetworkManager-wait-online systemd-networkd' run

        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r 'systemctl -fq enable ModemManager' run

        if [ -f "${script_path}/plymouthd.conf" ]; then
            mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
                -r 'systemctl -fq enable plymouth-start' run
        fi

        if [ -f "${work_dir}/root-image/etc/systemd/system/lightdm.service" ]; then
            mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
                -r 'systemctl -fq enable lightdm' run
            chmod +x ${work_dir}/root-image/etc/lightdm/Xsession
        fi

        if [ -f "${work_dir}/root-image/etc/systemd/system/gdm.service" ]; then
            mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
                -r 'systemctl -fq enable gdm' run
            chmod +x ${work_dir}/root-image/etc/gdm/Xsession
        fi

        # Disable pamac if present
        if [ -f "${work_dir}/root-image/usr/lib/systemd/system/pamac.service" ]; then
            mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
                -r 'systemctl -fq disable pamac pamac-cleancache.timer pamac-mirrorlist.timer' run
        fi

        # Enable systemd-timesyncd (ntp)
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r 'systemctl -fq enable systemd-timesyncd.service' run

        # Fix /home permissions
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r 'chown -R antergos:users /home/antergos' run

        # BEGIN Pacstrap/Pacman bug where hooks are not run inside the chroot
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r '/usr/bin/update-ca-trust' run

        # Copying GSettings XML schema files
        mkdir -p ${work_dir}/root-image/usr/share/glib-2.0/schemas
        for _schema in ${script_path}/gsettings/*.gschema.override; do
            echo ">>> Will use ${_schema}"
            cp ${_schema} ${work_dir}/root-image/usr/share/glib-2.0/schemas
        done

        # Compiling GSettings XML schema files
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r '/usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas' run

        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r '/usr/bin/update-desktop-database --quiet' run

        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r '/usr/bin/update-mime-database /usr/share/mime' run

        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r '/usr/bin/gdk-pixbuf-query-loaders --update-cache' run
        # END Pacstrap/Pacman bug

        # Fix sudoers
        chown -R root:root ${work_dir}/root-image/etc/
        chmod 660 ${work_dir}/root-image/etc/sudoers

        # Fix QT apps
        echo 'export GTK2_RC_FILES="$HOME/.gtkrc-2.0"' >> ${work_dir}/root-image/etc/bash.bashrc

        # Configure powerpill
        sed -i 's|"ask" : true|"ask" : false|g' ${work_dir}/root-image/etc/powerpill/powerpill.json

        # Black list floppy
        echo "blacklist floppy" > ${work_dir}/root-image/etc/modprobe.d/nofloppy.conf

        ## Black list pc speaker
        #echo "blacklist pcspkr" > ${work_dir}/root-image/etc/modprobe.d/nopcspkr.conf

        # Install translations for updater script
        ( "${script_path}/translations.sh" $(cd "${out_dir}"; pwd;) $(cd "${work_dir}"; pwd;) $(cd "${script_path}"; pwd;) )

        touch /var/tmp/customize_${iso_name}_rootfs.five
    }

    # Call all "parts" functions
    parts=(one two three four five)
    for part in ${parts[*]}
    do
        if [[ ! -f /var/tmp/customize_${iso_name}_rootfs.${part} ]]; then
            part_${part};
            sleep 5;
        fi
    done
}

# Copy iso_hotfix_utility files to root-image
iso_hotfix_utility() {
    echo ">>> Installing iso-hotfix-utility..."
    cp ${script_path}/iso-hotfix-utility/iso-hotfix-utility ${work_dir}/root-image/usr/bin/pacman-boot
    chmod 755 ${work_dir}/root-image/usr/bin/pacman-boot

    mkdir -p "${work_dir}/root-image/etc/iso-hotfix-utility.d"

    for _file in ${script_path}/iso-hotfix-utility/dist/**
    do
        install -m755 -t "${work_dir}/root-image/etc/iso-hotfix-utility.d" "${_file}"
    done

    for fpath in ${script_path}/iso-hotfix-utility/po/*; do
        if [[ -f "${fpath}" ]] && [[ "${fpath}" != 'po/CNCHI_UPDATER.pot' ]]; then
            STRING_PO=`echo ${fpath#*/}`
            STRING=`echo ${STRING_PO%.po}`
            mkdir -p "${work_dir}/root-image/usr/share/locale/${STRING}/LC_MESSAGES"
            msgfmt "${fpath}" -o "${work_dir}/root-image/usr/share/locale/${STRING}/LC_MESSAGES/CNCHI_UPDATER.mo"
            echo "${STRING} installed..."
        fi
    done
}

# Prepare ${install_dir}/boot/
make_boot() {
    mkdir -p ${work_dir}/iso/${install_dir}/boot/
    if [[ -f ${work_dir}/root-image/boot/archiso.img ]]; then
        cp ${work_dir}/root-image/boot/archiso.img ${work_dir}/iso/${install_dir}/boot/archiso.img
        cp ${work_dir}/root-image/boot/vmlinuz-linux ${work_dir}/iso/${install_dir}/boot/vmlinuz
    else
        echo '>>> work_dir is ${work_dir}'
        ls ${work_dir} && ls ${work_dir}/root-image/ && ls ${work_dir}/root-image/boot/
    fi
}

# Add other aditional/extra files to ${install_dir}/boot/
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
    cp -LR ${script_path}/isolinux ${work_dir}/iso/${install_dir}/boot/syslinux
    cp ${work_dir}/root-image/usr/lib/syslinux/bios/*.c32 ${work_dir}/iso/${install_dir}/boot/syslinux
    cp ${work_dir}/root-image/usr/lib/syslinux/bios/lpxelinux.0 ${work_dir}/iso/${install_dir}/boot/syslinux
    cp ${work_dir}/root-image/usr/lib/syslinux/bios/memdisk ${work_dir}/iso/${install_dir}/boot/syslinux
    mkdir -p ${work_dir}/iso/${install_dir}/boot/syslinux/hdt
    gzip -c -9 ${work_dir}/root-image/usr/share/hwdata/pci.ids > ${work_dir}/iso/${install_dir}/boot/syslinux/hdt/pciids.gz
    gzip -c -9 ${work_dir}/root-image/usr/lib/modules/*-ARCH/modules.alias > ${work_dir}/iso/${install_dir}/boot/syslinux/hdt/modalias.gz
}

# Prepare /isolinux
make_isolinux() {
    mkdir -p ${work_dir}/iso/isolinux
    cp -LR isolinux ${work_dir}/iso
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
}


# Prepare efiboot.img::/EFI for "El Torito" EFI boot mode
make_efiboot() {
    mkdir -p ${work_dir}/iso/EFI/archiso
    truncate -s 64M ${work_dir}/iso/EFI/archiso/efiboot.img
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
}

# Remove unused icons (should only be used by minimal installation)
remove_extra_icons() {
    if [[ -d "${work_dir}/root-image/usr/share/icons" ]]; then
        cd ${work_dir}/root-image/usr/share/icons
        find . \
            ! -iname '**Cnchi**' \
            ! -iname '**image-missing.svg**' \
            ! -iname '**emblem-default.svg**' \
            ! -iname '**dialog-warning.svg**' \
            ! -iname '**edit-undo**' \
            ! -iname '**list-add**' \
            ! -iname '**list-remove**' \
            ! -iname '**system-run**' \
            ! -iname '**edit-clear-all**' \
            ! -iname 'dialog-***' \
            ! -iname '**-yes.svg**' \
            ! -iname '**_yes.svg**' \
            ! -iname '**-no.svg**' \
            ! -iname '**stock_no.svg**' \
            ! -iname 'nm-***' \
            ! -iname '**system-software-install**' \
            ! -iname '***bluetooth***' \
            ! -iname '***printer***' \
            ! -iname '***firefox***' \
            ! -iname '**network-server**' \
            ! -iname '***preferences-desktop-font***' \
            ! -iname '**fonts**' \
            ! -iname '**applications-accessories**' \
            ! -iname '**text-editor**' \
            ! -iname '**accessories-text-editor**' \
            ! -iname '**gnome-mime-x-directory-smb-share**' \
            ! -iname '**terminal**' \
            ! -iname '**video-display**' \
            ! -iname '**go-next-symbolic**' \
            ! -iname '**go-previous-symbolic**' \
            ! -iname '**_close**' \
            ! -iname '**-close**' \
            ! -iname '**dialog-**' \
            ! -iname 'nm-**' \
            ! -iname 'window-**' \
            ! -iname '**network**' \
            ! -iname 'index.theme' \
            ! -iname '**system-shutdown**' \
            ! -iname '**pan-**' \
            ! -iname '**symbolic**' \
            ! -ipath '**Adwaita**' \
            ! -ipath '**highcolor**' \
            -type f -delete
    fi
}

# Prepare ISO Version Files
make_iso_version_files() {
    base_dir="${work_dir}/root-image/etc"
    version_files=('arch-release' 'hostname' 'hosts' 'lsb-release' 'os-release')

    # Replace <VERSION> with actual iso version in all version files.
    for version_file_name in "${version_files[@]}"
    do
        version_file="${base_dir}/${version_file_name}"
        sed -i "s|<VERSION>|${iso_version}|g" "${version_file}"
    done
}

# Build "dkms" kernel modules.
make_kernel_modules_with_dkms() {
    if [[ ! -f /var/tmp/customize_${iso_name}_rootfs.dkms ]]; then
        # Build kernel modules that are handled by dkms so we can delete kernel headers to save space
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r 'dkms autoinstall' run

        # Remove kernel headers and dkms.
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r 'pacman -Rdd --noconfirm linux-headers dkms' run

        # Bugfix
        cp "${script_path}/dkms.sh" "${work_dir}/root-image/usr/bin"
        chmod +x "${work_dir}/root-image/usr/bin/dkms.sh"
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r '/usr/bin/dkms.sh' run

        touch /var/tmp/customize_${iso_name}_rootfs.dkms
    fi
}

# Build a single root filesystem
make_prepare() {
    cp -a -l -f ${work_dir}/root-image ${work_dir}

    mkarchiso ${verbose} -z -w "${work_dir}" -D "${install_dir}" pkglist
    mkarchiso ${verbose} -z -w "${work_dir}" -D "${install_dir}" prepare
}

# Build ISO
make_iso() {
    if [[ -f "${out_dir}/${iso_name}-${iso_version}-${arch}.iso" ]]; then
        isoName="${iso_name}-${iso_version}-2-${arch}.iso"
    else
        isoName="${iso_name}-${iso_version}-${arch}.iso"
    fi
    mkarchiso ${verbose} -z -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" -L "${iso_label}" -o "${out_dir}" iso "${isoName}"
}

# Cleans rootfs
clean_rootfs() {
    rm -rf ${work_dir}
    rm -f /var/tmp/customize_${iso_name}_rootfs.*
}

# Cleans rootfs and deletes iso files
purge_rootfs() {
    clean_rootfs
    rm -f ${out_dir}/${iso_name}-${iso_version}-*-${arch}.iso
}

make_all() {
    run_once make_pacman_conf
    run_once make_basefs
    run_once make_packages
    run_once make_packages_efi
    run_once make_setup_mkinitcpio
    run_once make_customize_rootfs
    run_once make_iso_version_files
    run_once make_kernel_modules_with_dkms
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


# Program starts here

if [[ ${EUID} -ne 0 ]]; then
    echo "This script must be run as root."
    _usage 1
fi

if [[ ${arch} != x86_64 ]]; then
    echo "This script needs to be run on x86_64"
    _usage 1
fi

# Get ISO name from iso_name.txt file
if [ -f "${script_path}/iso_name.txt" ]; then
    iso_name=$(cat ${script_path}/iso_name.txt)
fi

while getopts 'N:V:L:D:w:o:zvh' arg; do
    case "${arg}" in
        N) iso_name="${OPTARG}" ;;
        V) iso_version="${OPTARG}" ;;
        L) iso_label="${OPTARG}" ;;
        D) install_dir="${OPTARG}" ;;
        w) work_dir="${OPTARG}" ;;
        o) out_dir="${OPTARG}" ;;
        z) keep="-z"
           echo ">>> Will keep pacman cache in ISO file" ;;
        v) verbose="-v" ;;
        h) _usage 0 ;;
        *)
            echo "Invalid argument '${arg}'"
            _usage 1
            ;;
    esac
done

mkdir -p ${work_dir}

shift $((OPTIND - 1))

if [[ $# -lt 1 ]]; then
    echo "No command specified"
    _usage 1
fi

command_name="${1}"

case "${command_name}" in
    build)
        make_all
        ;;
    clean)
        clean_rootfs
        ;;
    purge)
        purge_rootfs
        ;;
esac
