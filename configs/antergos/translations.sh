#!/bin/bash

shopt -s nullglob

_out_dir="$1"
_work_dir="$2"
        	
        	cd ${_out_dir}/trans
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
        		sleep 1
        	done
        	
shopt -u nullglob

exit 0;
