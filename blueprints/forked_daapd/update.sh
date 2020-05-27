#!/usr/local/bin/bash
# This file contains the update script for forked_daapd

iocage exec "$1" service dbus stop
iocage exec "$1" service avahi-daemon stop
iocage exec "$1" service forked-daapd stop

#TODO add update commands here

iocage exec "$1" service dbus restart
iocage exec "$1" service avahi-daemon restart
iocage exec "$1" service forked-daapd restart