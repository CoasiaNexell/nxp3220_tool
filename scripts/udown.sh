#!/bin/bash

BASEDIR=$(cd "$(dirname "$0")" && pwd)
RESULT=$BASEDIR/../../result
DOWNLOADER=$BASEDIR/../linux-usbdownloader/linux-usbdownloader

nxp3220=(
	"-f $RESULT/nxp3220_bl1.bin.raw  -a 0xFFFF0000 -j 0xFFFF0000"
	"-f $RESULT/bl2-vtk.bin.raw -a 0xffff8000 -j 0xffff8000"
	"-f $BASEDIR/../../bl2/bl2-nxp3220/tools/sss.raw -a 0x60000000 -j 0x60000000"
	"-f $RESULT/bl32.bin.raw -a 0x50000000 -j 0x50000000"
	"-f $RESULT/u-boot.bin.raw -a 0x43c00000 -j 0x43c00000"
	)

for i in "${nxp3220[@]}"
do
	echo "DOWNLOAD: $i1"
	sudo $DOWNLOADER -t nxp3220 $i
	sleep 1	# wait for next connect
	if [ $? -ne 0 ]; then
		exit 1;
	fi
done
