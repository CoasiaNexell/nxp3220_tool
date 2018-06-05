#!/bin/bash

BASEDIR=$(cd "$(dirname "$0")" && pwd)

RESULT=$BASEDIR/../../result
BINGENDIR=$BASEDIR/../bingen
UBOOTDIR=$BASEDIR/../../u-boot/u-boot-2017.5

NSIHFILE=nsih.txt
BOOTKEY=bootkey
USERKEY=userkey

mkdir -p $RESULT

echo "*** Generate Binary for U-Boot ***"
$BINGENDIR/bingen -n $BINGENDIR/$NSIHFILE -i $UBOOTDIR/u-boot.bin -b $BINGENDIR/$BOOTKEY -u $BINGENDIR/$USERKEY -k bl33 -l 0x43c00000 -s 0x43c00000 -t

cp $UBOOTDIR/u-boot.bin.raw $RESULT
