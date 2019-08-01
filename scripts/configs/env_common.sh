#!/bin/bash
export BASEDIR=`readlink -e -n "$(cd "$(dirname "$0")" && pwd)/../.."`
export RESULT="${BASEDIR}/out/result"

if [[ ! -z $TARGET_RESULT ]]; then
	export RESULT="${BASEDIR}/out/${TARGET_RESULT}"
fi

export BL_TOOLCHAIN="${BASEDIR}/tools/crosstools/gcc-arm-none-eabi-6-2017-q2-update/bin/arm-none-eabi-"
export LINUX_TOOLCHAIN="${BASEDIR}/tools/crosstools/gcc-linaro-7.2.1-2017.11-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-"

if [[ -z $TARGET_BL1_DIR ]]; then
	export BL1_DIR=${BASEDIR}/firmwares/binary
else
	export BL1_DIR=${TARGET_BL1_DIR}
fi

export BL2_DIR=${BASEDIR}/firmwares/bl2-nxp3220
export BL32_DIR=${BASEDIR}/firmwares/bl32-nxp3220
export UBOOT_DIR=${BASEDIR}/u-boot-2018.5
export KERNEL_DIR=${BASEDIR}/kernel-4.14
export BR2_DIR=${BASEDIR}/buildroot

export TOOL_BINGEN="${BASEDIR}/tools/bin/bingen"
export TOOL_BINENC="${BASEDIR}/tools/bin/aescbc_enc"
export TOOL_BINECC="${BASEDIR}/tools/bin/nandbingen"
export TOOL_MKPARAM="${BASEDIR}/tools/scripts/mk_bootparam.sh"
export TOOL_MKUBIFS="${BASEDIR}/tools/scripts/mk_ubifs.sh"
export TOOL_MKEXT4="make_ext4fs"

export BL1_BIN="bl1-nxp3220.bin"
export BL1_LOADADDR=0xFFFF0000
export BL1_NSIH="${BASEDIR}/tools/files/nsih_bl1.txt"
export BL1_BOOTKEY="${BASEDIR}/tools/files/bootkey"
export BL1_USERKEY="${BASEDIR}/tools/files/userkey"
export BL1_AESKEY="${BASEDIR}/tools/files/aeskey.txt"
export BL1_VECTOR="${BASEDIR}/tools/files/aesvector.txt"

export BL2_BIN="bl2-${TARGET_BL2_BOARD}.bin"
export BL2_LOADADDR=0xFFFF9000
export BL2_NSIH="${BL2_DIR}/reference-nsih/$TARGET_BL2_NSIH"
export BL2_BOOTKEY="${BASEDIR}/tools/files/bootkey"
export BL2_USERKEY="${BASEDIR}/tools/files/userkey"
export BL2_CHIP=${TARGET_BL2_CHIP}
export BL2_BOARD=${TARGET_BL2_BOARD}
export BL2_PMIC=${TARGET_BL2_PMIC}

export BL32_BIN="bl32.bin"
export BL32_LOADADDR=${TARGET_BL32_LOADADDR}
export BL32_NSIH="${BL32_DIR}/reference-nsih/nsih_general.txt"
export BL32_BOOTKEY="${BASEDIR}/tools/files/bootkey"
export BL32_USERKEY="${BASEDIR}/tools/files/userkey"
export BL32_AESKEY="${BASEDIR}/tools/files/aeskey.txt"
export BL32_VECTOR="${BASEDIR}/tools/files/aesvector.txt"

export UBOOT_BIN="u-boot.bin"
export UBOOT_LOADADDR=0x43c00000
export UBOOT_NSIH="${BASEDIR}/tools/files/nsih_uboot.txt"
export UBOOT_DEFCONFIG=${TARGET_UBOOT_DEFCONFIG}
export UBOOT_BOOTKEY="${BASEDIR}/tools/files/bootkey"
export UBOOT_USERKEY="${BASEDIR}/tools/files/userkey"
export UBOOT_LOGO_BMP="${BASEDIR}/tools/files/logo.bmp"

export KERNEL_DEFCONFIG=${TARGET_KERNEL_DEFCONFIG}
export KERNEL_BIN=${TARGET_KERNEL_IMAGE}
export DTB_BIN=${TARGET_KERNEL_DTB}.dtb

export BR2_DEFCONFIG=${TARGET_BR2_DEFCONFIG}

export IMAGE_TYPE=${TARGET_IMAGE_TYPE}
export IMAGE_BOOT_SIZE=${TARGET_BOOT_IMAGE_SIZE}
export IMAGE_ROOT_SIZE=${TARGET_ROOT_IMAGE_SIZE}

export TOOL_FILES=(
	"${BASEDIR}/tools/scripts/partmap_fastboot.sh"
	"${BASEDIR}/tools/scripts/partmap_diskimg.sh"
	"${BASEDIR}/tools/scripts/usb-down.sh"
	"${BASEDIR}/tools/scripts/configs/udown.bootloader.sh"
	"${BASEDIR}/tools/bin/linux-usbdownloader"
	"${BASEDIR}/tools/files/partmap_*.txt"
)

