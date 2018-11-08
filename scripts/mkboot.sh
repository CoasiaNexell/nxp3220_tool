#!/bin/bash

BASEDIR="$(cd "$(dirname "$0")" && pwd)/../.."
MAKE_EXT4FS_EXE="$BASEDIR/tools/bin/make_ext4fs"

pushd result

if [ ! -d boot ]; then
	mkdir boot
fi

if [ ! -d boot ]; then
	echo -e "\033[47;31m fail to mkdir: '$boot' ... \033[0m"
	exit 1;
fi

cp -a zImage ./boot
cp -a *.dtb ./boot
$MAKE_EXT4FS_EXE -b 4096 -L boot -l 33554432 boot.img ./boot/

popd
