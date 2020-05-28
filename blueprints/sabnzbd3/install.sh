#!/usr/local/bin/bash
# This file contains an example install script to base your own jails on

initblueprint "$1"

# Initialise defaults
# You can add default values for the variables already loaded here.

if [ "${reinstall}" = "true" ]; then
	echo "Reinstall detected..."
else
	echo "no reinstall detected, normal install proceeding..."
fi

iocage exec "$1" curl -LO https://github.com/sabnzbd/sabnzbd/archive/3.0.0Beta1.tar.gz

exitblueprint "$1" "SABnzbd3 is now available at http://:8080/"
