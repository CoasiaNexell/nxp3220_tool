#!/bin/bash

IMAGE_UNPACK=initrd.gz
IMAGE_PATH=initrd

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
	echo "Usage: $0 [SRC uInitrd image] [DST initrd dir]"
	echo ""
	echo " - Unpack uInitrd(image formats designed for the U-Boot firmware) with fakeroot"
	exit 1;
fi

IMAGE_NAME=$1
[ $# -eq 2 ] && IMAGE_PATH=$2;

echo "Unpacking  $IMAGE_NAME -> $IMAGE_UNPACK"

if [ -e $IMAGE_UNPACK ]; then
	rm $IMAGE_UNPACK
fi

dd if=$IMAGE_NAME of=$IMAGE_UNPACK skip=64 bs=1

if [ -d $IMAGE_PATH ]; then
	echo "Remove     $IMAGE_PATH ..."
	rm -rf $IMAGE_PATH
fi

echo "Uncompress $IMAGE_UNPACK -> $IMAGE_PATH"

mkdir -p $IMAGE_PATH
cd $IMAGE_PATH
zcat ../$IMAGE_UNPACK | cpio -id
