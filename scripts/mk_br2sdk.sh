#!/bin/bash
# Copyright (c) 2019 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>
#

BASEDIR=`readlink -e -n "$(cd "$(dirname "$0")" && pwd)/../.."`
RESULTDIR="$BASEDIR/result"

BUILDROOT_DIR=$BASEDIR/buildroot
KERNEL_DIR=$BASEDIR/kernel-4.14
BUILDROOT_SDK=nxp3220-arm-gnueabihf_sdk-buildroot # BR2_SDK_PREFIX

SDK_SYSROOT_APPEND_DIR=()
declare -A SDK_SYSROOT_APPEND_TARGET=()

function help() {
	echo  -e "\033[0;33m  \033[0m"
	echo  -e "\033[0;33m Setup SDK: \033[0m"
	echo  -e "\033[0;33m  $> tar zxf $RESULTDIR/${BUILDROOT_SDK}.tar.gz -C <SDK PATH>\033[0m"
	echo  -e "\033[0;33m  $> <SDK PATH>/$BUILDROOT_SDK$BUILDROOT_SDK$BUILDROOT_SDK///relocate-sdk.sh\033[0m"
	echo  -e "\033[0;33m  \033[0m"
	echo  -e "\033[0;33m Setup Environments: \033[0m"
	echo  -e "\033[0;33m  $> source ${BASEDIR}/tools/scripts/env_setup_br2_sdk.sh <SDK PATH>\033[0m"
	echo  -e "\033[0;33m  \033[0m"
}

function usage() {
	echo  -e "\033[0;33m usage:\033[0m"
	echo  -e "\033[0;33m  $> build_br2_sdk.sh [SDK PATH]\033[0m"
	help;
	exit 1;
}

if [ "$#" -ne 0 ]; then
	usage;
fi

if [[ $1 == "-h" ]]; then
	usage;
fi

BUILDROOT_TARGET_PREFIX=arm-linux-gnueabihf
BUILDROOT_SDK_TOP=$BUILDROOT_DIR/output/images

# goto buildroot
cd $BUILDROOT_DIR
[ $? -ne 0 ] && exit 1;

if [[ ! -d $BUILDROOT_DIR/output/target ]]; then
	echo  -e "\033[0;33m Buildroot is not builded !!!$@\033[0m"
	exit 1;
fi

# build sdk
echo  -e "\033[0;33m Build: cd `readlink -e -n $BUILDROOT_DIR`\033[0m"
echo  -e "\033[0;33m Build: make sdk BR2_SDK_PREFIX=$BUILDROOT_SDK\033[0m"
make sdk BR2_SDK_PREFIX=$BUILDROOT_SDK
[ $? -ne 0 ] && exit 1;

# decompress sdk tar file
cd $BUILDROOT_SDK_TOP
echo  -e "\033[0;33m Uncompress: `pwd`\033[0m"
echo  -e "\033[0;33m Uncompress: tar zxf ${BUILDROOT_SDK}.tar.gz\033[0m"
if [ -d ${BUILDROOT_SDK} ]; then
	rm -rf ${BUILDROOT_SDK}
fi
tar zxvf ${BUILDROOT_SDK}.tar.gz >/dev/null 2>&1
[ $? -ne 0 ] && exit 1;

# set PATH
export PATH=$BUILDROOT_SDK_TOP/$BUILDROOT_SDK/bin:$PATH
SDK_SYSROOT=`${BUILDROOT_TARGET_PREFIX}-gcc -print-sysroot`
[ $? -ne 0 ] && exit 1;

# append dirs to SDK
echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
echo -e "\033[0;33m Append dir: $SDK_SYSROOT\033[0m"
for i in "${SDK_SYSROOT_APPEND_DIR[@]}"
do
	echo -e "\tdir  : ${i}"
	mkdir -p ${SDK_SYSROOT}${i}
done

# append files to SDK
echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
echo -e "\033[0;33m Append file: $SDK_SYSROOT\033[0m"
for i in "${!SDK_SYSROOT_APPEND_TARGET[@]}"
do
	if [ ! -f $i ]; then
		echo  -e "\033[0;31m No such file: $i\033[0m"
		continue
	fi

	echo -e "\tfrom : ${i}"
	echo -e "\tto   : ${SDK_SYSROOT_APPEND_TARGET[$i]}"
	cp -a ${i} ${SDK_SYSROOT}${SDK_SYSROOT_APPEND_TARGET[$i]}
done
echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"

# re-compress
echo  -e "\033[0;33m Compress: ${BUILDROOT_SDK} \033[0m"
echo  -e "\033[0;33m Compress: tar czf ${BUILDROOT_SDK}.tar.gz ${BUILDROOT_SDK}\033[0m"
tar czf ${BUILDROOT_SDK}.tar.gz ${BUILDROOT_SDK} >/dev/null 2>&1
rm -rf ${BUILDROOT_SDK}
sync

# copy to result
echo  -e "\033[0;33m Result: $RESULTDIR/${BUILDROOT_SDK}.tar.gz\033[0m"
cp ${BUILDROOT_SDK}.tar.gz $RESULTDIR

help;
