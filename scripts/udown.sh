#!/bin/bash

BASEDIR=$(cd "$(dirname "$0")" && pwd)
RESULT=$BASEDIR/../../result
DOWNLOADER=$BASEDIR/../linux-usbdownloader/linux-usbdownloader
TARGET=nxp3220

BLIMAGES=(
	"-b $RESULT/bl1-nxp3220.bin.raw  -a 0xFFFF0000 -j 0xFFFF0000"
	"-b $RESULT/bl2-vtk.bin.raw -a 0xFFFF8000 -j 0xFFFF8000"
#	"-b $RESULT/sss.raw -a 0x60000000 -j 0x60000000"
	"-b $RESULT/bl32.bin.raw -a 0x5E000000 -j 0x5E000000"
	"-b $RESULT/u-boot.bin.raw -a 0x43C00000 -j 0x43C00000"
	)

# usb download input file
if [ $# -eq 1 ]; then
	echo "DOWNLOAD: $1"
	if [ ! -f $1 ]; then
		echo "No such file: $1 ... "
		exit 1;
	fi

	sudo $DOWNLOADER -t $TARGET -f $1
	exit $?
fi

# usb download BLIMAGES
for i in "${BLIMAGES[@]}"
do
	echo "DOWNLOAD: $i"
	sudo $DOWNLOADER -t $TARGET $i

	[ $? -ne 0 ] && exit 1;

	sleep 2	# wait for next connect
done
