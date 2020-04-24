#!/bin/bash
export BSP_BASEDIR=$(realpath $(dirname $(realpath ${2}))/../../..)
export BSP_RESULT_TOP=${BSP_BASEDIR}/out
export BSP_RESULT=${BSP_RESULT_TOP}/result

if [[ ! -z $TARGET_RESULT ]]; then
	export BSP_RESULT=${BSP_RESULT_TOP}/${TARGET_RESULT}
fi

if [[ -z $BSP_TOOLCHAIN_BL ]]; then
	export BSP_TOOLCHAIN_BL="${BSP_BASEDIR}/tools/crosstools/gcc-arm-none-eabi-6-2017-q2-update/bin/arm-none-eabi-"
fi

if [[ -z $BSP_TOOLCHAIN_LINUX ]]; then
	export BSP_TOOLCHAIN_LINUX="${BSP_BASEDIR}/tools/crosstools/gcc-linaro-7.2.1-2017.11-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-"
fi

if [[ -z $TARGET_BL1_DIR ]]; then
	export BSP_BL1_DIR=${BSP_BASEDIR}/firmwares/binary
else
	export BSP_BL1_DIR=${TARGET_BL1_DIR}
fi

export BSP_BL2_DIR=${BSP_BASEDIR}/firmwares/bl2-nxp3220
export BSP_BL32_DIR=${BSP_BASEDIR}/firmwares/bl32-nxp3220
export BSP_UBOOT_DIR=${BSP_BASEDIR}/u-boot-2018.5
export BSP_KERNEL_DIR=${BSP_BASEDIR}/kernel-4.14
export BSP_BR2_DIR=${BSP_BASEDIR}/buildroot

export TOOL_BINGEN="${BSP_BASEDIR}/tools/bin/bingen"
export TOOL_BINENC="openssl"
export TOOL_BINECC="${BSP_BASEDIR}/tools/bin/nandbingen"
export TOOL_MKPARAM="${BSP_BASEDIR}/tools/scripts/mk_bootparam.sh"
export TOOL_MKUBIFS="${BSP_BASEDIR}/tools/scripts/mk_ubifs.sh"
export TOOL_MKEXT4="make_ext4fs"

# secure keys
export SECURE_BOOTKEY="${BSP_BASEDIR}/tools/files/secure-bootkey.pem"
export SECURE_USERKEY="${BSP_BASEDIR}/tools/files/secure-userkey.pem"
export SECURE_BL1_ENCKEY="${BSP_BASEDIR}/tools/files/secure-bl1-enckey.txt"
export SECURE_BL32_ENCKEY="${BSP_BASEDIR}/tools/files/secure-bl32-enckey.txt"

# b1 configs
export BL1_BIN="bl1-nxp3220.bin"
export BL1_LOADADDR=0xFFFF0000
export BL1_NSIH="${BSP_BASEDIR}/tools/files/nsih_bl1.txt"

# b2 configs
export BL2_BIN="bl2-${TARGET_BL2_BOARD}.bin"
export BL2_LOADADDR=0xFFFF9000
export BL2_NSIH="${BSP_BL2_DIR}/reference-nsih/$TARGET_BL2_NSIH"
export BL2_CHIP=${TARGET_BL2_CHIP}
export BL2_BOARD=${TARGET_BL2_BOARD}
export BL2_PMIC=${TARGET_BL2_PMIC}

# b32 configs
export BL32_BIN="bl32.bin"
export BL32_LOADADDR=${TARGET_BL32_LOADADDR}
export BL32_NSIH="${BSP_BL32_DIR}/reference-nsih/nsih_general.txt"

# uboot configs
export UBOOT_BIN="u-boot.bin"
export UBOOT_LOADADDR=0x43c00000
export UBOOT_NSIH="${BSP_BASEDIR}/tools/files/nsih_uboot.txt"
export UBOOT_DEFCONFIG=${TARGET_UBOOT_DEFCONFIG}
export UBOOT_LOGO_BMP="${BSP_BASEDIR}/tools/files/logo.bmp"

# kernel configs
export KERNEL_DEFCONFIG=${TARGET_KERNEL_DEFCONFIG}
export KERNEL_BIN=${TARGET_KERNEL_IMAGE}
export DTB_BIN=${TARGET_KERNEL_DTB}.dtb

# buildroot configs
export BR2_DEFCONFIG=${TARGET_BR2_DEFCONFIG}

# images configs
export IMAGE_TYPE=${TARGET_IMAGE_TYPE}
export IMAGE_BOOT_SIZE=${TARGET_BOOT_IMAGE_SIZE}
export IMAGE_ROOT_SIZE=${TARGET_ROOT_IMAGE_SIZE}
export IMAGE_DATA_SIZE=${TARGET_DATA_IMAGE_SIZE}

export BSP_TOOL_FILES=(
	"${BSP_BASEDIR}/tools/scripts/partmap_fastboot.sh"
	"${BSP_BASEDIR}/tools/scripts/partmap_diskimg.sh"
	"${BSP_BASEDIR}/tools/scripts/usb-down.sh"
	"${BSP_BASEDIR}/tools/scripts/configs/udown.bootloader.sh"
	"${BSP_BASEDIR}/tools/scripts/configs/udown.bootloader-secure.sh"
	"${BSP_BASEDIR}/tools/bin/linux-usbdownloader"
	"${BSP_BASEDIR}/tools/bin/simg2dev"
	"${BSP_BASEDIR}/tools/files/partmap_*.txt"
	"${BSP_BASEDIR}/tools/scripts/swu_image.sh"
	"${BSP_BASEDIR}/tools/scripts/swu_hash.py"
	"${BSP_BASEDIR}/tools/files/secure-bootkey.pem"
	"${BSP_BASEDIR}/tools/files/secure-userkey.pem"
	"${BSP_BASEDIR}/tools/files/secure-jtag-hash.txt"
	"${BSP_BASEDIR}/tools/files/efuse_cfg-aes_enb.txt"
	"${BSP_BASEDIR}/tools/files/efuse_cfg-verify_enb-hash0.txt"
	"${BSP_BASEDIR}/tools/files/efuse_cfg-sjtag_enb.txt"
)
