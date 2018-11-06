#!/bin/bash

BASEDIR="$(cd "$(dirname "$0")" && pwd)/../.."
RESULT="$BASEDIR/result"

# Toolchains for Bootloader/Linux
BL_TOOLCHAIN="$BASEDIR/tools/crosstools/gcc-arm-none-eabi-6-2017-q2-update/bin/arm-none-eabi-"
LINUX_TOOLCHAIN="$BASEDIR/tools/crosstools/gcc-linaro-7.2.1-2017.11-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-"

# Build Path
BL2_DIR=$BASEDIR/bootloader/bl2-nxp3220
BL32_DIR=$BASEDIR/bootloader/bl32-nxp3220
BR2_DIR=$BASEDIR/buildroot
UBOOT_DIR=$BASEDIR/u-boot-2018.5
KERNEL_DIR=$BASEDIR/kernel-4.14
BIN_DIR="$BASEDIR/tools/bin"

#Bootloader Make Option
BL2_MAKEOPT="CHIPNAME=sip_s31nx BOARD=vtk PMIC=sm5011"

# BINGEN Input Path
BL2_NSIH="$BL2_DIR/reference-nsih/nsih_vtk_ddr3_800Mhz.txt"
BL32_NSIH="$BL32_DIR/reference-nsih/nsih_general.txt"
UBOOT_NSIH="$BIN_DIR/nsih_uboot.txt"
BOOT_KEY="$BIN_DIR/bootkey"
USER_KEY="$BIN_DIR/userkey"

# BINGEN Command
BINGEN_EXE="$BIN_DIR/bingen"
BL2_BINGEN="$BINGEN_EXE -n $BL2_NSIH -i $RESULT/bl2-vtk.bin
			-b $BOOT_KEY -u $USER_KEY	-k bl2 -l 0xFFFF9000 -s 0xFFFF9000 -t"

BL32_BINGEN="$BINGEN_EXE -n $BL32_NSIH -i $RESULT/bl32.bin
			-b $BOOT_KEY -u $USER_KEY	-k bl32	-l 0x5F000000 -s 0x5F000000 -t"

BL32_BINGEN_ENC="$BINGEN_EXE -n $BL32_NSIH -i $RESULT/bl32.bin.enc
			-b $BOOT_KEY -u $USER_KEY	-k bl32	-l 0x5F000000 -s 0x5F000000 -t"

UBOOT_BINGEN="$BINGEN_EXE -n $UBOOT_NSIH -i $RESULT/u-boot.bin
			-b $BOOT_KEY -u $USER_KEY -k bl33 -l 0x43C00000 -s 0x43C00000 -t"

# Encryption Commands
AESCBC_EXE="$BIN_DIR/aescbc_enc"
AESKEY=$(<$BIN_DIR/aeskey.txt)
AESVECTOR=$(<$BIN_DIR/aesvector.txt)

BL1_AESCBC_ENC="$AESCBC_EXE -n $RESULT/bl1-nxp3220.bin
			-k $AESKEY -v $AESVECTOR -m enc	-b 128"

BL32_AESCBC_ENC="$AESCBC_EXE -n $RESULT/bl32.bin
			-k $AESKEY -v $AESVECTOR -m enc	-b 128"

# Boot Image Build Command
BL1_COMMAND="$BL1_AESCBC_ENC; $BL1_BINGEN_ENC; $BL1_BINGEN"
BL32_COMMAND="$BL32_AESCBC_ENC; $BL32_BINGEN_ENC; $BL32_BINGEN"

BUILD_IMAGES=(
	"MACHINE= nxp3220",
	"ARCH  	= arm",
	"TOOL	= $LINUX_TOOLCHAIN",
	"RESULT = $RESULT",
	"bl1   	=
		OUTPUT	: $BASEDIR/bootloader/binary/bl1-nxp3220.bin.raw",
	"bl2   	=
		PATH  	: $BL2_DIR,
		TOOL  	: $BL_TOOLCHAIN,
		OPTION	: $BL2_MAKEOPT,
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
		CONFIG	: sip_s31nx_vtk_defconfig,
		OUTPUT	: u-boot.bin,
		POSTCMD	: $UBOOT_BINGEN"
	"br2   	=
		PATH  	: $BR2_DIR,
		CONFIG	: nxp3220_sysv_defconfig,
		OUTPUT	: output/target,
		COPY  	: rootfs",
	"kernel	=
		PATH  	: $KERNEL_DIR,
		CONFIG	: sip-s31nx_vtk_defconfig,
		IMAGE 	: zImage,
		OUTPUT	: arch/arm/boot/zImage",
	"dtb   	=
		PATH  	: $KERNEL_DIR,
		IMAGE 	: sip-s31nx-vtk.dtb,
		OUTPUT	: arch/arm/boot/dts/sip-s31nx-vtk.dtb,",
)
