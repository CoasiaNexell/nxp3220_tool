#!/bin/bash

BASEDIR="$(cd "$(dirname "$0")" && pwd)/../.."
RESULT="$BASEDIR/result"
TARGET=artik310s

DN_IMAGES=(
	"TARGET: $TARGET"
	"BOARD : vtk"
	"bl1   : -b $RESULT/bl1-nxp3220.bin.raw"
	"bl2   : -b $RESULT/bl2-vtk.bin.raw"
#	"sss   : -b $RESULT/sss.raw"
	"bl32  : -b $RESULT/bl32.bin.raw"
	"uboot : -b $RESULT/u-boot.bin.raw"
	"kernel: -f $RESULT/zImage"
	"dtb   : -f $RESULT/sip-s31nx-vtk.dtb"
)

DN_ENC_IMAGES=(
	"TARGET: $TARGET"
	"BOARD : vtk"
	"bl1   : -b $RESULT/bl1-nxp3220.bin.enc.raw"
	"bl2   : -b $RESULT/bl2-vtk.bin.raw"
#	"sss   : -b $RESULT/sss.raw"
	"bl32  : -b $RESULT/bl32.bin.enc.raw"
	"uboot : -b $RESULT/u-boot.bin.raw"
	"kernel: -f $RESULT/zImage"
	"dtb   : -f $RESULT/sip-s31nx-vtk.dtb"
)
