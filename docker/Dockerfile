FROM antergos-base
LABEL maintainer "karasu <karasu@antergos.com>"

ENV PATH='/usr/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl' \
    LANG='en_US.UTF-8' \
    LANGUAGE='en_US:en' \
    LC_TIME='en_US.UTF-8' \
    LC_PAPER='en_US.UTF-8' \
    LC_MEASUREMENT='en_US.UTF-8' \
    TZ='UTC'

# RUN echo "keyserver hkp://pgp.mit.edu:11371" > /etc/pacman.d/gnupg/gpg.conf && pacman-key --refresh-keys

RUN pacman -S --noconfirm archlinux-keyring antergos-keyring && pacman-key --populate archlinux antergos

RUN pacman -Syu --noconfirm --needed && pacman -S --noconfirm --needed archiso git arch-install-scripts dosfstools libisoburn \
 mkinitcpio-nfs-utils make patch squashfs-tools wget gfxboot fribidi iso-hotfix-utility nano transifex-client

RUN git clone https://github.com/Antergos/antergos-iso.git /antergos-iso && \
 cd /antergos-iso && git checkout testing && make install

RUN git clone https://github.com/Antergos/antergos-gfxboot.git /antergos-iso/antergos-gfxboot && \
 cd /antergos-iso/antergos-gfxboot && git checkout colors && make all

# RUN git clone https://github.com/Antergos/iso-hotfix-utility /antergos-iso/iso-hotfix-utility

CMD ["/usr/bin/bash"]
