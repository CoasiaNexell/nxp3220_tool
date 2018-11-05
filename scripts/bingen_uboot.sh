#!/bin/bash

BASEDIR=$(cd "$(dirname "$0")" && pwd)

RESULT=$BASEDIR/../../result
BINGENDIR=$BASEDIR/../bin/
UBOOTBIN=$BASEDIR/../../u-boot-2018.5/u-boot.bin

FILES_DIR=$BASEDIR/../files
NSIHFILE=$FILES_DIR/nsih_uboot.txt
BOOTKEY=$FILES_DIR/bootkey
USERKEY=$FILES_DIR/userkey

mkdir -p $RESULT

if [ ! -f $UBOOTBIN ]; then
	echo "No such file: $UBOOTBIN ... "
	exit 1
fi

echo "*** Generate Binary for U-Boot ***"
$BINGENDIR/bingen -n $NSIHFILE -i $UBOOTBIN -b $BOOTKEY -u $USERKEY -k bl33 -l 0x43c00000 -s 0x43c00000 -t

cp $UBOOTBIN $RESULT
cp $UBOOTBIN.raw $RESULT
