#!/bin/bash

BASEDIR=$(cd "$(dirname "$0")" && pwd)

RESULT=$BASEDIR/../../result
BINGENDIR=$BASEDIR/../bingen
UBOOTBIN=$BASEDIR/../../u-boot/u-boot-2017.5/u-boot.bin

NSIHFILE=nsih.txt
BOOTKEY=bootkey
USERKEY=userkey

mkdir -p $RESULT

if [ ! -f $UBOOTBIN ]; then
	echo "No such file: $UBOOTBIN ... "
	exit 1
fi

echo "*** Generate Binary for U-Boot ***"
$BINGENDIR/bingen -n $BINGENDIR/$NSIHFILE -i $UBOOTBIN -b $BINGENDIR/$BOOTKEY -u $BINGENDIR/$USERKEY -k bl33 -l 0x43c00000 -s 0x43c00000 -t

cp $UBOOTBIN $RESULT
cp $UBOOTBIN.raw $RESULT
