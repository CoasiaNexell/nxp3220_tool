#!/bin/bash

BASEDIR=$(cd "$(dirname "$0")" && pwd)
RESULT=$BASEDIR/../../result
DOWNLOADER=$BASEDIR/../linux-usbdownloader/linux-usbdownloader

nxp3220=(
	"-b $RESULT/nxp3220_bl1.bin.raw  -a 0xFFFF0000 -j 0xFFFF0000"
	"-b $RESULT/bl2-vtk.bin.raw -a 0xFFFF8000 -j 0xFFFF8000"
#	"-b $BASEDIR/../../bl2/bl2-nxp3220/tools/sss.raw -a 0x60000000 -j 0x60000000"
	"-b $RESULT/bl32.bin.raw -a 0x5E000000 -j 0x5E000000"
	"-b $RESULT/u-boot.bin.raw -a 0x43C00000 -j 0x43C00000"
	)

for i in "${nxp3220[@]}"
do
	echo "DOWNLOAD: $i1"
	sudo $DOWNLOADER -t nxp3220 $i
	sleep 2	# wait for next connect
	if [ $? -ne 0 ]; then
		exit 1;
	fi
done
