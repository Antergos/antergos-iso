#!/bin/bash

shopt -s nullglob

_OUT_DIR="$1"
_WORK_DIR="$2"
_SCRIPT_DIR="$3"

for mo_file in ${_OUT_DIR}/trans/cnchi_updater/*.mo
do
	fullname="$(basename ${mo_file})"
	#echo "${fullname}"
	fname="${fullname%.*}"
	#echo "${fname}"
	dest="${_SCRIPT_DIR}/root-image/usr/share/locale/${fname}/LC_MESSAGES"
	echo "${dest}"
	if ! [[ -d "${dest}" ]]; then
		mkdir -p "${dest}";
	fi
	mv "${mo_file}" "${dest}/CNCHI_UPDATER.mo"
done

#for f in ${_OUT_DIR}/trans/antergos-gfxboot/*.po
#do
#	echo "Moving ${f} to ${_script_dir}/antergos-gfxboot/po"
#	mv -f "${f}" "${_script_dir}/antergos-gfxboot/po"
#done

cp -RL "${_SCRIPT_DIR}/antergos-gfxboot" "/usr/share/gfxboot/themes/"
cd /usr/share/gfxboot/themes/antergos-gfxboot
tx pull
make
cp -R /usr/share/gfxboot/themes/antergos-gfxboot/isolinux "${_SCRIPT_DIR}"

shopt -u nullglob

exit 0;
