#!/bin/bash

IMAGE_PATH=$1
IMAGE_NAME=$2

if [ $# -ne 2 ]; then
	echo "Usage: $0 [SRC initrd dir] [DST uInitrd image]"
	echo ""
	echo " - Pack uInitrd(image formats designed for the U-Boot firmware) with fakeroot"
	exit 1;
fi

IMAGE_UNPACK=initrd.gz

echo "Packing  $IMAGE_PATH -> $IMAGE_UNPACK"

if [ ! -d $IMAGE_PATH ]; then
	echo "No such directory $IMAGE_PATH"
	exit 1;
fi

cd $IMAGE_PATH

# this is pure magic (it allows us to pretend to be root)
# make image with fakeroot to preserve the permission
find . | fakeroot cpio -H newc -o | gzip -c > ../$IMAGE_UNPACK

# make uinitrd image
cd ..
echo "Convert $IMAGE_UNPACK -> $IMAGE_NAME"

# mkimage options
UBOOT_MKIMAGE=mkimage
ARCH=arm
IMAGE_TYPE=ramdisk
SYSTEM=linux
COMPRESS=none #gzip
IMAGE_TYPE=ramdisk

$UBOOT_MKIMAGE -A $ARCH -O $SYSTEM -T $IMAGE_TYPE -C $COMPRESS -a 0 -e 0 -n $IMAGE_TYPE -d $IMAGE_UNPACK $IMAGE_NAME
