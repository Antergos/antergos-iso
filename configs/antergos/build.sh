#!/bin/bash

set -e -u

iso_name=antergos
iso_label="ANTERGOS"
iso_version=$(date +%Y.%m.%d)
install_dir=arch
arch=$(uname -m)
work_dir=work
out_dir=out
verbose=""
cmd_args=""

script_path=$(readlink -f ${0%/*})

setup_workdir() {
    #cache_dirs=($(pacman -v 2>&1 | grep '^Cache Dirs:' | sed 's/Cache Dirs:\s*//g'))
    cache_dirs="/var/cache/pacman/pkg_${arch}"
    mkdir -p "${work_dir}"
    pacman_conf="${work_dir}/pacman.conf"
    sed -r "s|^#?\\s*CacheDir.+|CacheDir = $(echo -n ${cache_dirs[@]})|g" \
        "${script_path}/pacman.conf.${arch}" > "${pacman_conf}"
}

# Base installation (root-image)
make_basefs() {
    mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" init
    mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" -p "memtest86+ mkinitcpio-nfs-utils nbd" install
}

# Additional packages (root-image)
make_packages() {
    mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" -p "$(grep -h -v ^# ${script_path}/packages.{both,${arch}})" install
}

# Copy mkinitcpio archiso hooks (root-image)
make_setup_mkinitcpio() {
    local _hook
    for _hook in archiso archiso_shutdown archiso_pxe_common archiso_pxe_nbd archiso_pxe_http archiso_pxe_nfs archiso_loop_mnt; do
        cp /usr/lib/initcpio/hooks/${_hook} ${work_dir}/root-image/usr/lib/initcpio/hooks
        cp /usr/lib/initcpio/install/${_hook} ${work_dir}/root-image/usr/lib/initcpio/install
    done
    cp /usr/lib/initcpio/install/archiso_kms ${work_dir}/root-image/usr/lib/initcpio/install
    cp /usr/lib/initcpio/archiso_shutdown ${work_dir}/root-image/usr/lib/initcpio
    cp ${script_path}/mkinitcpio.conf ${work_dir}/root-image/etc/mkinitcpio-archiso.conf
    mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" -r 'mkinitcpio -c /etc/mkinitcpio-archiso.conf -k /boot/vmlinuz-linux -g /boot/archiso.img' run
}

# Prepare ${install_dir}/boot/
make_boot() {
    mkdir -p ${work_dir}/iso/${install_dir}/boot/
    cp ${work_dir}/root-image/boot/archiso.img ${work_dir}/iso/${install_dir}/boot/archiso.img
    cp ${work_dir}/root-image/boot/vmlinuz-linux ${work_dir}/iso/${install_dir}/boot/vmlinuz
}

make_boot_extra() {
    cp ${work_dir}/root-image/boot/memtest86+/memtest.bin ${work_dir}/iso/${install_dir}/boot/memtest
    cp ${work_dir}/root-image/usr/share/licenses/common/GPL2/license.txt ${work_dir}/iso/${install_dir}/boot/memtest.COPYING
}


make_isolinux() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        cp -Lr isolinux ${work_dir}/iso
        cp -R ${work_dir}/root-image/usr/lib/syslinux/bios/* ${work_dir}/iso/isolinux/
        sed "s|%ARCHISO_LABEL%|${iso_label}|g;
                s|%INSTALL_DIR%|${install_dir}|g;
                s|%ARCH%|${arch}|g" ${script_path}/isolinux/isolinux.cfg > ${work_dir}/iso/isolinux/isolinux.cfg
        : > ${work_dir}/build.${FUNCNAME}
    fi
}

# Prepare /EFI
make_efi() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        if [[ ${arch} == "x86_64" ]]; then

            mkdir -p ${work_dir}/iso/EFI/boot
            cp ${work_dir}/root-image/usr/lib/gummiboot/gummibootx64.efi ${work_dir}/iso/EFI/boot/bootx64.efi

            mkdir -p ${work_dir}/iso/loader/entries
            cp ${script_path}/efiboot/loader/loader.conf ${work_dir}/iso/loader/
            cp ${script_path}/efiboot/loader/entries/uefi-shell-v2-x86_64.conf ${work_dir}/iso/loader/entries/
            cp ${script_path}/efiboot/loader/entries/uefi-shell-v1-x86_64.conf ${work_dir}/iso/loader/entries/

            sed "s|%ARCHISO_LABEL%|${iso_label}|g;
                 s|%INSTALL_DIR%|${install_dir}|g" ${script_path}/efiboot/loader/entries/archiso-x86_64-usb.conf > ${work_dir}/iso/loader/entries/archiso-x86_64.conf

            # EFI Shell 2.0 for UEFI 2.3+ ( http://sourceforge.net/apps/mediawiki/tianocore/index.php?title=UEFI_Shell )
            wget -O ${work_dir}/iso/EFI/shellx64_v2.efi https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2/ShellBinPkg/UefiShell/X64/Shell.efi
            # EFI Shell 1.0 for non UEFI 2.3+ ( http://sourceforge.net/apps/mediawiki/tianocore/index.php?title=Efi-shell )
            wget -O ${work_dir}/iso/EFI/shellx64_v1.efi https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2/EdkShellBinPkg/FullShell/X64/Shell_Full.efi

        fi
        : > ${work_dir}/build.${FUNCNAME}
    fi
}

# Prepare efiboot.img::/EFI for "El Torito" EFI boot mode
make_efiboot() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        if [[ ${arch} == "x86_64" ]]; then

            mkdir -p ${work_dir}/iso/EFI/archiso
            truncate -s 31M ${work_dir}/iso/EFI/archiso/efiboot.img
            mkfs.vfat -n ARCHISO_EFI ${work_dir}/iso/EFI/archiso/efiboot.img

            mkdir -p ${work_dir}/efiboot
            mount ${work_dir}/iso/EFI/archiso/efiboot.img ${work_dir}/efiboot

            mkdir -p ${work_dir}/efiboot/EFI/archiso
            cp ${work_dir}/iso/${install_dir}/boot/vmlinuz ${work_dir}/efiboot/EFI/archiso/vmlinuz.efi
            cp ${work_dir}/iso/${install_dir}/boot/archiso.img ${work_dir}/efiboot/EFI/archiso/archiso.img

            mkdir -p ${work_dir}/efiboot/EFI/boot
            cp ${work_dir}/root-image/usr/lib/gummiboot/gummibootx64.efi ${work_dir}/efiboot/EFI/boot/bootx64.efi

            mkdir -p ${work_dir}/efiboot/loader/entries
            cp ${script_path}/efiboot/loader/loader.conf ${work_dir}/efiboot/loader/
            cp ${script_path}/efiboot/loader/entries/uefi-shell-v2-x86_64.conf ${work_dir}/efiboot/loader/entries/
            cp ${script_path}/efiboot/loader/entries/uefi-shell-v1-x86_64.conf ${work_dir}/efiboot/loader/entries/

            sed "s|%ARCHISO_LABEL%|${iso_label}|g;
                 s|%INSTALL_DIR%|${install_dir}|g" ${script_path}/efiboot/loader/entries/archiso-x86_64-cd.conf > ${work_dir}/efiboot/loader/entries/archiso-x86_64.conf

            cp ${work_dir}/iso/EFI/shellx64_v2.efi ${work_dir}/efiboot/EFI/
            cp ${work_dir}/iso/EFI/shellx64_v1.efi ${work_dir}/efiboot/EFI/

            umount -fl ${work_dir}/efiboot

        fi
        : > ${work_dir}/build.${FUNCNAME}
    fi
}


# Customize installation (root-image)
make_customize_root_image() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        cp -af ${script_path}/root-image ${work_dir}
        ln -sf /usr/share/zoneinfo/UTC ${work_dir}/root-image/etc/localtime
        chmod 750 ${work_dir}/root-image/etc/sudoers.d
        chmod 440 ${work_dir}/root-image/etc/sudoers.d/g_wheel
        mkdir -p ${work_dir}/root-image/etc/pacman.d
        wget -O ${work_dir}/root-image/etc/pacman.d/mirrorlist 'https://www.archlinux.org/mirrorlist/?country=all&protocol=http&use_mirror_status=on'
        sed -i "s/#Server/Server/g" ${work_dir}/root-image/etc/pacman.d/mirrorlist

        # Download opendesktop-fonts
        wget --content-disposition -P ${work_dir}/root-image/arch/pkg 'https://www.archlinux.org/packages/community/any/opendesktop-fonts/download/'

        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r '/usr/bin/locale-gen' \
            run

        #sed -i 's|^root:|root:liLfqaUhrN8Hs|g' ${work_dir}/root-image/etc/shadow
        
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r 'groupadd -r autologin' \
            run

        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r 'useradd -m -g users -G "audio,disk,optical,wheel,network,autologin" antergos' \
            run

        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r 'amixer -c 0 set Master playback 50% unmute' \
            run

        # Configuring pacman
        cp -f ${script_path}/pacman.conf.i686 ${work_dir}/root-image/etc/pacman.conf
        sed -i 's|^#CheckSpace|CheckSpace|g' ${work_dir}/root-image/etc/pacman.conf
        sed -i 's|^#SigLevel = Optional TrustedOnly|SigLevel = Optional|g' ${work_dir}/root-image/etc/pacman.conf
        if [[ ${arch} == 'x86_64' ]];then
            echo '' >> ${work_dir}/root-image/etc/pacman.conf
            echo '[multilib]' >> ${work_dir}/root-image/etc/pacman.conf
            echo 'SigLevel = PackageRequired' >> ${work_dir}/root-image/etc/pacman.conf
            echo 'Include = /etc/pacman.d/mirrorlist' >> ${work_dir}/root-image/etc/pacman.conf
        fi
        



        sed -i 's|^Exec=|Exec=sudo |g' ${work_dir}/root-image/usr/share/applications/pacmanxg.desktop
        sed -i 's|^Exec=|Exec=sudo |g' ${work_dir}/root-image/usr/share/applications/libreoffice-installer.desktop
        sed -i 's|^Exec=|Exec=sudo |g' ${work_dir}/root-image/usr/share/applications/gparted.desktop

        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r 'systemctl -f enable pacman-init.service lightdm.service NetworkManager.service ModemManager.service livecd.service || true' \
            run

        # Fix sudoers
        chown -R root:root ${work_dir}/root-image/etc/
        chmod 660 ${work_dir}/root-image/etc/sudoers

        # Fix QT apps
        echo 'export GTK2_RC_FILES="$HOME/.gtkrc-2.0"' >> ${work_dir}/root-image/etc/bash.bashrc

        # Configure powerpill
        sed -i 's|"ask" : true|"ask" : false|g' ${work_dir}/root-image/etc/powerpill/powerpill.json
        
        # Gsettings changes
        mkdir -p ${work_dir}/root-image/var/run/dbus
        mount -o bind /var/run/dbus ${work_dir}/root-image/var/run/dbus
        cp ${script_path}/set-gsettings ${work_dir}/root-image/usr/bin/
        chmod +x ${work_dir}/root-image/usr/bin/

        # Set gsettings
        mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" \
            -r 'su -c "/usr/bin/set-gsettings" antergos >/dev/null 2>&1' \
            run
            
        rm ${work_dir}/root-image/usr/bin/set-gsettings
        umount -lf ${work_dir}/root-image/var/run/dbus
        
        # Black list floppy
        echo "blacklist floppy" > ${work_dir}/root-image/etc/modprobe.d/nofloppy.conf
        
        # LXDM autologin
        sed -i 's/# autologin=dgod/autologin=antergos/g' ${work_dir}/root-image/etc/lxdm/lxdm.conf


        : > ${work_dir}/build.${FUNCNAME}
    fi
}

# Split out /usr/lib/modules from root-image (makes more "dual-iso" friendly)
make_usr_lib_modules() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        mv ${work_dir}/root-image/usr/lib/modules ${work_dir}/usr-lib-modules
        : > ${work_dir}/build.${FUNCNAME}
    fi
}

# Split out /usr/share from root-image (makes more "dual-iso" friendly)
make_usr_share() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        mv ${work_dir}/root-image/usr/share ${work_dir}/usr-share
        : > ${work_dir}/build.${FUNCNAME}
    fi
}

# Process aitab
make_aitab() {
    if [[ ! -e ${work_dir}/build.${FUNCNAME} ]]; then
        sed "s|%ARCH%|${arch}|g" ${script_path}/aitab > ${work_dir}/iso/${install_dir}/aitab
        : > ${work_dir}/build.${FUNCNAME}
    fi
}

# Build all filesystem images specified in aitab (.fs .fs.sfs .sfs)
make_prepare() {
    cp -a -l -f ${work_dir}/root-image ${work_dir}
    mkarchiso ${verbose} -w "${work_dir}" -D "${install_dir}" pkglist
    mkarchiso ${verbose} -w "${work_dir}" -D "${install_dir}" prepare
    rm -rf ${work_dir}/root-image
    # rm -rf ${work_dir}/${arch}/root-image (if low space, this helps)
}

# Build ISO
make_iso() {
    mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" checksum
    mkarchiso ${verbose} -w "${work_dir}" -C "${pacman_conf}" -D "${install_dir}" -L "${iso_label}" -o "${out_dir}" iso "${iso_name}-${iso_version}-${arch}.iso"
}


purge_single ()
{
    if [[ -d ${work_dir} ]]; then
        find ${work_dir} -mindepth 1 -maxdepth 1 \
            ! -path ${work_dir}/iso -prune \
            | xargs rm -rf
    fi
}


clean_single ()
{
    rm -rf ${work_dir}
    rm -f ${out_dir}/${iso_name}-${iso_version}-*-${arch}.iso
}

make_common_single() {
    make_basefs
    make_packages
    make_setup_mkinitcpio
    make_boot
    make_boot_extra
    make_isolinux
    make_efi
    make_efiboot
    make_aitab
    make_customize_root_image
    make_usr_lib_modules
    make_usr_share
    make_prepare
    make_iso
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

while getopts 'N:V:L:D:w:o:vh' arg; do
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



work_dir=${work_dir}/${arch}

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
