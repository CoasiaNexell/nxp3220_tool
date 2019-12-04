#!/bin/sh
# swupate shell for read enalbe mmc boot partition
# $0 : script name
# $1 : "data" element in sw-descript's scripts

# re-mount misc
if [[ ! -z $1 ]] && [[ -e /dev/$1 ]]; then
	echo "Mount /dev/$1 -> /misc"
	mount -o rw /dev/$1 /misc
fi
