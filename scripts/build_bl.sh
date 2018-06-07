#!/bin/bash

BASEDIR=$(cd "$(dirname "$0")" && pwd)
RESULT="$BASEDIR/../../result"	# must be set with Relative path for not exist dir

BL_DIR=`readlink -e -n "$BASEDIR/../.."`
BL_TOOLCHAIN=`readlink -e -n "$BASEDIR/../crosstools/gcc-arm-none-eabi-6-2017-q2-update/bin/"`
LINUX_TOOLCHAIN=`readlink -e -n "$BASEDIR/../crosstools/gcc-linaro-7.2.1-2017.11-x86_64_arm-linux-gnueabihf/bin"`

BL1_DIR=$BL_DIR/bl1/bl1-nxp3220
BL1_BIN=$BL_DIR/bl1/bl1-nxp3220/out/nxp3220_bl1.bin.raw

BL2_DIR=$BL_DIR/bl2/bl2-nxp3220
BL2_BIN=$BL_DIR/bl2/bl2-nxp3220/out/bl2-vtk.bin.raw

BL32_DIR=$BL_DIR/bl32/bl32-nxp3220
BL32_BIN=$BL_DIR/bl32/bl32-nxp3220/out/bl32.bin.raw

export PATH=$PATH:$BL_TOOLCHAIN:$LINUX_TOOLCHAIN

mkdir -p $RESULT

RESULT=`readlink -e -n "$BASEDIR/../../result"`

build_bl() {
	dir=$1;	bin=$2; ret=$3; msg=$4

	echo "*** BUILD: $msg ***"

	make clean -C $dir
	[ $? -ne 0 ] && exit 1;

	make -C $dir
	[ $? -ne 0 ] && exit 1;

	echo "*** COPY : $bin ***"
	echo "*** TO   : $ret/ ***"

	cp $bin $ret/
}

case "$1" in
	bl1)
	       	build_bl $BL1_DIR $BL1_BIN $RESULT "BL1"
		;;
	bl2)
	       	build_bl $BL2_DIR $BL2_BIN $RESULT "BL2"
		;;
	bl32)
	       	build_bl $BL32_DIR $BL32_BIN $RESULT "BL32"
		;;

	help|h|-h|-help)
		echo "Usage : $0 {*|bl1|bl2|bl32}"
		exit 1
		;;
	*)
		build_bl $BL1_DIR $BL1_BIN $RESULT "BL1"
		build_bl $BL2_DIR $BL2_BIN $RESULT "BL2"
		build_bl $BL32_DIR $BL32_BIN $RESULT "BL32"
		;;
esac

exit $?
