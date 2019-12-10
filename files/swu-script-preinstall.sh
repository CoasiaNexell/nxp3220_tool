#!/bin/sh
# swupate shell for read enalbe mmc boot partition
# $0 : script name
# $1 : "data" element in sw-descript's scripts

# umount misc to re-partition with parted
umount /misc

# Create /tmp/datadst to remount for filesystem
mkdir -p /tmp/datadst; sync;

# disable ro mode to enable write for mmc boot partition
SYS_MMCBOOT=/sys/block/$1/force_ro
if [[ ! -f $SYS_MMCBOOT ]]; then
	echo "No such device: $SYS_MMCBOOT"
	exit 0;
fi
echo 0 > $SYS_MMCBOOT
