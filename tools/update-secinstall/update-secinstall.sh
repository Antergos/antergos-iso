#!/bin/bash

DEST_UNPACK='/tmp/update-secinstall'
PKGS_LOCATION='/home/faidoc/Cinnarch/Repos/cinnarch-secinstall2/x86_64'

UNPACK='tar Jxf'

PKG_NAME=''
PKG_URL=''
PKG_VERSION=''
PKG_REMOTE_VERSION=''

rm -rf /var/cache/pacman/pkg/*pkg.tar.xz*
mkdir -p ${DEST_UNPACK}
mkdir -p ${PKGS_LOCATION}/tmp
touch ${PKGS_LOCATION}/tmp/new_packages

pacman -Syy --config pacman.conf.x86_64

for i in `find ${PKGS_LOCATION} -name '*pkg.tar.xz'`;do
	${UNPACK} ${i} -C ${DEST_UNPACK} >/dev/null 2>&1

	PKG_NAME=`cat /tmp/update-secinstall/.PKGINFO | grep pkgname|cut -f2 -d '='`
	PKG_URL=`pacman -Sp ${PKG_NAME}`
	PKG_REMOTE_VERSION=`pacman -Si ${PKG_NAME}|grep Versión|cut -f2 -d ':'`
	PKG_VERSION=`cat /tmp/update-secinstall/.PKGINFO | grep pkgver|cut -f2 -d '='`

	if ! [[ ${PKG_VERSION} = ${PKG_REMOTE_VERSION} ]];then
		rm -rf ${i}
		#wget -P ${PKGS_LOCATION}/tmp ${PKG_URL} 
		pacman --noconfirm -Sw ${PKG_NAME}
		echo ${i} >> ${PKGS_LOCATION}/tmp/new_packages
	fi
	rm -rf ${DEST_UNPACK}/*
done
cp /var/cache/pacman/pkg/*.pkg.tar.xz ${PKGS_LOCATION}
cp /var/cache/pacman/pkg ${PKGS_LOCATION}/tmp
repo-add -f ${PKGS_LOCATION}/cinnarch-secinstall.db.tar.gz ${PKGS_LOCATION}/*.pkg.tar.xz