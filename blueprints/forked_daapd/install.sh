#!/usr/local/bin/bash
# This script builds and installs the current release of forked_daapd

initblueprint "$1"

createmount "$1" "${itunes_media}" /media/itunes

cp "${SCRIPT_DIR}"/blueprints/forked_daapd/build-ffmpeg.sh /mnt/"${global_dataset_iocage}"/jails/"$1"/root/root/
cp "${SCRIPT_DIR}"/blueprints/forked_daapd/build-daapd.sh /mnt/"${global_dataset_iocage}"/jails/"$1"/root/root/

iocage exec "$1" pkg install -y autoconf automake autotools cmake git glib gmake gperf iconv libtool mercurial mxml nasm opus rsync wget yasm

iocage exec "$1" bash /root/build-ffmpeg.sh
iocage exec "$1" bash /root/build-daapd.sh

# default config: /usr/local/etc/forked-daapd.conf
iocage exec "$1" cp /usr/local/etc/forked-daapd.conf /config/
iocage exec "$1" sed -i '' -e "/directories =/s?=.*?= { \"/media/itunes\" }?" /config/forked-daapd.conf

iocage exec "$1" sysrc "dbus_enable=YES"
iocage exec "$1" sysrc "avahi_daemon_enable=YES"
iocage exec "$1" sysrc "forked_daapd_flags=-c /config/forked-daapd.conf"
iocage exec "$1" sysrc "forked_daapd_enable=YES"

iocage exec "$1" service dbus start
iocage exec "$1" service avahi-daemon start
iocage exec "$1" service forked-daapd start

# remove build depdendencies
iocage exec "$1" pkg delete -y autoconf automake autotools cmake curl git gmake gperf iconv libtool mercurial nasm opus rsync wget yasm
