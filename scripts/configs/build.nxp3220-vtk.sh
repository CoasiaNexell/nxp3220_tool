#!/bin/bash

BASEDIR="$(cd "$(dirname "$0")" && pwd)/../.."
RESULT="$BASEDIR/result"

# DIR
BL1_DIR=$BASEDIR/bootloader/bl1-nxp3220
BL2_DIR=$BASEDIR/bootloader/bl2-nxp3220
BL32_DIR=$BASEDIR/bootloader/bl32-nxp3220
BR2_DIR=$BASEDIR/rootfs/buildroot

UBOOT_DIR=$BASEDIR/u-boot/u-boot-2018.5
KERNEL_DIR=$BASEDIR/kernel/kernel-4.14

# for bootloader (bl1/2/32)
BL_TOOLCHAIN_PATH="$BASEDIR/tools/crosstools/gcc-arm-none-eabi-6-2017-q2-update/bin"
BL_TOOLCHAIN="$BL_TOOLCHAIN_PATH/arm-none-eabi-"
LINUX_TOOLCHAIN="$BASEDIR/tools/crosstools/gcc-linaro-7.2.1-2017.11-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-"

BINGEN_DIR="$BASEDIR/tools/bin"
BL1_NSIHFILE="$BL1_DIR/reference-nsih/nsih_general.txt"
BL2_NSIHFILE="$BL2_DIR/reference-nsih/nsih_vtk_ddr3_800Mhz.txt"
BL32_NSIHFILE="$BL32_DIR/reference-nsih/nsih_general.txt"
UBOOT_NSIHFILE="$BINGEN_DIR/nsih_uboot.txt"
BOOTKEY="$BINGEN_DIR/bootkey"
USERKEY="$BINGEN_DIR/userkey"

BINGEN_EXE="$BASEDIR/tools/bin/bingen"
BL1_BINGEN="$BINGEN_EXE -n $BL1_NSIHFILE -i $RESULT/bl1-nxp3220.bin
			-b $BOOTKEY -u $USERKEY	-k bl1 l 0xFFFF0000 -s 0xFFFF0000 -t"
BL1_BINGEN_ENC="$BINGEN_EXE -n $BL1_NSIHFILE -i $RESULT/bl1-nxp3220.bin.enc
			-b $BOOTKEY -u $USERKEY	-k bl1 -l 0xFFFF0000 -s 0xFFFF0000 -t"

BL2_BINGEN="$BINGEN_EXE -n $BL2_NSIHFILE -i $RESULT/bl2-vtk.bin
			-b $BOOTKEY -u $USERKEY	-k bl2 -l 0xFFFF9000 -s 0xFFFF9000 -t"

BL32_BINGEN="$BINGEN_EXE -n $BL32_NSIHFILE -i $RESULT/bl32.bin
			-b $BOOTKEY -u $USERKEY	-k bl32	-l 0x5F000000 -s 0x5F000000 -t"

BL32_BINGEN_ENC="$BINGEN_EXE -n $BL32_NSIHFILE -i $RESULT/bl32.bin.enc
			-b $BOOTKEY -u $USERKEY	-k bl32	-l 0x5F000000 -s 0x5F000000 -t"

UBOOT_BINGEN="$BINGEN_EXE -n $UBOOT_NSIHFILE -i $RESULT/u-boot.bin
			-b $BOOTKEY -u $USERKEY -k bl33 -l 0x43C00000 -s 0x43C00000 -t"

AESCBC_EXE="$BASEDIR/tools/bin/aescbc_enc"
AESKEY=$(<$BASEDIR/tools/bin/aeskey.txt)
AESVECTOR=$(<$BASEDIR/tools/bin/aesvector.txt)
BL1_AESCBC_ENC="$AESCBC_EXE -n $RESULT/bl1-nxp3220.bin
			-k $AESKEY -v $AESVECTOR -m enc	-b 128"

BL32_AESCBC_ENC="$AESCBC_EXE -n $RESULT/bl32.bin
			-k $AESKEY -v $AESVECTOR -m enc	-b 128"

BL1_COMMAND="$BL1_AESCBC_ENC; $BL1_BINGEN_ENC; $BL1_BINGEN"
BL32_COMMAND="$BL32_AESCBC_ENC; $BL32_BINGEN_ENC; $BL32_BINGEN"

BUILD_IMAGES=(
	"MACHINE= nxp3220",
	"ARCH  	= arm",
	"TOOL	= $LINUX_TOOLCHAIN",
	"RESULT = $RESULT",
	"bl1   	=
		PATH  	: $BL1_DIR,
		TOOL  	: $BL_TOOLCHAIN,
		OUTPUT	: out/bl1-nxp3220.bin*,
		POSTCMD : $BL1_COMMAND,
		JOBS  	: 1", # must be 1
	"bl2   	=
		PATH  	: $BL2_DIR,
		TOOL  	: $BL_TOOLCHAIN,
		OPTION	: BOARD=vtk,
		OUTPUT	: out/bl2-vtk.bin*,
		POSTCMD : $BL2_BINGEN,
		JOBS  	: 1", # must be 1
	"bl32   	=
		PATH  	: $BL32_DIR,
		TOOL  	: $BL_TOOLCHAIN,
		OUTPUT	: out/bl32.bin*,
		POSTCMD	: $BL32_COMMAND,
		JOBS  	: 1", # must be 1
	"uboot 	=
		PATH  	: $UBOOT_DIR,
		CONFIG	: nxp3220_vtk_defconfig,
		OUTPUT	: u-boot.bin,
		POSTCMD	: $UBOOT_BINGEN"
	"kernel	=
		PATH  	: $KERNEL_DIR,
		CONFIG	: nxp3220_vtk_defconfig,
		IMAGE 	: zImage,
		OUTPUT	: arch/arm/boot/zImage",
	"dtb   	=
		PATH  	: $KERNEL_DIR,
		IMAGE 	: nxp3220-vtk.dtb,
		OUTPUT	: arch/arm/boot/dts/nxp3220-vtk.dtb",
	"br2   	=
		PATH  	: $BR2_DIR,
		CONFIG	: nxp3220_vtk_sysv_defconfig,
		OUTPUT	: output/target,
		COPY  	: rootfs",
)
