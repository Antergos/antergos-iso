#!/bin/sh
#

if [ -d /etc/X11/xinit/xinitrc.d ]; then
    for f in /etc/X11/xinit/xinitrc.d/*; do
        [ -x "$f" ] && . "$f"
    done
    unset f
fi

sudo timedatectl set-ntp true

# Make sure keyring daemon is running
eval $(/usr/bin/gnome-keyring-daemon --start --components=pkcs11,secrets)

exec dbus-launch --exit-with-session openbox-session
