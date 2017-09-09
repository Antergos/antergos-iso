#!/bin/bash
set -euo pipefail

if [ -f config ]; then
    source ./config
else
    # No config file!
    exit 1
fi

KEEP_XZ_FLAG="-z"

# Root filesystem of our ISO image will be created here
ROOTFS=${WORK_DIR}/root-image

# Helper functions
MKARCHISO() {
    mkarchiso ${VERBOSE} ${KEEP_XZ_FLAG} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" "$@"
}

MKARCHISO_RUN() {
    mkarchiso ${VERBOSE} ${KEEP_XZ_FLAG} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" -r "$@" run
}

_usage ()
{
    echo "usage ${0} [options] command <command options>"
    echo
    echo " General options:"
    echo "    -N <iso_name>      Set an iso filename (prefix)"
    echo "                        Default: ${ISO_NAME}"
    echo "    -V <iso_version>   Set an iso version (in filename)"
    echo "                        Default: ${ISO_VERSION}"
    echo "    -L <iso_label>     Set an iso label (disk label)"
    echo "                        Default: ${ISO_LABEL}"
    echo "    -D <install_dir>   Set an install_dir (directory inside iso)"
    echo "                        Default: ${INSTALL_DIR}"
    echo "    -w <work_dir>      Set the working directory"
    echo "                        Default: ${WORK_DIR}"
    echo "    -o <out_dir>       Set the output directory"
    echo "                        Default: ${OUT_DIR}"
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
    if [[ ! -e ${WORK_DIR}/build.${1}_${ARCH} ]]; then
        $1
        touch ${WORK_DIR}/build.${1}_${ARCH}
    fi
}

# Setup custom pacman.conf with current cache directories.
make_pacman_conf() {
    CACHE_DIRS="/var/cache/pacman/pkg"
    PACMAN_CONF="${WORK_DIR}/pacman.conf"
    sed -r "s|^#?\\s*CacheDir.+|CacheDir = $(echo -n ${CACHE_DIRS[@]})|g" "${SCRIPT_PATH}/pacman.conf" > "${PACMAN_CONF}"
}

# Base installation, plus needed packages (root-image)
make_basefs() {
    if [[ ${ISO_NAME} == *"minimal"* ]] || [[ ${ISO_NAME} == *"netcli"* ]]; then
        MKARCHISO init-minimal
    else
        MKARCHISO init
    fi

    MKARCHISO -p "haveged intel-ucode nbd memtest86+" install
}

# Additional packages (root-image)
make_packages() {
    for _file in ${SCRIPT_PATH}/packages/*.packages
    do
        FILEOK="true"
        if [[ "$NVIDIA_DRIVER" == "n" ]] && [[ "${_file}" == *"nvidia"* ]]; then
            # Do not add nvidia driver
            FILEOK="false"
        elif [[ "$NOUVEAU_DRIVER" == "n" ]] && [[ "${_file}" == *"nouveau"* ]]; then
            # Do not add nouveau driver
            FILEOK="false"
        fi

        if [[ "$FILEOK" == "true" ]]; then
            echo
            echo ">>> Installing packages from ${_file}..."
            packages=$(grep -h -v ^# ${_file})
            # Do not add ZFS module if instructed to do so
            if [ "${ADD_ZFS_MODULES}" != "y" ]; then
                packages=$(grep -h -v ^# ${_file} | grep -h -v ^zfs)
            fi
            MKARCHISO -p "${packages}" install
        else
            echo ">>> ${_file} skipped!"
        fi
    done
}

# Needed packages for x86_64 EFI boot
make_packages_efi() {
    MKARCHISO -p "efitools" install
}

# Copy mkinitcpio antiso hooks (root-image)
make_setup_mkinitcpio() {
    local _hook
    mkdir -p ${ROOTFS}/etc/initcpio/hooks
    mkdir -p ${ROOTFS}/etc/initcpio/install
    mkdir -p ${ROOTFS}/usr/lib/initcpio/hooks
    mkdir -p ${ROOTFS}/usr/lib/initcpio/install
    for _hook in archiso archiso_shutdown archiso_pxe_common archiso_pxe_nbd archiso_pxe_http archiso_pxe_nfs archiso_loop_mnt; do
         cp /usr/lib/initcpio/hooks/${_hook} ${ROOTFS}/usr/lib/initcpio/hooks
         cp /usr/lib/initcpio/install/${_hook} ${ROOTFS}/usr/lib/initcpio/install
         cp /usr/lib/initcpio/hooks/${_hook} ${ROOTFS}/etc/initcpio/hooks
         cp /usr/lib/initcpio/install/${_hook} ${ROOTFS}/etc/initcpio/install
    done
    cp /usr/lib/initcpio/install/archiso_kms ${ROOTFS}/usr/lib/initcpio/install
    cp /usr/lib/initcpio/archiso_shutdown ${ROOTFS}/usr/lib/initcpio
    sed -i "s|/usr/lib/initcpio/|/etc/initcpio/|g" ${ROOTFS}/etc/initcpio/install/archiso_shutdown
    cp /usr/lib/initcpio/install/archiso_kms ${ROOTFS}/etc/initcpio/install
    cp /usr/lib/initcpio/archiso_shutdown ${ROOTFS}/etc/initcpio
    cp -L ${SCRIPT_PATH}/mkinitcpio.conf ${ROOTFS}/etc/mkinitcpio-archiso.conf
    cp -L ${SCRIPT_PATH}/root-image/etc/os-release ${ROOTFS}/etc

    if [ -f "${SCRIPT_PATH}/plymouth/plymouthd.conf" ]; then
        cp -L ${SCRIPT_PATH}/plymouth/plymouthd.conf ${ROOTFS}/etc/plymouth
        cp -L ${SCRIPT_PATH}/plymouth/plymouth.initcpio_hook ${ROOTFS}/etc/initcpio/hooks
        cp -L ${SCRIPT_PATH}/plymouth/plymouth.initcpio_install ${ROOTFS}/etc/initcpio/install
        #MKARCHISO_RUN 'plymouth-set-default-theme Antergos-Simple'
        echo '>>> Plymouth done!'
    else
        sed -i 's|plymouth||g' ${ROOTFS}/etc/mkinitcpio-archiso.conf
    fi

    MKARCHISO_RUN 'mkinitcpio -c /etc/mkinitcpio-archiso.conf -k /boot/vmlinuz-linux -g /boot/archiso.img'
    echo '>>> Mkinitcpio done!'
    if [[ ! -f ${ROOTFS}/boot/archiso.img ]]; then
    		echo '>>> Building archiso.img!'
    		arch-chroot "${ROOTFS}" 'mkinitcpio -c /etc/mkinitcpio-archiso.conf -k /boot/vmlinuz-linux -g /boot/archiso.img' 2>&1
    fi
}

# Customize installation (root-image)
make_customize_rootfs() {
    part_one() {
        # Copy specific config root-image (and its contents) to our work dir
        cp -afLR ${SCRIPT_PATH}/root-image ${WORK_DIR}

        if [ -f "${ROOTFS}/etc/xdg/autostart/pamac-tray.desktop" ]; then
            rm ${ROOTFS}/etc/xdg/autostart/pamac-tray.desktop
        fi

        ln -sf /usr/share/zoneinfo/UTC ${ROOTFS}/etc/localtime

        chmod 750 ${ROOTFS}/etc/sudoers.d
        chmod 440 ${ROOTFS}/etc/sudoers.d/g_wheel

        if [ "${ISO_HOTFIX}" == "y" ]; then
            iso_hotfix_utility
        fi

        if [ "${CNCHI_GIT}" == "y" ]; then
            cnchi_git
        fi

        #if [[ ${ISO_NAME} == *"minimal"* ]]; then
        #    remove_extra_icons
        #fi
        if [[ ${ISO_NAME} == *"netcli"* ]]; then
            remove_extra_icons
        fi

        mkdir -p ${ROOTFS}/etc/pacman.d
        wget -O ${ROOTFS}/etc/pacman.d/mirrorlist 'https://www.archlinux.org/mirrorlist/?country=all&protocol=http&use_mirror_status=on'
        sed -i "s/#Server/Server/g" ${ROOTFS}/etc/pacman.d/mirrorlist

        #mkdir -p ${ROOTFS}/var/run/dbus
        #mount -o bind /var/run/dbus ${ROOTFS}/var/run/dbus

        # Download opendesktop-fonts
        #wget --content-disposition -P ${ROOTFS}/arch/pkg 'https://www.archlinux.org/packages/community/any/opendesktop-fonts/download/'
        #cp /start/opendesktop**.xz ${ROOTFS}/arch/pkg
        touch /var/tmp/customize_${ISO_NAME}_rootfs.one
    }

    part_two() {
        MKARCHISO_RUN '/usr/bin/locale-gen'
        touch /var/tmp/customize_${ISO_NAME}_rootfs.two
    }

    part_three() {
        echo "Adding autologin group"
        MKARCHISO_RUN 'groupadd -r autologin'

        echo "Adding nopasswdlogin group"
        MKARCHISO_RUN 'groupadd -r nopasswdlogin'

        echo "Adding antergos user"
        MKARCHISO_RUN 'useradd -m -g users -G "audio,disk,optical,wheel,network,autologin,nopasswdlogin" antergos'

        # Set antergos account passwordless
        MKARCHISO_RUN 'passwd -d antergos'

        # Remove vboxclient from autostart
       	rm -f ${ROOTFS}/etc/xdg/autostart/vboxclient.desktop

    	touch /var/tmp/customize_${ISO_NAME}_rootfs.three
    }

    part_four() {
        cp -L ${SCRIPT_PATH}/set_password ${ROOTFS}/usr/bin
        chmod +x ${ROOTFS}/usr/bin/set_password
        MKARCHISO_RUN '/usr/bin/set_password'

        rm -f ${ROOTFS}/usr/bin/set_password
        #echo "antergos:U6aMy0wojraho" | chpasswd -R /antergos-iso/configs/antergos/${ROOTFS}

        # Configuring pacman
        echo "Configuring Pacman"
        cp -f ${SCRIPT_PATH}/pacman.conf ${ROOTFS}/etc/pacman.conf
        sed -i 's|^#CheckSpace|CheckSpace|g' ${ROOTFS}/etc/pacman.conf
        sed -i 's|^#SigLevel = Optional TrustedOnly|SigLevel = Optional|g' ${ROOTFS}/etc/pacman.conf

        # Setup journal
        sed -i 's/#\(Storage=\)auto/\1volatile/' ${ROOTFS}/etc/systemd/journald.conf

        # Setup gparted execution method if installed
        if [ -f "${ROOTFS}/usr/share/applications/gparted.desktop" ]; then
            sed -i 's|^Exec=|Exec=sudo -E |g' ${ROOTFS}/usr/share/applications/gparted.desktop
        fi

        # Setup Chromium start page if installed
        if [ -f "${ROOTFS}/usr/share/applications/chromium.desktop" ]; then
            sed -i 's|^Exec=chromium %U|Exec=chromium --user-data-dir=/home/antergos/.config/chromium/Default --start-maximized --homepage=https://antergos.com|g' ${ROOTFS}/usr/share/applications/chromium.desktop
        fi

        # Setup Midori start page if installed
        if [ -f "${ROOTFS}/usr/share/applications/midori.desktop" ]; then
            sed -i 's|^Exec=midori %U|Exec=midori https://www.antergos.com|g' ${ROOTFS}/usr/share/applications/midori.desktop
        fi

        touch /var/tmp/customize_${ISO_NAME}_rootfs.four
    }

    part_five() {
        # Enable services
        MKARCHISO_RUN 'systemctl -fq enable pacman-init'

        if [ -f "${ROOTFS}/etc/systemd/system/livecd.service" ]; then
            MKARCHISO_RUN 'systemctl -fq enable livecd'
        fi

        MKARCHISO_RUN 'systemctl -fq enable systemd-networkd'

        if [ -f "${ROOTFS}/usr/lib/systemd/system/NetworkManager.service" ]; then
            MKARCHISO_RUN 'systemctl -fq enable NetworkManager NetworkManager-wait-online'
        fi

        if [ -f "${ROOTFS}/etc/systemd/system/livecd-alsa-unmuter.service" ]; then
            MKARCHISO_RUN 'systemctl -fq enable livecd-alsa-unmuter'
        fi

        if [ -f "${ROOTFS}/etc/systemd/system/vboxservice.service" ]; then
            MKARCHISO_RUN 'systemctl -fq enable vboxservice'
        fi

        MKARCHISO_RUN 'systemctl -fq enable ModemManager'
        MKARCHISO_RUN 'systemctl -fq enable upower'

        if [ -f "${SCRIPT_PATH}/plymouthd.conf" ]; then
            MKARCHISO_RUN 'systemctl -fq enable plymouth-start'
        fi

        if [ -f "${ROOTFS}/etc/systemd/system/lightdm.service" ]; then
            MKARCHISO_RUN 'systemctl -fq enable lightdm'
            chmod +x ${ROOTFS}/etc/lightdm/Xsession
        fi

        if [ -f "${ROOTFS}/etc/systemd/system/gdm.service" ]; then
            MKARCHISO_RUN 'systemctl -fq enable gdm'
            chmod +x ${ROOTFS}/etc/gdm/Xsession
        fi

        # Disable pamac if present
        if [ -f "${ROOTFS}/usr/lib/systemd/system/pamac.service" ]; then
            MKARCHISO_RUN 'systemctl -fq disable pamac pamac-cleancache.timer pamac-mirrorlist.timer'
        fi

        # Useful a11y services for sonar
        if [ -f "${ROOTFS}/usr/lib/systemd/system/espeakup.service" ]; then
            MKARCHISO_RUN 'systemctl -fq enable espeakup'
        fi
        if [ -f "${ROOTFS}/usr/lib/systemd/system/brltty.service" ]; then
            MKARCHISO_RUN 'systemctl -fq enable brltty'
        fi

        # Enable systemd-timesyncd (ntp)
        MKARCHISO_RUN 'systemctl -fq enable systemd-timesyncd'

        # Fix /home permissions
        MKARCHISO_RUN 'chown -R antergos:users /home/antergos'

        # Setup gsettings if gsettings folder exists
        if [ -d ${SCRIPT_PATH}/gsettings ]; then
            # Copying GSettings XML schema files
            mkdir -p ${ROOTFS}/usr/share/glib-2.0/schemas
            for _schema in ${SCRIPT_PATH}/gsettings/*.gschema.override; do
                echo ">>> Will use ${_schema}"
                cp ${_schema} ${ROOTFS}/usr/share/glib-2.0/schemas
            done

            # Compile GSettings XML schema files
            MKARCHISO_RUN '/usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas'
        fi

        # BEGIN Pacstrap/Pacman bug where hooks are not run inside the chroot
        if [ -f ${ROOTFS}/usr/bin/update-ca-trust ]; then
            MKARCHISO_RUN '/usr/bin/update-ca-trust'
        fi
        if [ -f ${ROOTFS}/usr/bin/update-desktop-database ]; then
            MKARCHISO_RUN '/usr/bin/update-desktop-database --quiet'
        fi
        if [ -f ${ROOTFS}/usr/bin/update-mime-database ]; then
            MKARCHISO_RUN '/usr/bin/update-mime-database /usr/share/mime'
        fi
        if [ -f ${ROOTFS}/usr/bin/gdk-pixbuf-query-loaders ]; then
            MKARCHISO_RUN '/usr/bin/gdk-pixbuf-query-loaders --update-cache'
        fi
        # END Pacstrap/Pacman bug

        ## Set multi-user target (text) as default boot mode for net-install
        #MKARCHISO_RUN 'systemctl -fq enable multi-user.target'
        #MKARCHISO_RUN 'systemctl -fq set-default multi-user.target'

        # Fix sudoers
        chown -R root:root ${ROOTFS}/etc/
        chmod 660 ${ROOTFS}/etc/sudoers

        # Fix QT apps
        echo 'export GTK2_RC_FILES="$HOME/.gtkrc-2.0"' >> ${ROOTFS}/etc/bash.bashrc

        # Configure powerpill
        sed -i 's|"ask" : true|"ask" : false|g' ${ROOTFS}/etc/powerpill/powerpill.json

        # Black list floppy
        echo "blacklist floppy" > ${ROOTFS}/etc/modprobe.d/nofloppy.conf

        ## Black list pc speaker
        #echo "blacklist pcspkr" > ${ROOTFS}/etc/modprobe.d/nopcspkr.conf

        # Install translations for updater script
        ( "${SCRIPT_PATH}/translations.sh" $(cd "${OUT_DIR}"; pwd;) $(cd "${WORK_DIR}"; pwd;) $(cd "${SCRIPT_PATH}"; pwd;) )

        echo "Set systemd target"
        if [[ ${ISO_NAME} == *"netcli"* ]]; then
            MKARCHISO_RUN 'systemctl -fq set-default multi-user.target'
        else
            MKARCHISO_RUN 'systemctl -fq set-default graphical.target'
        fi

        touch /var/tmp/customize_${ISO_NAME}_rootfs.five
    }

    # Call all "parts" functions
    parts=(one two three four five)
    for part in ${parts[*]}
    do
        if [[ ! -f /var/tmp/customize_${ISO_NAME}_rootfs.${part} ]]; then
            part_${part};
            sleep 5;
        fi
    done
}

# Install iso_hotfix_utility files to root-image
iso_hotfix_utility() {
    echo
    echo ">>> Installing iso-hotfix-utility..."
    wget "${ISO_HOTFIX_UTILITY_URL}" -O ${SCRIPT_PATH}/iso-hotfix-utility.tar.gz
    tar xfz ${SCRIPT_PATH}/iso-hotfix-utility.tar.gz -C ${SCRIPT_PATH}
    rm -f ${SCRIPT_PATH}/iso-hotfix-utility.tar.gz
    mv "${SCRIPT_PATH}/iso-hotfix-utility-${ISO_HOTFIX_UTILITY_VERSION}" ${SCRIPT_PATH}/iso-hotfix-utility

    cp "${SCRIPT_PATH}/iso-hotfix-utility/iso-hotfix-utility" "${ROOTFS}/usr/bin/pacman-boot"
    chmod 755 "${ROOTFS}/usr/bin/pacman-boot"

    mkdir -p "${ROOTFS}/etc/iso-hotfix-utility.d"

    for _file in ${SCRIPT_PATH}/iso-hotfix-utility/dist/**
    do
        install -m755 -t "${ROOTFS}/etc/iso-hotfix-utility.d" "${_file}"
    done

    for fpath in ${SCRIPT_PATH}/iso-hotfix-utility/po/*; do
        if [[ -f "${fpath}" ]] && [[ "${fpath}" != 'po/CNCHI_UPDATER.pot' ]]; then
            STRING_PO=`echo ${fpath#*/}`
            STRING=`echo ${STRING_PO%.po}`
            mkdir -p "${ROOTFS}/usr/share/locale/${STRING}/LC_MESSAGES"
            msgfmt "${fpath}" -o "${ROOTFS}/usr/share/locale/${STRING}/LC_MESSAGES/CNCHI_UPDATER.mo"
            echo "${STRING} installed..."
        fi
    done
    rm -rf ${SCRIPT_PATH}/iso-hotfix-utility
}

# Install cnchi installer from Git
cnchi_git() {
    echo
    echo ">>> Warning! Installing Cnchi Installer from GIT (${CNCHI_GIT_BRANCH} branch)"
    wget "${CNCHI_GIT_URL}" -O ${SCRIPT_PATH}/cnchi-git.zip
    unzip ${SCRIPT_PATH}/cnchi-git.zip -d ${SCRIPT_PATH}
    rm -f ${SCRIPT_PATH}/cnchi-git.zip

    CNCHI_SRC="${SCRIPT_PATH}/Cnchi-${CNCHI_GIT_BRANCH}"

    install -d ${ROOT_FS}/usr/share/{cnchi,locale}
	install -Dm755 "${CNCHI_SRC}/bin/cnchi" "${ROOT_FS}/usr/bin/cnchi"
	install -Dm755 "${CNCHI_SRC}/cnchi.desktop" "${ROOT_FS}/usr/share/applications/cnchi.desktop"
	install -Dm644 "${CNCHI_SRC}/data/images/antergos/antergos-icon.png" "${ROOT_FS}/usr/share/pixmaps/cnchi.png"

    # TODO: This should be included in Cnchi's src code as a separate file
    # (as both files are needed to run cnchi)
    sed -r -i 's|\/usr.+ -v|pkexec /usr/share/cnchi/bin/cnchi -s bugsnag|g' "${ROOT_FS}/usr/bin/cnchi"

    for i in ${CNCHI_SRC}/cnchi ${CNCHI_SRC}/bin ${CNCHI_SRC}/data ${CNCHI_SRC}/scripts ${CNCHI_SRC}/ui; do
        cp -R ${i} "${ROOT_FS}/usr/share/cnchi/"
    done

    for files in ${CNCHI_SRC}/po/*; do
        if [ -f "$files" ] && [ "$files" != 'po/cnchi.pot' ]; then
            STRING_PO=`echo ${files#*/}`
            STRING=`echo ${STRING_PO%.po}`
            mkdir -p ${ROOT_FS}/usr/share/locale/${STRING}/LC_MESSAGES
            msgfmt $files -o ${ROOT_FS}/usr/share/locale/${STRING}/LC_MESSAGES/cnchi.mo
            echo "${STRING} installed..."
        fi
    done
}

# Prepare ${INSTALL_DIR}/boot/
make_boot() {
    mkdir -p ${WORK_DIR}/iso/${INSTALL_DIR}/boot/
    if [[ -f ${ROOTFS}/boot/archiso.img ]]; then
        cp ${ROOTFS}/boot/archiso.img ${WORK_DIR}/iso/${INSTALL_DIR}/boot/archiso.img
        cp ${ROOTFS}/boot/vmlinuz-linux ${WORK_DIR}/iso/${INSTALL_DIR}/boot/vmlinuz
    else
        echo '>>> work_dir is ${WORK_DIR}'
        ls ${WORK_DIR} && ls ${ROOTFS}/ && ls ${ROOTFS}/boot/
    fi
}

# Add other aditional/extra files to ${INSTALL_DIR}/boot/
make_boot_extra() {
    if [[ -f ${ROOTFS}/boot/memtest86+/memtest.bin ]]; then
        cp ${ROOTFS}/boot/memtest86+/memtest.bin ${WORK_DIR}/iso/${INSTALL_DIR}/boot/memtest
    fi

    if [[ -f ${ROOTFS}/usr/share/licenses/common/GPL2/license.txt ]]; then
        cp ${ROOTFS}/usr/share/licenses/common/GPL2/license.txt ${WORK_DIR}/iso/${INSTALL_DIR}/boot/memtest.COPYING
    fi

    cp ${ROOTFS}/boot/intel-ucode.img ${WORK_DIR}/iso/${INSTALL_DIR}/boot/intel_ucode.img
    cp ${ROOTFS}/usr/share/licenses/intel-ucode/LICENSE ${WORK_DIR}/iso/${INSTALL_DIR}/boot/intel_ucode.LICENSE
}

# Prepare /${INSTALL_DIR}/boot/syslinux
make_syslinux() {
    mkdir -p ${WORK_DIR}/iso/${INSTALL_DIR}/boot/syslinux
    for _cfg in ${SCRIPT_PATH}/isolinux/*.cfg; do
        sed "s|%ARCHISO_LABEL%|${ISO_LABEL}|g;
             s|%INSTALL_DIR%|${INSTALL_DIR}|g;
             s|%ARCH%|${ARCH}|g" ${_cfg} > ${WORK_DIR}/iso/${INSTALL_DIR}/boot/syslinux/${_cfg##*/}
    done
    cp -LR ${SCRIPT_PATH}/isolinux ${WORK_DIR}/iso/${INSTALL_DIR}/boot/syslinux
    cp ${ROOTFS}/usr/lib/syslinux/bios/*.c32 ${WORK_DIR}/iso/${INSTALL_DIR}/boot/syslinux
    cp ${ROOTFS}/usr/lib/syslinux/bios/lpxelinux.0 ${WORK_DIR}/iso/${INSTALL_DIR}/boot/syslinux
    cp ${ROOTFS}/usr/lib/syslinux/bios/memdisk ${WORK_DIR}/iso/${INSTALL_DIR}/boot/syslinux
    mkdir -p ${WORK_DIR}/iso/${INSTALL_DIR}/boot/syslinux/hdt
    gzip -c -9 ${ROOTFS}/usr/share/hwdata/pci.ids > ${WORK_DIR}/iso/${INSTALL_DIR}/boot/syslinux/hdt/pciids.gz
    gzip -c -9 ${ROOTFS}/usr/lib/modules/*-ARCH/modules.alias > ${WORK_DIR}/iso/${INSTALL_DIR}/boot/syslinux/hdt/modalias.gz
}

# Prepare /isolinux
make_isolinux() {
    mkdir -p ${WORK_DIR}/iso/isolinux
    cp -LR ${SCRIPT_PATH}/isolinux ${WORK_DIR}/iso
    cp -R ${ROOTFS}/usr/lib/syslinux/bios/* ${WORK_DIR}/iso/isolinux/
    cp ${ROOTFS}/usr/lib/syslinux/bios/*.c32 ${WORK_DIR}/iso/isolinux/
    sed "s|%ARCHISO_LABEL%|${ISO_LABEL}|g;
         s|%INSTALL_DIR%|${INSTALL_DIR}|g;
         s|%ARCH%|${ARCH}|g" ${SCRIPT_PATH}/isolinux/isolinux.cfg > ${WORK_DIR}/iso/isolinux/isolinux.cfg
    cp ${ROOTFS}/usr/lib/syslinux/bios/isolinux.bin ${WORK_DIR}/iso/isolinux/
    cp ${ROOTFS}/usr/lib/syslinux/bios/isohdpfx.bin ${WORK_DIR}/iso/isolinux/
    cp ${ROOTFS}/usr/lib/syslinux/bios/lpxelinux.0 ${WORK_DIR}/iso/isolinux/
}


# Prepare /EFI
make_efi() {
    mkdir -p ${WORK_DIR}/iso/EFI/boot
    cp ${ROOTFS}/usr/share/efitools/efi/PreLoader.efi ${WORK_DIR}/iso/EFI/boot/bootx64.efi
    cp ${ROOTFS}/usr/share/efitools/efi/HashTool.efi ${WORK_DIR}/iso/EFI/boot/
    cp ${SCRIPT_PATH}/efiboot/loader/bg.bmp ${WORK_DIR}/iso/EFI/

    cp ${ROOTFS}/usr/lib/systemd/boot/efi/systemd-bootx64.efi ${WORK_DIR}/iso/EFI/boot/loader.efi

    mkdir -p ${WORK_DIR}/iso/loader/entries
    cp ${SCRIPT_PATH}/efiboot/loader/loader.conf ${WORK_DIR}/iso/loader/
    cp ${SCRIPT_PATH}/efiboot/loader/entries/uefi-shell-v2-x86_64.conf ${WORK_DIR}/iso/loader/entries/
    cp ${SCRIPT_PATH}/efiboot/loader/entries/uefi-shell-v1-x86_64.conf ${WORK_DIR}/iso/loader/entries/

    for boot_entry in ${SCRIPT_PATH}/efiboot/loader/entries/**.conf; do
        [[ "${boot_entry}" = **'archiso-cd'** ]] && continue
        fname=$(basename ${boot_entry})
        sed "s|%ARCHISO_LABEL%|${ISO_LABEL}|g;
            s|%INSTALL_DIR%|${INSTALL_DIR}|g" ${boot_entry} > ${WORK_DIR}/iso/loader/entries/${fname}
    done

   # EFI Shell 2.0 for UEFI 2.3+
   curl -o ${WORK_DIR}/iso/EFI/shellx64_v2.efi https://raw.githubusercontent.com/tianocore/edk2/master/ShellBinPkg/UefiShell/X64/Shell.efi
   # EFI Shell 1.0 for non UEFI 2.3+
   curl -o ${WORK_DIR}/iso/EFI/shellx64_v1.efi https://raw.githubusercontent.com/tianocore/edk2/master/EdkShellBinPkg/FullShell/X64/Shell_Full.efi
}


# Prepare efiboot.img::/EFI for "El Torito" EFI boot mode
make_efiboot() {
    mkdir -p ${WORK_DIR}/iso/EFI/archiso
    truncate -s 64M ${WORK_DIR}/iso/EFI/archiso/efiboot.img
    mkfs.fat -n ARCHISO_EFI ${WORK_DIR}/iso/EFI/archiso/efiboot.img

    mkdir -p ${WORK_DIR}/efiboot
    mount ${WORK_DIR}/iso/EFI/archiso/efiboot.img ${WORK_DIR}/efiboot

    mkdir -p ${WORK_DIR}/efiboot/EFI/archiso
    cp ${WORK_DIR}/iso/${INSTALL_DIR}/boot/vmlinuz ${WORK_DIR}/efiboot/EFI/archiso/vmlinuz.efi
    cp ${WORK_DIR}/iso/${INSTALL_DIR}/boot/archiso.img ${WORK_DIR}/efiboot/EFI/archiso/archiso.img

    cp ${WORK_DIR}/iso/${INSTALL_DIR}/boot/intel_ucode.img ${WORK_DIR}/efiboot/EFI/archiso/intel_ucode.img

    mkdir -p ${WORK_DIR}/efiboot/EFI/boot
    cp ${ROOTFS}/usr/share/efitools/efi/PreLoader.efi ${WORK_DIR}/efiboot/EFI/boot/bootx64.efi
    cp ${ROOTFS}/usr/share/efitools/efi/HashTool.efi ${WORK_DIR}/efiboot/EFI/boot/
    cp ${SCRIPT_PATH}/efiboot/loader/bg.bmp ${WORK_DIR}/efiboot/EFI/

    cp ${ROOTFS}/usr/lib/systemd/boot/efi/systemd-bootx64.efi ${WORK_DIR}/efiboot/EFI/boot/loader.efi

    mkdir -p ${WORK_DIR}/efiboot/loader/entries
    cp ${SCRIPT_PATH}/efiboot/loader/loader.conf ${WORK_DIR}/efiboot/loader/
    cp ${SCRIPT_PATH}/efiboot/loader/entries/uefi-shell-v2-x86_64.conf ${WORK_DIR}/efiboot/loader/entries/
    cp ${SCRIPT_PATH}/efiboot/loader/entries/uefi-shell-v1-x86_64.conf ${WORK_DIR}/efiboot/loader/entries/

    for boot_entry in ${SCRIPT_PATH}/efiboot/loader/entries/**.conf; do
        [[ "${boot_entry}" = **'archiso-usb-default'** ]] && continue
        fname=$(basename ${boot_entry})
        sed "s|%ARCHISO_LABEL%|${ISO_LABEL}|g;
            s|%INSTALL_DIR%|${INSTALL_DIR}|g" ${boot_entry} > ${WORK_DIR}/efiboot/loader/entries/${fname}
    done

    for boot_entry in ${WORK_DIR}/efiboot/loader/entries/**.conf; do
        grep -q '/arch/boot/' "${boot_entry}" || continue
        sed -i 's|/arch/boot/|/EFI/archiso/|g' "${boot_entry}"
    done

    cp ${WORK_DIR}/iso/EFI/shellx64_v2.efi ${WORK_DIR}/efiboot/EFI/
    cp ${WORK_DIR}/iso/EFI/shellx64_v1.efi ${WORK_DIR}/efiboot/EFI/

    umount -d ${WORK_DIR}/efiboot
}

# Remove unused icons (should only be used by minimal and netcli installations)
remove_extra_icons() {
    if [[ -d "${ROOTFS}/usr/share/icons" ]]; then
        echo
        echo ">>> Removing extra icons..."
        cd ${ROOTFS}/usr/share/icons
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
    base_dir="${ROOTFS}/etc"
    version_files=('arch-release' 'hostname' 'hosts' 'lsb-release' 'os-release')

    # Replace <VERSION> with actual iso version in all version files.
    for version_file_name in "${version_files[@]}"
    do
        version_file="${base_dir}/${version_file_name}"
        sed -i "s|<VERSION>|${ISO_VERSION}|g" "${version_file}"
    done
}

# Build "dkms" kernel modules.
make_kernel_modules_with_dkms() {
    if [[ ! -f /var/tmp/customize_${ISO_NAME}_rootfs.dkms ]]; then
        # Build kernel modules that are handled by dkms so we can delete kernel headers to save space
        MKARCHISO_RUN 'dkms autoinstall'

        if [ "${ADD_ZFS_MODULES}" == "y" ]; then
            # Bugfix (sometimes pacman tries to build zfs before spl!)
            cp "${SCRIPT_PATH}/dkms.sh" "${ROOTFS}/usr/bin"
            chmod +x "${ROOTFS}/usr/bin/dkms.sh"
            MKARCHISO_RUN '/usr/bin/dkms.sh'
        fi

        # Removing linux-headers makes dkms hook delete broadcom-wl driver!
        # Remove kernel headers.
        #MKARCHISO -r 'pacman -Rdd --noconfirm linux-headers' run

        touch /var/tmp/customize_${ISO_NAME}_rootfs.dkms
    fi
}

# Build a single root filesystem
make_prepare() {
    cp -a -l -f ${ROOTFS} ${WORK_DIR}

    MKARCHISO pkglist
    MKARCHISO prepare
}

# Build ISO
make_iso() {
    if [[ -f "${OUT_DIR}/${ISO_NAME}-${ISO_VERSION}-${ARCH}.iso" ]]; then
        FULL_ISO_NAME="${ISO_NAME}-${ISO_VERSION}-2-${ARCH}.iso"
    else
        FULL_ISO_NAME="${ISO_NAME}-${ISO_VERSION}-${ARCH}.iso"
    fi
    echo ">>> Building ${FULL_ISO_NAME}..."
    MKARCHISO -L "${ISO_LABEL}" -o "${OUT_DIR}" iso "${FULL_ISO_NAME}"
}

# Cleans rootfs
clean_rootfs() {
    rm -rf ${WORK_DIR}/*
    rm -f /var/tmp/customize_${ISO_NAME}_rootfs.*

    # Clean isolinux directory created by translations.sh script
    if [ -d ${SCRIPT_PATH}/isolinux ]; then
        rm -rf ${SCRIPT_PATH}/isolinux
    fi
}

# Cleans rootfs and deletes iso files
purge_rootfs() {
    clean_rootfs
    rm -f ${OUT_DIR}/*.iso
}

make_all() {
    echo ">>> Building ${ISO_NAME}..."

    if [[ "${KEEP_XZ}" == "n" ]]; then
        echo ">>> Will REMOVE cached xz packages from ISO!"
    else
        echo ">>> Will KEEP cached xz packages in ISO!"
    fi

    echo ">>> (1/16) make pacman.conf"
    run_once make_pacman_conf
    echo ">>> (2/16) make basefs"
    run_once make_basefs
    echo ">>> (3/16) make packages"
    run_once make_packages
    echo ">>> (4/16) make efi packages"
    run_once make_packages_efi
    echo ">>> (5/16) make mkinitcpio setup"
    run_once make_setup_mkinitcpio
    echo ">>> (6/16) make customize rootfs"
    run_once make_customize_rootfs
    echo ">>> (7/16) make iso version files"
    run_once make_iso_version_files
    echo ">>> (8/16) make kernel modules (dkms)"
    run_once make_kernel_modules_with_dkms
    echo ">>> (9/16) make boot"
    run_once make_boot
    echo ">>> (10/16) make boot (extra)"
    run_once make_boot_extra
    echo ">>> (11/16) make syslinux"
    run_once make_syslinux
    echo ">>> (12/16) make isolinux"
    run_once make_isolinux
    echo ">>> (13/16) make efi"
    run_once make_efi
    echo ">>> (14/16) make efi boot"
    run_once make_efiboot
    echo ">>> (15/16) make prepare"
    run_once make_prepare
    echo ">>> (16/16) make iso"
    run_once make_iso
    exit 0;
}

# Program starts here ---------------------------------------------------------

if [[ ${EUID} -ne 0 ]]; then
    echo "This script must be run as root."
    _usage 1
fi

if [[ ${ARCH} != x86_64 ]]; then
    echo "This script needs to be run on x86_64"
    _usage 1
fi

# Add nvidia to the iso name if nvidia proprietary drivers are used but
# and the nouveau ones are not included
if [[ "$NVIDIA_DRIVER" == "y" ]] && [[ "$NOUVEAU_DRIVER" == "n" ]]; then
    ISO_NAME=${ISO_NAME}-nvidia
fi

# Add nozfs to the iso name if no zfs modules are in it
if [ "${ADD_ZFS_MODULES}" != "y" ]; then
    ISO_NAME=${ISO_NAME}-nozfs
fi

# Set KEEP_XZ_FLAG variable from KEEP_XZ
if [[ "${KEEP_XZ}" == "y" ]]; then
    KEEP_XZ_FLAG="-z"
else
    KEEP_XZ_FLAG=""
fi

if [[ "${KEEP_XZ}" != "y" ]]; then
    # Show in iso name that no xz packages are cached in the ISO
    ISO_NAME=${ISO_NAME}-noxz
fi

while getopts 'N:V:L:D:w:o:vh' ARG; do
    case "${ARG}" in
        N) ISO_NAME="${OPTARG}" ;;
        V) ISO_VERSION="${OPTARG}" ;;
        L) ISO_LABEL="${OPTARG}" ;;
        D) INSTALL_DIR="${OPTARG}" ;;
        w) WORK_DIR="${OPTARG}" ;;
        o) OUT_DIR="${OPTARG}" ;;
        v) VERBOSE="-v" ;;
        h) _usage 0 ;;
        *)
            echo "Invalid argument '${ARG}'"
            _usage 1
            ;;
    esac
done

mkdir -p ${WORK_DIR}
mkdir -p ${OUT_DIR}

shift $((OPTIND - 1))

if [[ $# -lt 1 ]]; then
    echo "No command specified"
    _usage 1
fi

COMMAND_NAME="${1}"

case "${COMMAND_NAME}" in
    build)
        make_all
        ;;
    clean)
        clean_rootfs
        ;;
    purge)
        purge_rootfs
        ;;
    make)
        make_iso
        ;;
esac
