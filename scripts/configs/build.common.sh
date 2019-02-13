#!/bin/bash

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
LOGO_BMP="$FILES_DIR/logo.bmp"

# BL2 BUILD
BL2_DIR=$BASEDIR/firmwares/bl2-nxp3220
BL2_MAKEOPT="CHIPNAME=${TARGET_BL2_CHIP} BOARD=${TARGET_BL2_BOARD} PMIC=${TARGET_BL2_PMIC}"
BL2_NSIH="$BL2_DIR/reference-nsih/${TARGET_BL2_NSIH}.txt"

BL2_BINGEN="$BINGEN_EXE -n $BL2_NSIH -i $RESULT/bl2-${TARGET_BL2_BOARD}.bin
		-b $BOOT_KEY -u $USER_KEY -k bl2 -l 0xFFFF9000 -s 0xFFFF9000 -t"
BL2_POSTCMD="$BL2_BINGEN; \
		cp $RESULT/bl2-${TARGET_BL2_BOARD}.bin.raw $RESULT/bl2.bin.raw"

# BL32 BUILD
BL32_DIR=$BASEDIR/firmwares/bl32-nxp3220
BL32_NSIH="$BL32_DIR/reference-nsih/nsih_general.txt"

BL32_BINGEN="$BINGEN_EXE -n $BL32_NSIH -i $RESULT/bl32.bin
		-b $BOOT_KEY -u $USER_KEY -k bl32 -l ${TARGET_BL32_LOADADDRESS} -s ${TARGET_BL32_LAUNCHADDRESS} -t"
BL32_BINGEN_ENC="$BINGEN_EXE -n $BL32_NSIH -i $RESULT/bl32.bin.enc
		-b $BOOT_KEY -u $USER_KEY -k bl32 -l ${TARGET_BL32_LOADADDRESS} -s ${TARGET_BL32_LAUNCHADDRESS} -t"

AESCBC_EXE="$BIN_DIR/aescbc_enc"
AESKEY=$(<$FILES_DIR/aeskey.txt)
AESVECTOR=$(<$FILES_DIR/aesvector.txt)

BL32_AESCBC_ENC="$AESCBC_EXE -n $RESULT/bl32.bin -k $AESKEY -v $AESVECTOR -m enc -b 128"
BL32_POSTCMD="$BL32_AESCBC_ENC; $BL32_BINGEN_ENC; $BL32_BINGEN"

# Images BUILD
EXT4FS_EXE="$BASEDIR/tools/bin/make_ext4fs"

MKBOOT_PARAM="$BASEDIR/tools/scripts/mkboot_param.sh"
UBOOT_PARAM="$MKBOOT_PARAM $UBOOT_DIR $LINUX_TOOLCHAIN $RESULT"
UBOOT_BINGEN="$BINGEN_EXE -n $UBOOT_NSIH -i $RESULT/u-boot.bin
		-b $BOOT_KEY -u $USER_KEY -k bl33 -l 0x43C00000 -s 0x43C00000 -t"
UBOOT_POSTCMD="$UBOOT_PARAM; $UBOOT_BINGEN"

KERNEL_POSTCMD="mkdir -p $RESULT/boot; \
		cp -a $RESULT/zImage $RESULT/boot;"
DTB_POSTCMD="mkdir -p $RESULT/boot; \
		cp -a $RESULT/${TARGET_KERNEL_DTB}.dtb $RESULT/boot;"
LOGO_POSTCMD="mkdir -p $RESULT/boot; \
		cp -a $LOGO_BMP $RESULT/boot;"

MAKE_BOOTIMG="$KERNEL_POSTCMD $DTB_POSTCMD $LOGO_POSTCMD
		$EXT4FS_EXE -b 4096 -L boot -l ${BOOT_IMAGE_SIZE} $RESULT/boot.img $RESULT/boot/"
MAKE_ROOTIMG="$EXT4FS_EXE -b 4096 -L rootfs -l ${ROOT_IMAGE_SIZE} $RESULT/rootfs.img $RESULT/rootfs"

# Build Targets
BUILD_IMAGES=(
	"MACHINE= nxp3220",
	"ARCH  	= arm",
	"TOOL	= $LINUX_TOOLCHAIN",
	"RESULT = $RESULT",
	"bl1   	=
		OUTPUT	: $BASEDIR/firmwares/binary/bl1-${TARGET_BL1_NAME}.bin.raw",
	"bl2   	=
		PATH  	: $BL2_DIR,
		TOOL  	: $BL_TOOLCHAIN,
		OPTION	: $BL2_MAKEOPT,
		OUTPUT	: out/bl2-${TARGET_BL2_BOARD}.bin*,
		POSTCMD : $BL2_POSTCMD,
		JOBS  	: 1", # must be 1
	"bl32   	=
		PATH  	: $BL32_DIR,
		TOOL  	: $BL_TOOLCHAIN,
		OUTPUT	: out/bl32.bin*,
		POSTCMD	: $BL32_POSTCMD,
		JOBS  	: 1", # must be 1
	"uboot 	=
		PATH  	: $UBOOT_DIR,
		CONFIG	: ${TARGET_UBOOT_DEFCONFIG},
		OUTPUT	: u-boot.bin,
		POSTCMD	: $UBOOT_POSTCMD"
	"br2   	=
		PATH  	: $BR2_DIR,
		CONFIG	: ${TARGET_BR2_DEFCONFIG},
		OUTPUT	: output/target,
		COPY  	: rootfs",
	"kernel	=
		PATH  	: $KERNEL_DIR,
		CONFIG	: ${TARGET_KERNEL_DEFCONFIG},
		IMAGE 	: zImage,
		OUTPUT	: arch/arm/boot/zImage,
		POSTCMD : $KERNEL_POSTCMD",
	"dtb   	=
		PATH  	: $KERNEL_DIR,
		IMAGE 	: ${TARGET_KERNEL_DTB}.dtb,
		OUTPUT	: arch/arm/boot/dts/${TARGET_KERNEL_DTB}.dtb,
		POSTCMD : $DTB_POSTCMD",
	"bootimg =
		POSTCMD : $MAKE_BOOTIMG",
	"rootimg =
		POSTCMD	: $MAKE_ROOTIMG",
)
