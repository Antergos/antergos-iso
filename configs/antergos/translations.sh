#!/bin/bash

shopt -s nullglob

_out_dir="$1"
_work_dir="$2"
_script_dir="$3"
        	
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
			cd ${_out_dir}/trans/antergos-gfxboot
		  	for f in *.po
		  	do
		  		mv -f ${f} ${_script_dir}/antergos-gfxboot/po
		  	done
		  	cd ${_script_dir}/antergos-gfxboot
		  	make
		  	cp -R isolinux ${_script_dir}

		fi
        	
shopt -u nullglob

exit 0;
