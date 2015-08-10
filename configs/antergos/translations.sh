#!/bin/bash

shopt -s nullglob

_out_dir="$1"
_work_dir="$2"
_trans_for="$3"
        	
        	if [[ ${_trans_for} = "cnchi_updater" ]]; then
		  	cd ${_out_dir}/trans/cnchi_updater
		  	for f in *.mo
		  	do
		  		fullname="$(basename ${f})"
		  		echo ${fullname}
		  		fname="${fullname%.*}"
		  		echo ${fname}
		  		dest="${_work_dir}/root-image/usr/share/locale/${fname}/LC_MESSAGES"
		  		if ! [[ -d "${dest}" ]]; then
		  			mkdir -p "${dest}";
		  		fi
		  		mv ${f} ${dest}/CNCHI_UPDATER.mo
		  	done
		else
			cd ${_out_dir}/trans/gfxboot
		  	for f in *.tr
		  	do
		  		fullname="$(basename ${f})"
		  		echo ${fullname}
		  		fname="${fullname%.*}"
		  		echo ${fname}
		  		mv -f ${f} ${_work_dir}/isolinux
		  	done
		  	cd ${_work_dir}/isolinux
		  	rm -f bootlogo
		  	find . | cpio -o > ../bootlogo
		  	mv ../bootlogo .

		fi
        	
shopt -u nullglob

exit 0;
