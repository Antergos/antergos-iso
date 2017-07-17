#!/bin/bash

set -e -u

ISO_NAME="antergos"
ISO_LABEL="ANTERGOS"

YEAR="$(date +'%y')"
MONTH="$(date +'%-m')"
ISO_VERSION="${YEAR}.${MONTH}"

INSTALL_DIR="arch"
WORK_DIR="/work"
OUT_DIR="/out"

ARCH=$(uname -m)
VERBOSE="-v"
SCRIPT_PATH=$(readlink -f ${0%/*})

# Add ZFS modules
ADD_ZFS_MODULES="y"

# Keep xz packages in cache (minimal will always remove them)
KEEP_XZ="y"

# Install iso-hotfix-utility from source
ISO_HOTFIX="y"
ISO_HOTFIX_UTILITY_VERSION="1.0.17"
ISO_HOTFIX_UTILITY_URL="https://github.com/Antergos/iso-hotfix-utility/archive/${ISO_HOTFIX_UTILITY_VERSION}.tar.gz"

# Pacman configuration file
PACMAN_CONF="${WORK_DIR}/pacman.conf"

# Get ISO name from iso_name.txt file
if [ -f "${SCRIPT_PATH}/version.txt" ]; then
    ISO_NAME=${ISO_NAME}-$(cat ${SCRIPT_PATH}/version.txt)
fi

if [ "${ADD_ZFS_MODULES}" != "y" ]; then
    ISO_NAME=${ISO_NAME}-nozfs
fi

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

    # Will remove cached pacman xz packages when the
    # iso name contains "minimal" in its name
    if [[ ${ISO_NAME} == *"minimal"* ]]; then
        KEEP_XZ="n"
        KEEP_XZ_FLAG=""
    elif [[ "${KEEP_XZ}" == "n" ]]; then
        # Iso is not minimal, but it won't contain any cached packages either.
        # Add it to the iso name, so everybody knows.
        ISO_NAME=${ISO_NAME}-nocache
    fi

    if [[ "${KEEP_XZ}" == "n" ]]; then
        echo ">>> Will REMOVE cached xz packages from ISO!"
    else
        echo ">>> Will KEEP cached xz packages from ISO!"
    fi
}

# Base installation, plus needed packages (root-image)
make_basefs() {
    mkarchiso ${VERBOSE} ${KEEP_XZ_FLAG} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" init
    mkarchiso ${VERBOSE} ${KEEP_XZ_FLAG} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" -p "haveged intel-ucode nbd memtest86+" install
}

# Additional packages (root-image)
make_packages() {
    for _file in ${SCRIPT_PATH}/packages/*.packages
    do
        echo
        echo ">>> Installing packages from ${_file}..."
        packages=$(grep -h -v ^# ${_file})
        if [ "${ADD_ZFS_MODULES}" != "y" ]; then
            packages=$(grep -h -v ^# ${_file} | grep -h -v ^zfs)
        fi
        mkarchiso ${VERBOSE} ${KEEP_XZ_FLAG} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" -p "${packages}" install
    done
}

# Needed packages for x86_64 EFI boot
make_packages_efi() {
    mkarchiso ${VERBOSE} ${KEEP_XZ_FLAG} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" -p "efitools" install
}

# Copy mkinitcpio archiso hooks (root-image)
make_setup_mkinitcpio() {
    local _hook
    mkdir -p ${WORK_DIR}/root-image/etc/initcpio/hooks
    mkdir -p ${WORK_DIR}/root-image/etc/initcpio/install
    mkdir -p ${WORK_DIR}/root-image/usr/lib/initcpio/hooks
    mkdir -p ${WORK_DIR}/root-image/usr/lib/initcpio/install
    for _hook in archiso archiso_shutdown archiso_pxe_common archiso_pxe_nbd archiso_pxe_http archiso_pxe_nfs archiso_loop_mnt; do
         cp /usr/lib/initcpio/hooks/${_hook} ${WORK_DIR}/root-image/usr/lib/initcpio/hooks
         cp /usr/lib/initcpio/install/${_hook} ${WORK_DIR}/root-image/usr/lib/initcpio/install
         cp /usr/lib/initcpio/hooks/${_hook} ${WORK_DIR}/root-image/etc/initcpio/hooks
         cp /usr/lib/initcpio/install/${_hook} ${WORK_DIR}/root-image/etc/initcpio/install
    done
    cp /usr/lib/initcpio/install/archiso_kms ${WORK_DIR}/root-image/usr/lib/initcpio/install
    cp /usr/lib/initcpio/archiso_shutdown ${WORK_DIR}/root-image/usr/lib/initcpio
    sed -i "s|/usr/lib/initcpio/|/etc/initcpio/|g" ${WORK_DIR}/root-image/etc/initcpio/install/archiso_shutdown
    cp /usr/lib/initcpio/install/archiso_kms ${WORK_DIR}/root-image/etc/initcpio/install
    cp /usr/lib/initcpio/archiso_shutdown ${WORK_DIR}/root-image/etc/initcpio
    cp -L ${SCRIPT_PATH}/mkinitcpio.conf ${WORK_DIR}/root-image/etc/mkinitcpio-archiso.conf
    cp -L ${SCRIPT_PATH}/root-image/etc/os-release ${WORK_DIR}/root-image/etc

    if [ -f "${SCRIPT_PATH}/plymouth/plymouthd.conf" ]; then
        cp -L ${SCRIPT_PATH}/plymouth/plymouthd.conf ${WORK_DIR}/root-image/etc/plymouth
        cp -L ${SCRIPT_PATH}/plymouth/plymouth.initcpio_hook ${WORK_DIR}/root-image/etc/initcpio/hooks
        cp -L ${SCRIPT_PATH}/plymouth/plymouth.initcpio_install ${WORK_DIR}/root-image/etc/initcpio/install
        #mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" -r 'plymouth-set-default-theme Antergos-Simple' run 2&>1
        echo '>>> Plymouth done!'
    else
        sed -i 's|plymouth||g' ${WORK_DIR}/root-image/etc/mkinitcpio-archiso.conf
    fi

    mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
        -r 'mkinitcpio -c /etc/mkinitcpio-archiso.conf -k /boot/vmlinuz-linux -g /boot/archiso.img' run
    echo '>>> Mkinitcpio done!'
    if [[ ! -f ${WORK_DIR}/root-image/boot/archiso.img ]]; then
    		echo '>>> Building archiso.img!'
    		arch-chroot "${WORK_DIR}/root-image" 'mkinitcpio -c /etc/mkinitcpio-archiso.conf -k /boot/vmlinuz-linux -g /boot/archiso.img' 2>&1
    fi
}

# Customize installation (root-image)
make_customize_rootfs() {
    part_one() {
        cp -afLR ${SCRIPT_PATH}/root-image ${WORK_DIR}
        if [ -f "${WORK_DIR}/root-image/etc/xdg/autostart/pamac-tray.desktop" ]; then
            rm ${WORK_DIR}/root-image/etc/xdg/autostart/pamac-tray.desktop
        fi
        ln -sf /usr/share/zoneinfo/UTC ${WORK_DIR}/root-image/etc/localtime
        chmod 750 ${WORK_DIR}/root-image/etc/sudoers.d
        chmod 440 ${WORK_DIR}/root-image/etc/sudoers.d/g_wheel

        if [ "${ISO_HOTFIX}" == "y" ]; then
            iso_hotfix_utility
        fi

        if [[ ${ISO_NAME} == *"minimal"* ]]; then
            remove_extra_icons
        fi

        mkdir -p ${WORK_DIR}/root-image/etc/pacman.d
        wget -O ${WORK_DIR}/root-image/etc/pacman.d/mirrorlist 'https://www.archlinux.org/mirrorlist/?country=all&protocol=http&use_mirror_status=on'
        sed -i "s/#Server/Server/g" ${WORK_DIR}/root-image/etc/pacman.d/mirrorlist

        #mkdir -p ${WORK_DIR}/root-image/var/run/dbus
        #mount -o bind /var/run/dbus ${WORK_DIR}/root-image/var/run/dbus

        # Download opendesktop-fonts
        #wget --content-disposition -P ${WORK_DIR}/root-image/arch/pkg 'https://www.archlinux.org/packages/community/any/opendesktop-fonts/download/'
        #cp /start/opendesktop**.xz ${WORK_DIR}/root-image/arch/pkg
        touch /var/tmp/customize_${ISO_NAME}_rootfs.one
    }

    part_two() {
        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r '/usr/bin/locale-gen' run
        touch /var/tmp/customize_${ISO_NAME}_rootfs.two
    }

    part_three() {
        echo "Adding autologin group"
        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r 'groupadd -r autologin' run

        echo "Adding nopasswdlogin group"
        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r 'groupadd -r nopasswdlogin' run

        echo "Adding antergos user"
        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r 'useradd -m -g users -G "audio,disk,optical,wheel,network,autologin,nopasswdlogin" antergos' run

        # Set antergos account passwordless
        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r 'passwd -d antergos' run

        echo "Set systemd target"
        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r 'systemctl set-default -f graphical.target' run

       	rm ${WORK_DIR}/root-image/etc/xdg/autostart/vboxclient.desktop
    	touch /var/tmp/customize_${ISO_NAME}_rootfs.three
    }

    part_four() {
        cp -L ${SCRIPT_PATH}/set_password ${WORK_DIR}/root-image/usr/bin
        chmod +x ${WORK_DIR}/root-image/usr/bin/set_password
        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r '/usr/bin/set_password' run

        rm ${WORK_DIR}/root-image/usr/bin/set_password
        #echo "antergos:U6aMy0wojraho" | chpasswd -R /antergos-iso/configs/antergos/${WORK_DIR}/root-image

        # Configuring pacman
        echo "Configuring Pacman"
        cp -f ${SCRIPT_PATH}/pacman.conf ${WORK_DIR}/root-image/etc/pacman.conf
        sed -i 's|^#CheckSpace|CheckSpace|g' ${WORK_DIR}/root-image/etc/pacman.conf
        sed -i 's|^#SigLevel = Optional TrustedOnly|SigLevel = Optional|g' ${WORK_DIR}/root-image/etc/pacman.conf

        # Setup journal
        sed -i 's/#\(Storage=\)auto/\1volatile/' ${WORK_DIR}/root-image/etc/systemd/journald.conf
        # Setup gparted execution method
        sed -i 's|^Exec=|Exec=sudo -E |g' ${WORK_DIR}/root-image/usr/share/applications/gparted.desktop

        # Setup Chromium start page if installed
        if [ -f "${WORK_DIR}/root-image/usr/share/applications/chromium.desktop" ]; then
            sed -i 's|^Exec=chromium %U|Exec=chromium --user-data-dir=/home/antergos/.config/chromium/Default --start-maximized --homepage=https://antergos.com|g' ${WORK_DIR}/root-image/usr/share/applications/chromium.desktop
        else
            echo ">>> Chromium not installed."
        fi

        # Setup Midori start page if installed
        if [ -f "${WORK_DIR}/root-image/usr/share/applications/midori.desktop" ]; then
            sed -i 's|^Exec=midori %U|Exec=midori https://www.antergos.com|g' ${WORK_DIR}/root-image/usr/share/applications/midori.desktop
        fi

        touch /var/tmp/customize_${ISO_NAME}_rootfs.four
    }

    part_five() {
        # Enable services
        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r 'systemctl -fq enable pacman-init NetworkManager livecd vboxservice NetworkManager-wait-online systemd-networkd' run

        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r 'systemctl -fq enable ModemManager upower' run

        if [ -f "${SCRIPT_PATH}/plymouthd.conf" ]; then
            mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
                -r 'systemctl -fq enable plymouth-start' run
        fi

        if [ -f "${WORK_DIR}/root-image/etc/systemd/system/lightdm.service" ]; then
            mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
                -r 'systemctl -fq enable lightdm' run
            chmod +x ${WORK_DIR}/root-image/etc/lightdm/Xsession
        fi

        if [ -f "${WORK_DIR}/root-image/etc/systemd/system/gdm.service" ]; then
            mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
                -r 'systemctl -fq enable gdm' run
            chmod +x ${WORK_DIR}/root-image/etc/gdm/Xsession
        fi

        # Disable pamac if present
        if [ -f "${WORK_DIR}/root-image/usr/lib/systemd/system/pamac.service" ]; then
            mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
                -r 'systemctl -fq disable pamac pamac-cleancache.timer pamac-mirrorlist.timer' run
        fi

        # Enable systemd-timesyncd (ntp)
        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r 'systemctl -fq enable systemd-timesyncd.service' run

        # Fix /home permissions
        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r 'chown -R antergos:users /home/antergos' run

        # BEGIN Pacstrap/Pacman bug where hooks are not run inside the chroot
        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r '/usr/bin/update-ca-trust' run

        # Copying GSettings XML schema files
        mkdir -p ${WORK_DIR}/root-image/usr/share/glib-2.0/schemas
        for _schema in ${SCRIPT_PATH}/gsettings/*.gschema.override; do
            echo ">>> Will use ${_schema}"
            cp ${_schema} ${WORK_DIR}/root-image/usr/share/glib-2.0/schemas
        done

        # Compile GSettings XML schema files
        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r '/usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas' run

        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r '/usr/bin/update-desktop-database --quiet' run

        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r '/usr/bin/update-mime-database /usr/share/mime' run

        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r '/usr/bin/gdk-pixbuf-query-loaders --update-cache' run
        # END Pacstrap/Pacman bug

        # Fix sudoers
        chown -R root:root ${WORK_DIR}/root-image/etc/
        chmod 660 ${WORK_DIR}/root-image/etc/sudoers

        # Fix QT apps
        echo 'export GTK2_RC_FILES="$HOME/.gtkrc-2.0"' >> ${WORK_DIR}/root-image/etc/bash.bashrc

        # Configure powerpill
        sed -i 's|"ask" : true|"ask" : false|g' ${WORK_DIR}/root-image/etc/powerpill/powerpill.json

        # Black list floppy
        echo "blacklist floppy" > ${WORK_DIR}/root-image/etc/modprobe.d/nofloppy.conf

        ## Black list pc speaker
        #echo "blacklist pcspkr" > ${WORK_DIR}/root-image/etc/modprobe.d/nopcspkr.conf

        # Install translations for updater script
        ( "${SCRIPT_PATH}/translations.sh" $(cd "${OUT_DIR}"; pwd;) $(cd "${WORK_DIR}"; pwd;) $(cd "${SCRIPT_PATH}"; pwd;) )

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
    mv "${SCRIPT_PATH}/iso-hotfix-utility-${ISO_HOTFIX_UTILITY_VERSION}" ${SCRIPT_PATH}/iso-hotfix-utility

    cp "${SCRIPT_PATH}/iso-hotfix-utility/iso-hotfix-utility" "${WORK_DIR}/root-image/usr/bin/pacman-boot"
    chmod 755 "${WORK_DIR}/root-image/usr/bin/pacman-boot"

    mkdir -p "${WORK_DIR}/root-image/etc/iso-hotfix-utility.d"

    for _file in ${SCRIPT_PATH}/iso-hotfix-utility/dist/**
    do
        install -m755 -t "${WORK_DIR}/root-image/etc/iso-hotfix-utility.d" "${_file}"
    done

    for fpath in ${SCRIPT_PATH}/iso-hotfix-utility/po/*; do
        if [[ -f "${fpath}" ]] && [[ "${fpath}" != 'po/CNCHI_UPDATER.pot' ]]; then
            STRING_PO=`echo ${fpath#*/}`
            STRING=`echo ${STRING_PO%.po}`
            mkdir -p "${WORK_DIR}/root-image/usr/share/locale/${STRING}/LC_MESSAGES"
            msgfmt "${fpath}" -o "${WORK_DIR}/root-image/usr/share/locale/${STRING}/LC_MESSAGES/CNCHI_UPDATER.mo"
            echo "${STRING} installed..."
        fi
    done
}

# Prepare ${INSTALL_DIR}/boot/
make_boot() {
    mkdir -p ${WORK_DIR}/iso/${INSTALL_DIR}/boot/
    if [[ -f ${WORK_DIR}/root-image/boot/archiso.img ]]; then
        cp ${WORK_DIR}/root-image/boot/archiso.img ${WORK_DIR}/iso/${INSTALL_DIR}/boot/archiso.img
        cp ${WORK_DIR}/root-image/boot/vmlinuz-linux ${WORK_DIR}/iso/${INSTALL_DIR}/boot/vmlinuz
    else
        echo '>>> work_dir is ${WORK_DIR}'
        ls ${WORK_DIR} && ls ${WORK_DIR}/root-image/ && ls ${WORK_DIR}/root-image/boot/
    fi
}

# Add other aditional/extra files to ${INSTALL_DIR}/boot/
make_boot_extra() {
    cp ${WORK_DIR}/root-image/boot/memtest86+/memtest.bin ${WORK_DIR}/iso/${INSTALL_DIR}/boot/memtest
    cp ${WORK_DIR}/root-image/usr/share/licenses/common/GPL2/license.txt ${WORK_DIR}/iso/${INSTALL_DIR}/boot/memtest.COPYING
    cp ${WORK_DIR}/root-image/boot/intel-ucode.img ${WORK_DIR}/iso/${INSTALL_DIR}/boot/intel_ucode.img
    cp ${WORK_DIR}/root-image/usr/share/licenses/intel-ucode/LICENSE ${WORK_DIR}/iso/${INSTALL_DIR}/boot/intel_ucode.LICENSE
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
    cp ${WORK_DIR}/root-image/usr/lib/syslinux/bios/*.c32 ${WORK_DIR}/iso/${INSTALL_DIR}/boot/syslinux
    cp ${WORK_DIR}/root-image/usr/lib/syslinux/bios/lpxelinux.0 ${WORK_DIR}/iso/${INSTALL_DIR}/boot/syslinux
    cp ${WORK_DIR}/root-image/usr/lib/syslinux/bios/memdisk ${WORK_DIR}/iso/${INSTALL_DIR}/boot/syslinux
    mkdir -p ${WORK_DIR}/iso/${INSTALL_DIR}/boot/syslinux/hdt
    gzip -c -9 ${WORK_DIR}/root-image/usr/share/hwdata/pci.ids > ${WORK_DIR}/iso/${INSTALL_DIR}/boot/syslinux/hdt/pciids.gz
    gzip -c -9 ${WORK_DIR}/root-image/usr/lib/modules/*-ARCH/modules.alias > ${WORK_DIR}/iso/${INSTALL_DIR}/boot/syslinux/hdt/modalias.gz
}

# Prepare /isolinux
make_isolinux() {
    mkdir -p ${WORK_DIR}/iso/isolinux
    cp -LR isolinux ${WORK_DIR}/iso
    cp -R ${WORK_DIR}/root-image/usr/lib/syslinux/bios/* ${WORK_DIR}/iso/isolinux/
    cp ${WORK_DIR}/root-image/usr/lib/syslinux/bios/*.c32 ${WORK_DIR}/iso/isolinux/
    sed "s|%ARCHISO_LABEL%|${ISO_LABEL}|g;
         s|%INSTALL_DIR%|${INSTALL_DIR}|g;
         s|%ARCH%|${ARCH}|g" ${SCRIPT_PATH}/isolinux/isolinux.cfg > ${WORK_DIR}/iso/isolinux/isolinux.cfg
    cp ${WORK_DIR}/root-image/usr/lib/syslinux/bios/isolinux.bin ${WORK_DIR}/iso/isolinux/
    cp ${WORK_DIR}/root-image/usr/lib/syslinux/bios/isohdpfx.bin ${WORK_DIR}/iso/isolinux/
    cp ${WORK_DIR}/root-image/usr/lib/syslinux/bios/lpxelinux.0 ${WORK_DIR}/iso/isolinux/
}


# Prepare /EFI
make_efi() {
    mkdir -p ${WORK_DIR}/iso/EFI/boot
    cp ${WORK_DIR}/root-image/usr/share/efitools/efi/PreLoader.efi ${WORK_DIR}/iso/EFI/boot/bootx64.efi
    cp ${WORK_DIR}/root-image/usr/share/efitools/efi/HashTool.efi ${WORK_DIR}/iso/EFI/boot/
    cp ${SCRIPT_PATH}/efiboot/loader/bg.bmp ${WORK_DIR}/iso/EFI/

    cp ${WORK_DIR}/root-image/usr/lib/systemd/boot/efi/systemd-bootx64.efi ${WORK_DIR}/iso/EFI/boot/loader.efi

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
    cp ${WORK_DIR}/root-image/usr/share/efitools/efi/PreLoader.efi ${WORK_DIR}/efiboot/EFI/boot/bootx64.efi
    cp ${WORK_DIR}/root-image/usr/share/efitools/efi/HashTool.efi ${WORK_DIR}/efiboot/EFI/boot/
    cp ${SCRIPT_PATH}/efiboot/loader/bg.bmp ${WORK_DIR}/efiboot/EFI/

    cp ${WORK_DIR}/root-image/usr/lib/systemd/boot/efi/systemd-bootx64.efi ${WORK_DIR}/efiboot/EFI/boot/loader.efi

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

# Remove unused icons (should only be used by minimal installation)
remove_extra_icons() {
    if [[ -d "${WORK_DIR}/root-image/usr/share/icons" ]]; then
        echo
        echo ">>> Removing extra icons..."
        cd ${WORK_DIR}/root-image/usr/share/icons
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
    base_dir="${WORK_DIR}/root-image/etc"
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
        mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
            -r 'dkms autoinstall' run

        if [ "${ADD_ZFS_MODULES}" == "y" ]; then
            # Bugfix (sometimes pacman tries to build zfs before spl!)
            cp "${SCRIPT_PATH}/dkms.sh" "${WORK_DIR}/root-image/usr/bin"
            chmod +x "${WORK_DIR}/root-image/usr/bin/dkms.sh"
            mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
                -r '/usr/bin/dkms.sh' run
        fi

        # Removing linux-headers makes dkms hook delete broadcom-wl driver!
        # Remove kernel headers.
        #mkarchiso ${VERBOSE} -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" \
        #    -r 'pacman -Rdd --noconfirm linux-headers' run

        touch /var/tmp/customize_${ISO_NAME}_rootfs.dkms
    fi
}

# Build a single root filesystem
make_prepare() {
    cp -a -l -f ${WORK_DIR}/root-image ${WORK_DIR}

    mkarchiso ${VERBOSE} -z -w "${WORK_DIR}" -D "${INSTALL_DIR}" pkglist
    mkarchiso ${VERBOSE} -z -w "${WORK_DIR}" -D "${INSTALL_DIR}" prepare
}

# Build ISO
make_iso() {
    if [[ -f "${OUT_DIR}/${ISO_NAME}-${ISO_VERSION}-${ARCH}.iso" ]]; then
        FULL_ISO_NAME="${ISO_NAME}-${ISO_VERSION}-2-${ARCH}.iso"
    else
        FULL_ISO_NAME="${ISO_NAME}-${ISO_VERSION}-${ARCH}.iso"
    fi
    mkarchiso ${VERBOSE} -z -w "${WORK_DIR}" -C "${PACMAN_CONF}" -D "${INSTALL_DIR}" -L "${ISO_LABEL}" -o "${OUT_DIR}" iso "${FULL_ISO_NAME}"
}

# Cleans rootfs
clean_rootfs() {
    rm -rf ${WORK_DIR}/*
    rm -f /var/tmp/customize_${ISO_NAME}_rootfs.*
}

# Cleans rootfs and deletes iso files
purge_rootfs() {
    clean_rootfs
    rm -f ${OUT_DIR}/${ISO_NAME}-${ISO_VERSION}-*-${ARCH}.iso
}

make_all() {
    echo ">>> Building ${ISO_NAME}..."

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

if [[ ${ARCH} != x86_64 ]]; then
    echo "This script needs to be run on x86_64"
    _usage 1
fi

KEEP_XZ_FLAG=""
if [[ "${KEEP_XZ}" == "y" ]]; then
    KEEP_XZ_FLAG="-z"
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
esac
