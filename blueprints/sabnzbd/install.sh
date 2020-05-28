#!/usr/local/bin/bash

initblueprint "$1"

# Check if dataset Downloads dataset exist, create if they do not.
createmount "$1" "${global_dataset_downloads}" /mnt/downloads

# Check if dataset Complete Downloads dataset exist, create if they do not.
createmount "$1" "${global_dataset_downloads}"/complete /mnt/downloads/complete

# Check if dataset InComplete Downloads dataset exist, create if they do not.
createmount "$1" "${global_dataset_downloads}"/incomplete /mnt/downloads/incomplete

iocage exec "$1" chown -R _sabnzbd:_sabnzbd /config
iocage exec "$1" sysrc "sabnzbd_enable=YES"
iocage exec "$1" sysrc "sabnzbd_conf_dir=/config"
iocage exec "$1" sysrc "sabnzbd_user=_sabnzbd"
iocage exec "$1" sysrc "sabnzbd_group=_sabnzbd"
# start once to let service write default config
iocage exec "$1" service sabnzbd start
iocage exec "$1" service sabnzbd stop
# put our config in place
iocage exec "$1" sed -i '' -e 's?host = 127.0.0.1?host = 0.0.0.0?g' /config/sabnzbd.ini
iocage exec "$1" sed -i '' -e 's?download_dir = Downloads/incomplete?download_dir = /mnt/downloads/incomplete?g' /config/sabnzbd.ini
iocage exec "$1" sed -i '' -e 's?complete_dir = Downloads/complete?complete_dir = /mnt/downloads/complete?g' /config/sabnzbd.ini

iocage exec "$1" service sabnzbd start

JAIL_IP=${ip4_addr:-}
if [ -z "${JAIL_IP}" ]; then
	DEFAULT_IF=$(iocage exec "$1" route get default | awk '/interface/ {print $2}')
	JAIL_IP=$(iocage exec "$1" ifconfig "$DEFAULT_IF" | awk '/inet/ { print $2 }')
else
	JAIL_IP=${ip4_addr%/*}
fi
exitblueprint "$1" "sabnzbd is now accessible at http://${JAIL_IP}:8080/"
