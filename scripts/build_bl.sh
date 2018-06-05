#!/bin/bash

BASEDIR=$(cd "$(dirname "$0")" && pwd)
RESULT=$BASEDIR/../../result
BL_TOOLCHAIN=$BASEDIR/../crosstools/gcc-arm-none-eabi-6-2017-q2-update/bin/
LINUX_TOOLCHAIN=$BASEDIR/../crosstools/gcc-linaro-7.2.1-2017.11-x86_64_arm-linux-gnueabihf/bin

export PATH=$PATH:$BL_TOOLCHAIN:$LINUX_TOOLCHAIN

mkdir -p $RESULT

echo "*** Build BL1 ***"
make clean -C bl1/bl1-nxp3220
make -C bl1/bl1-nxp3220
cp bl1/bl1-nxp3220/out/nxp3220_bl1.bin.raw $RESULT

echo "*** Build BL2 ***"
make clean -C bl2/bl2-nxp3220
make -C bl2/bl2-nxp3220
cp bl2/bl2-nxp3220/out/bl2-vtk.bin.raw $RESULT

echo "*** Build BL32 ***"
make clean -C bl32/bl32-nxp3220
make -C bl32/bl32-nxp3220
cp bl32/bl32-nxp3220/out/bl32.bin.raw $RESULT