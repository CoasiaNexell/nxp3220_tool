#!/bin/bash

BASEDIR="$(cd "$(dirname "$0")" && pwd)/../.."
MAKE_EXT4FS_EXE="$BASEDIR/tools/bin/make_ext4fs"

pushd result

if [ ! -d rootfs ]; then
	echo -e "\033[47;31m make rootfs first ... \033[0m"
	exit 1;
fi

$MAKE_EXT4FS_EXE -b 4096 -L rootfs -l 1073741824 rootfs.img ./rootfs/

popd
