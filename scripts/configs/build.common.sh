#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>
#

BASE_DIR=$(realpath $(dirname $(realpath "$BASH_SOURCE"))/../../..)
RESULT_DIR=${BASE_DIR}/out/result
[[ ! -z $TARGET_RESULT ]] && RESULT_DIR=${BASE_DIR}/out/${TARGET_RESULT};

TOOL_BINGEN="${BASE_DIR}/tools/bin/bingen"
TOOL_BINECC="${BASE_DIR}/tools/bin/nandbingen"
TOOL_BOOTPARAM="${BASE_DIR}/tools/scripts/mk_bootparam.sh"
TOOL_MKUBIFS="${BASE_DIR}/tools/scripts/mk_ubifs.sh"
TOOLCHAIN_BOOTLOADER="${BASE_DIR}/tools/crosstools/gcc-arm-none-eabi-6-2017-q2-update/bin/arm-none-eabi-"
TOOLCHAIN_LINUX="${BASE_DIR}/tools/crosstools/gcc-linaro-7.2.1-2017.11-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-"

# secure keys
SECURE_BOOTKEY="${BASE_DIR}/tools/files/secure-bootkey.pem"
SECURE_USERKEY="${BASE_DIR}/tools/files/secure-userkey.pem"
SECURE_BL1_ENCKEY="${BASE_DIR}/tools/files/secure-bl1-enckey.txt"
SECURE_BL32_ENCKEY="${BASE_DIR}/tools/files/secure-bl32-enckey.txt"
SECURE_BL1_IVECTOR=73FC7B44B996F9990261A01C9CB93C8F
SECURE_BL32_IVECTOR=73FC7B44B996F9990261A01C9CB93C8F

# b1 configs
# Add to build source at target script:
# TARGET_BL1_DIR=$(realpath $(dirname $(realpath "$BASH_SOURCE"))/../../..)/firmwares/bl1-nxp3220
BL1_DIR=${TARGET_BL1_DIR}
[[ -z $TARGET_BL1_DIR ]] && BL1_DIR=${BASE_DIR}/firmwares/binary;
BL1_BIN="bl1-nxp3220.bin"
BL1_LOADADDR=0xFFFF0000
BL1_NSIH="${BASE_DIR}/tools/files/nsih_bl1.txt"

# b2 configs
BL2_DIR=${BASE_DIR}/firmwares/bl2-nxp3220
BL2_BIN="bl2-${TARGET_BL2_BOARD}.bin"
BL2_LOADADDR=0xFFFF9000
BL2_NSIH="${BL2_DIR}/reference-nsih/$TARGET_BL2_NSIH"
BL2_CHIP=${TARGET_BL2_CHIP}
BL2_BOARD=${TARGET_BL2_BOARD}
BL2_PMIC=${TARGET_BL2_PMIC}

# b32 configs
BL32_DIR=${BASE_DIR}/firmwares/bl32-nxp3220
BL32_BIN="bl32.bin"
BL32_LOADADDR=${TARGET_BL32_LOADADDR}
BL32_NSIH="${BL32_DIR}/reference-nsih/nsih_general.txt"

# uboot configs
UBOOT_DIR=${BASE_DIR}/u-boot-2018.5
UBOOT_BIN="u-boot.bin"
UBOOT_LOADADDR=0x43c00000
UBOOT_NSIH="${BASE_DIR}/tools/files/nsih_uboot.txt"
UBOOT_DEFCONFIG=${TARGET_UBOOT_DEFCONFIG}
UBOOT_LOGO_BMP="${BASE_DIR}/tools/files/logo.bmp"

# kernel configs
KERNEL_DIR=${BASE_DIR}/kernel-4.14
KERNEL_DEFCONFIG=${TARGET_KERNEL_DEFCONFIG}
KERNEL_BIN=${TARGET_KERNEL_IMAGE}
DTB_BIN=${TARGET_KERNEL_DTB}.dtb

# buildroot configs
BR2_DIR=${BASE_DIR}/buildroot
BR2_DEFCONFIG=${TARGET_BR2_DEFCONFIG}

# images configs
IMAGE_TYPE=${TARGET_IMAGE_TYPE}
IMAGE_BOOT_SIZE=${TARGET_BOOT_IMAGE_SIZE}
IMAGE_ROOT_SIZE=${TARGET_ROOT_IMAGE_SIZE}
IMAGE_DATA_SIZE=${TARGET_DATA_IMAGE_SIZE}
IMAGE_MISC_SIZE=${TARGET_MISC_IMAGE_SIZE}

if [[ ${IMAGE_TYPE} == "ext4" ]]; then
MAKE_BOOT_IMAGE="make_ext4fs -L boot -s -b 4k -l ${IMAGE_BOOT_SIZE} $RESULT_DIR/boot.img $RESULT_DIR/boot";
MAKE_ROOT_IMAGE="make_ext4fs -L rootfs -s -b 4k -l ${IMAGE_ROOT_SIZE} $RESULT_DIR/rootfs.img $RESULT_DIR/rootfs";
MAKE_DATA_IMAGE="make_ext4fs -L userdata -s -b 4k -l ${IMAGE_DATA_SIZE} $RESULT_DIR/userdata.img $RESULT_DIR/userdata";
MAKE_MISC_IMAGE="make_ext4fs -L misc -s -b 4k -l ${IMAGE_MISC_SIZE} $RESULT_DIR/misc.img $RESULT_DIR/misc";
elif [[ ${IMAGE_TYPE} == "ubi" ]]; then
MAKE_BOOT_IMAGE="${TOOL_MKUBIFS} -r ${RESULT_DIR}/boot -v boot -i 0 -l ${IMAGE_BOOT_SIZE} \
		-p ${FLASH_PAGE_SIZE} -b ${FLASH_BLOCK_SIZE} -c ${FLASH_DEVICE_SIZE}";
MAKE_ROOT_IMAGE="${TOOL_MKUBIFS} -r ${RESULT_DIR}/rootfs -v rootfs -i 1 -l ${IMAGE_ROOT_SIZE} \
		-p ${FLASH_PAGE_SIZE} -b ${FLASH_BLOCK_SIZE} -c ${FLASH_DEVICE_SIZE}";
MAKE_DATA_IMAGE="${TOOL_MKUBIFS} -r ${RESULT_DIR}/userdata -v userdata -i 1 -l ${IMAGE_DATA_SIZE} \
		-p ${FLASH_PAGE_SIZE} -b ${FLASH_BLOCK_SIZE} -c ${FLASH_DEVICE_SIZE}";
MAKE_MISC_IMAGE="${TOOL_MKUBIFS} -r ${RESULT_DIR}/misc -v misc -i 1 -l ${IMAGE_MISC_SIZE} \
		-p ${FLASH_PAGE_SIZE} -b ${FLASH_BLOCK_SIZE} -c ${FLASH_DEVICE_SIZE}";
else
	err "Not support image type: ${IMAGE_TYPE}"
	exit 1;
fi

# copy to result
BSP_TOOL_FILES=(
	"${BASE_DIR}/tools/scripts/partmap_fastboot.sh"
	"${BASE_DIR}/tools/scripts/partmap_diskimg.sh"
	"${BASE_DIR}/tools/scripts/usb-down.sh"
	"${BASE_DIR}/tools/scripts/configs/udown.bootloader.sh"
	"${BASE_DIR}/tools/scripts/configs/udown.bootloader-secure.sh"
	"${BASE_DIR}/tools/bin/linux-usbdownloader"
	"${BASE_DIR}/tools/bin/simg2dev"
	"${BASE_DIR}/tools/files/partmap_*.txt"
	"${BASE_DIR}/tools/scripts/swu_image.sh"
	"${BASE_DIR}/tools/scripts/swu_hash.py"
	"${BASE_DIR}/tools/files/secure-bootkey.pem"
	"${BASE_DIR}/tools/files/secure-userkey.pem"
	"${BASE_DIR}/tools/files/secure-jtag-hash.txt"
	"${BASE_DIR}/tools/files/efuse_cfg-aes_enb.txt"
	"${BASE_DIR}/tools/files/efuse_cfg-verify_enb-hash0.txt"
	"${BASE_DIR}/tools/files/efuse_cfg-sjtag_enb.txt"
)

###############################################################################
# build commands
###############################################################################

function post_build_bl1 () {
	local binary=${BL1_DIR}/${BL1_BIN}
	local outdir=${BL1_DIR}

	if [[ ! -z $TARGET_BL1_DIR ]]; then
		binary=${BL1_DIR}/out/${BL1_BIN}
		outdir=${BL1_DIR}/out
	fi

	# Copy encrypt keys
	cp ${SECURE_BL1_ENCKEY} ${outdir}/$(basename $SECURE_BL1_ENCKEY)
	cp ${SECURE_BOOTKEY} ${outdir}/$(basename $SECURE_BOOTKEY)
	cp ${SECURE_USERKEY} ${outdir}/$(basename $SECURE_USERKEY)

	SECURE_BL1_ENCKEY=${outdir}/$(basename $SECURE_BL1_ENCKEY)
	SECURE_BOOTKEY=${outdir}/$(basename $SECURE_BOOTKEY)
	SECURE_USERKEY=${outdir}/$(basename $SECURE_USERKEY)

        # Encrypt binary : $BIN.enc
	msg " ENCRYPT: ${binary} -> ${binary}.enc"
       openssl enc -e -nosalt -aes-128-cbc -in ${binary} -out ${binary}.enc \
		-K $(cat ${SECURE_BL1_ENCKEY}) -iv ${SECURE_BL1_IVECTOR};

        # (Encrypted binary) + NSIH : $BIN.bin.enc.raw
	msg " BINGEN : ${binary}.enc -> ${binary}.enc.raw"
        ${TOOL_BINGEN} -k bl1 -n ${BL1_NSIH} -i ${binary}.enc \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} -l ${BL1_LOADADDR} -s ${BL1_LOADADDR} -t;

        # Binary + NSIH : $BIN.raw
	msg " BINGEN : ${binary} -> ${binary}.raw"
        ${TOOL_BINGEN} -k bl1 -n ${BL1_NSIH} -i ${binary} \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} -l ${BL1_LOADADDR} -s ${BL1_LOADADDR} -t;

	cp ${SECURE_BL1_ENCKEY} ${RESULT_DIR}
	cp ${SECURE_BOOTKEY}.pub.hash.txt ${RESULT_DIR}

	cp ${binary}.raw ${RESULT_DIR}
	cp ${binary}.enc.raw ${RESULT_DIR}
}

function post_build_bl2 () {
        # Binary + NSIH : $BIN.raw
	msg " BINGEN : ${BL2_BIN} -> ${BL2_BIN}.raw"
        ${TOOL_BINGEN} -k bl2 -n ${BL2_NSIH} -i ${BL2_DIR}/out/${BL2_BIN} \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} -l ${BL2_LOADADDR} -s ${BL2_LOADADDR} -t;

        cp ${BL2_DIR}/out/${BL2_BIN}.raw ${RESULT_DIR}/bl2.bin.raw;
}

function post_build_bl32 () {
	# Copy encrype keys
	cp ${SECURE_BL32_ENCKEY}  ${BL32_DIR}/out/$(basename $SECURE_BL32_ENCKEY)
	cp ${SECURE_BOOTKEY} ${BL32_DIR}/out/$(basename $SECURE_BOOTKEY)
	cp ${SECURE_USERKEY} ${BL32_DIR}/out/$(basename $SECURE_USERKEY)

	SECURE_BL32_ENCKEY=${BL32_DIR}/out/$(basename $SECURE_BL32_ENCKEY)
	SECURE_BOOTKEY=${BL32_DIR}/out/$(basename $SECURE_BOOTKEY)
	SECURE_USERKEY=${BL32_DIR}/out/$(basename $SECURE_USERKEY)

        # Encrypt binary : $BIN.enc
	msg " ENCRYPT: ${BL32_BIN} -> ${BL32_BIN}.enc"
	openssl enc -e -nosalt -aes-128-cbc \
		-in ${BL32_DIR}/out/${BL32_BIN} -out ${BL32_DIR}/out/${BL32_BIN}.enc \
		-K $(cat ${SECURE_BL32_ENCKEY}) -iv ${SECURE_BL32_IVECTOR};

        # (Encrypted binary) + NSIH : $BIN.enc.raw
	msg " BINGEN : ${BL32_BIN}.enc -> ${BL32_BIN}.enc.raw"
        ${TOOL_BINGEN} -k bl32 -n ${BL32_NSIH} -i ${BL32_DIR}/out/${BL32_BIN}.enc \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} \
		-l ${BL32_LOADADDR} -s ${BL32_LOADADDR} -t -e;

        # Binary + NSIH : $BIN.raw
	msg " BINGEN : ${BL32_BIN} -> ${BL32_BIN}.raw"
        ${TOOL_BINGEN} -k bl32 -n ${BL32_NSIH} -i ${BL32_DIR}/out/${BL32_BIN} \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} \
		-l ${BL32_LOADADDR} -s ${BL32_LOADADDR} -t;

	cp ${SECURE_BL32_ENCKEY} ${RESULT_DIR}

	cp ${BL32_DIR}/out/${BL32_BIN}.raw ${RESULT_DIR}
	cp ${BL32_DIR}/out/${BL32_BIN}.enc.raw ${RESULT_DIR}
}

function post_build_uboot () {
	msg " BINGEN : ${UBOOT_BIN} -> ${UBOOT_BIN}.raw"
        ${TOOL_BINGEN} -k bl33 -n ${UBOOT_NSIH} -i ${UBOOT_DIR}/${UBOOT_BIN} \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} \
		-l ${UBOOT_LOADADDR} -s ${UBOOT_LOADADDR} -t;

	cp ${UBOOT_DIR}/${UBOOT_BIN}.raw ${RESULT_DIR}

	# create param.bin
	${TOOL_BOOTPARAM} ${UBOOT_DIR} ${TOOLCHAIN_LINUX} ${RESULT_DIR}
}

function post_build_modules () {
	mkdir -p ${RESULT}/modules
	find ${KERNEL_DIR} -name *.ko | xargs cp -t ${RESULT}/modules
}

function make_boot_image () {
	if ! mkdir -p ${RESULT_DIR}/boot; then exit 1; fi

	cp -a ${RESULT_DIR}/${KERNEL_BIN} ${RESULT_DIR}/boot;
	cp -a ${RESULT_DIR}/${DTB_BIN} ${RESULT_DIR}/boot;
	[[ -f ${UBOOT_LOGO_BMP} ]] && cp -a ${UBOOT_LOGO_BMP} ${RESULT_DIR}/boot;

	MAKE_BOOT_IMAGE="$(echo "$MAKE_BOOT_IMAGE" | sed 's/\s\s*/ /g')"
	bash -c "${MAKE_BOOT_IMAGE}";
}

function make_root_image () {
	MAKE_ROOT_IMAGE="$(echo "$MAKE_ROOT_IMAGE" | sed 's/\s\s*/ /g')"
	bash -c "${MAKE_ROOT_IMAGE}";
}

function make_data_image () {
	[[ -z ${IMAGE_DATA_SIZE} ]] || [[ ${IMAGE_TYPE} == "ubi" ]] && return;
	[[ ! -d $RESULT_DIR/userdata ]] && mkdir -p $RESULT_DIR/userdata;

	MAKE_DATA_IMAGE="$(echo "$MAKE_DATA_IMAGE" | sed 's/\s\s*/ /g')"
	bash -c "${MAKE_DATA_IMAGE}";
}

function do_copy_tools () {
	for file in "${BSP_TOOL_FILES[@]}"; do
		[[ -d $file ]] && continue;
		cp -a $file ${RESULT_DIR}
	done
}

function do_result_link () {
	local link=result
	local ret=$(basename $RESULT_DIR)

	msg " RETDIR : $RESULT_DIR"
	cd $(dirname $RESULT_DIR)
	[[ -e $link ]] && [[ $(readlink $link) == $ret ]] && return;

	rm -f $link;
	ln -s $ret $link
}

###############################################################################
# Build Image and Targets
###############################################################################

BUILD_IMAGES=(
	"MACHINE= nxp3220",
	"ARCH  	= arm",
	"TOOL	= ${TOOLCHAIN_LINUX}",
	"RESULT = ${RESULT_DIR}",
	"bl1   	=
		PATH  	: ${BL1_DIR},
		TOOL  	: ${TOOLCHAIN_BOOTLOADER},
		POSTCMD : post_build_bl1,
		JOBS  	: 1", # must be 1
	"bl2   	=
		PATH  	: ${BL2_DIR},
		TOOL  	: ${TOOLCHAIN_BOOTLOADER},
		OPTION	: CHIPNAME=${BL2_CHIP} BOARD=${BL2_BOARD} PMIC=${BL2_PMIC},
		POSTCMD : post_build_bl2,
		JOBS  	: 1", # must be 1
	"bl32  =
		PATH  	: ${BL32_DIR},
		TOOL  	: ${TOOLCHAIN_BOOTLOADER},
		POSTCMD	: post_build_bl32,
		JOBS  	: 1", # must be 1
	"uboot 	=
		PATH  	: ${UBOOT_DIR},
		CONFIG	: ${UBOOT_DEFCONFIG},
		OUTPUT	: u-boot.bin,
		POSTCMD	: post_build_uboot"
	"br2   	=
		PATH  	: ${BR2_DIR},
		CONFIG	: ${BR2_DEFCONFIG},
		OUTPUT	: output/target,
		COPY  	: rootfs",
	"kernel	=
		PATH  	: ${KERNEL_DIR},
		CONFIG	: ${KERNEL_DEFCONFIG},
		IMAGE 	: ${KERNEL_BIN},
		OUTPUT	: arch/arm/boot/${KERNEL_BIN}",
	"dtb   	=
		PATH  	: ${KERNEL_DIR},
		IMAGE 	: ${DTB_BIN},
		OUTPUT	: arch/arm/boot/dts/${DTB_BIN}",

	"bootimg =
		POSTCMD : make_boot_image",

	"rootimg =
		POSTCMD : make_root_image",

	"dataimg =
		POSTCMD : make_data_image",

	"tools  =
		POSTCMD	: do_copy_tools",

	"ret    =
		POSTCMD	: do_result_link",
)
