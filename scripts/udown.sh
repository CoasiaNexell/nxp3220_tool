#!/bin/bash

BASEDIR=$(cd "$(dirname "$0")" && pwd)
RESULT=$BASEDIR/../../result
WAITSEC=2

BL1=$RESULT/nxp3220_bl1.bin.raw
BL2=$RESULT/bl2-vtk.bin.raw
SSS=$BASEDIR/../../bl2/bl2-nxp3220/tools/sss.raw
BL32=$RESULT/bl32.bin.raw
UBOOT=$RESULT/u-boot.bin.raw

DOWNLOADER=$BASEDIR/../linux-usbdownloader/linux-usbdownloader

echo "*** USB Download $BL1 ***"
sudo $DOWNLOADER -t nxp3220 -f $BL1  -a 0xFFFF0000 -j 0xFFFF0000
sleep $WAITSEC

echo "*** USB Download $BL2 ***"
sudo $DOWNLOADER -t nxp3220 -f $BL2 -a 0xffff8000 -j 0xffff8000
sleep 8

echo "*** USB Download $SSS ***"
sudo $DOWNLOADER -t nxp3220 -f $SSS -a 0x60000000 -j 0x60000000
sleep $WAITSEC

echo "*** USB Download $BL32 ***"
sudo $DOWNLOADER -t nxp3220 -f $BL32 -a 0x50000000 -j 0x50000000
sleep $WAITSEC

echo "*** USB Download $UBOOT ***"
sudo $DOWNLOADER -t nxp3220 -f $UBOOT -a 0x43c00000 -j 0x43c00000
sleep $WAITSEC

