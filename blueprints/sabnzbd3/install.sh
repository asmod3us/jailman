#!/usr/local/bin/bash
# This file contains an example install script to base your own jails on

set -o errexit   # Exit on most errors
set -o errtrace  # Make sure any error trap is inherited
set -o nounset   # Disallow expansion of unset variables
set -o pipefail  # Use last non-zero exit code in a pipeline

trap "ERR during sabnzbd3 install" ERR

initblueprint "$1"

#source_version=3.0.0Beta1
archive=${blueprint_sabnzbd3_source_version}.tar.gz
target=/usr/local/share/sabnzbd3

iocage exec "$1" mkdir -p $target
iocage exec "$1" curl -qsL https://github.com/sabnzbd/sabnzbd/archive/"$archive" | tar -xvzf - --strip-components 1 -C $target
cp "${includes_dir}"/build.sh /mnt/"${global_dataset_iocage}"/jails/"$1"/root/root/
iocage exec "$1" bash /root/build.sh $target

cp "${includes_dir}"/sabnzbd3.rc /usr/local/etc/rc.d/sabnzbd
iocage exec "$1" chmod +x /usr/local/etc/rc.d/sabnzbd

iocage exec "$1" pw user add sabnzbd -c sabnzbd -d /nonexistent -s /usr/bin/nologin
iocage exec "$1" sysrc "sabnzbd_enable=YES"
iocage exec "$1" service sabnzbd start

exitblueprint "$1" "SABnzbd3 is now available at http://${jail_ip}:8080/"
