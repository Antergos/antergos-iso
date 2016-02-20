#!/bin/bash

shopt -s nullglob

_out_dir="$1"
_work_dir="$2"
_script_dir="$3"



for f in ${_out_dir}/trans/cnchi_updater/*.mo
do
	fullname="$(basename ${f})"
	echo "${fullname}"
	fname="${fullname%.*}"
	echo "${fname}"
	dest="${_script_dir}/root-image/usr/share/locale/${fname}/LC_MESSAGES"
	echo "${dest}"
	if ! [[ -d "${dest}" ]]; then
		mkdir -p "${dest}";
	fi
	mv "${f}" "${dest}/CNCHI_UPDATER.mo"
done

 

#for f in ${_out_dir}/trans/antergos-gfxboot/*.po
#do
#	echo "Moving ${f} to ${_script_dir}/antergos-gfxboot/po"
#	mv -f "${f}" "${_script_dir}/antergos-gfxboot/po"
#done

cp -RL "${_script_dir}/antergos-gfxboot" "/usr/share/gfxboot/themes/"
cd /usr/share/gfxboot/themes/antergos-gfxboot

tx pull

make

cp -R isolinux "${_script_dir}"


shopt -u nullglob

exit 0;
