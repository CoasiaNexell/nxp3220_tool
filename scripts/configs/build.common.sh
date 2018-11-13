#!/bin/bash

BASEDIR="$(cd "$(dirname "$0")" && pwd)/../.."
RESULT="$BASEDIR/result"

# Toolchains for Bootloader and Linux
BL_TOOLCHAIN="$BASEDIR/tools/crosstools/gcc-arm-none-eabi-6-2017-q2-update/bin/arm-none-eabi-"
LINUX_TOOLCHAIN="$BASEDIR/tools/crosstools/gcc-linaro-7.2.1-2017.11-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-"

# Build Path
BR2_DIR=$BASEDIR/buildroot
UBOOT_DIR=$BASEDIR/u-boot-2018.5
KERNEL_DIR=$BASEDIR/kernel-4.14
BIN_DIR="$BASEDIR/tools/bin"
FILES_DIR="$BASEDIR/tools/files"

# FILES
UBOOT_NSIH="$FILES_DIR/nsih_uboot.txt"
BOOT_KEY="$FILES_DIR/bootkey"
USER_KEY="$FILES_DIR/userkey"
BINGEN_EXE="$BIN_DIR/bingen"

# BL2 BUILD
BL2_DIR=$BASEDIR/firmwares/bl2-nxp3220
BL2_MAKEOPT="CHIPNAME=${TARGET_CHIP_ALIAS} BOARD=${TARGET_BOARD} PMIC=nxe1500"
BL2_NSIH="$BL2_DIR/reference-nsih/nsih_${TARGET_BOARD}_ddr3_800Mhz.txt"

BL2_BINGEN="$BINGEN_EXE -n $BL2_NSIH -i $RESULT/bl2-${TARGET_BOARD}.bin
		-b $BOOT_KEY -u $USER_KEY -k bl2 -l 0xFFFF9000 -s 0xFFFF9000 -t"
BL2_COMMAND="$BL2_BINGEN; \
		cp $RESULT/bl2-${TARGET_BOARD}.bin.raw $RESULT/bl2.bin.raw"

# BL32 BUILD
BL32_DIR=$BASEDIR/firmwares/bl32-nxp3220
BL32_NSIH="$BL32_DIR/reference-nsih/nsih_general.txt"
BL32_BINGEN="$BINGEN_EXE -n $BL32_NSIH -i $RESULT/bl32.bin
		-b $BOOT_KEY -u $USER_KEY -k bl32 -l 0x5F000000 -s 0x5F000000 -t"

BL32_BINGEN_ENC="$BINGEN_EXE -n $BL32_NSIH -i $RESULT/bl32.bin.enc
		-b $BOOT_KEY -u $USER_KEY -k bl32 -l 0x5F000000 -s 0x5F000000 -t"

UBOOT_BINGEN="$BINGEN_EXE -n $UBOOT_NSIH -i $RESULT/u-boot.bin
		-b $BOOT_KEY -u $USER_KEY -k bl33 -l 0x43C00000 -s 0x43C00000 -t"

AESCBC_EXE="$BIN_DIR/aescbc_enc"
AESKEY=$(<$FILES_DIR/aeskey.txt)
AESVECTOR=$(<$FILES_DIR/aesvector.txt)

BL32_AESCBC_ENC="$AESCBC_EXE -n $RESULT/bl32.bin -k $AESKEY -v $AESVECTOR -m enc -b 128"

BL32_COMMAND="$BL32_AESCBC_ENC; $BL32_BINGEN_ENC; $BL32_BINGEN"


# Images BUILD
MAKE_EXT4FS_EXE="$BASEDIR/tools/bin/make_ext4fs"
MAKE_BOOTIMG="mkdir -p $RESULT/boot; \
		cp -a $RESULT/zImage $RESULT/boot; \
		cp -a $RESULT/${TARGET_CHIP}-${TARGET_BOARD}.dtb $RESULT/boot; \
		$MAKE_EXT4FS_EXE -b 4096 -L boot -l 33554432 $RESULT/boot.img $RESULT/boot/"

MAKE_ROOTIMG="$MAKE_EXT4FS_EXE -b 4096 -L rootfs -l 1073741824 $RESULT/rootfs.img $RESULT/rootfs"

# Build Targets
BUILD_IMAGES=(
	"MACHINE= ${TARGET_CHIP}",
	"ARCH  	= arm",
	"TOOL	= $LINUX_TOOLCHAIN",
	"RESULT = $RESULT",
	"bl1   	=
		OUTPUT	: $BASEDIR/firmwares/binary/bl1-${TARGET_CHIP}.bin.raw",
	"bl2   	=
		PATH  	: $BL2_DIR,
		TOOL  	: $BL_TOOLCHAIN,
		OPTION	: $BL2_MAKEOPT,
		OUTPUT	: out/bl2-${TARGET_BOARD}.bin*,
		POSTCMD : $BL2_COMMAND,
		JOBS  	: 1", # must be 1
	"bl32   	=
		PATH  	: $BL32_DIR,
		TOOL  	: $BL_TOOLCHAIN,
		OUTPUT	: out/bl32.bin*,
		POSTCMD	: $BL32_COMMAND,
		JOBS  	: 1", # must be 1
	"uboot 	=
		PATH  	: $UBOOT_DIR,
		CONFIG	: ${TARGET_CHIP_ALIAS}_${TARGET_BOARD}_defconfig,
		OUTPUT	: u-boot.bin,
		POSTCMD	: $UBOOT_BINGEN"
	"br2   	=
		PATH  	: $BR2_DIR,
		CONFIG	: ${TARGET_CHIP}_sysv_defconfig,
		OUTPUT	: output/target,
		COPY  	: rootfs",
	"kernel	=
		PATH  	: $KERNEL_DIR,
		CONFIG	: ${TARGET_CHIP_ALIAS}_${TARGET_BOARD}_defconfig,
		IMAGE 	: zImage,
		OUTPUT	: arch/arm/boot/zImage",
	"dtb   	=
		PATH  	: $KERNEL_DIR,
		IMAGE 	: ${TARGET_CHIP}-${TARGET_BOARD}.dtb,
		OUTPUT	: arch/arm/boot/dts/${TARGET_CHIP}-${TARGET_BOARD}.dtb",
	"bootimg =
		POSTCMD : $MAKE_BOOTIMG",
	"rootimg =
		POSTCMD	: $MAKE_ROOTIMG",
)
