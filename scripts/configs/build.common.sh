#!/bin/bash

source $(readlink -e -n $(dirname "$0"))/configs/env_common.sh

function post_build_bl1 () {
        # Encrypt binary : $BIN.enc
        ${TOOL_BINENC} -n ${BL1_DIR}/${BL1_BIN} -k $(cat ${BL1_AESKEY}) \
		-v $(cat ${BL1_VECTOR}) -m enc -b 128;

        # (Encrypted binary) + NSIH : $BIN.bin.enc.raw
        ${TOOL_BINGEN} -k bl1 -n ${BL1_NSIH} -i ${BL1_DIR}/${BL1_BIN}.enc \
		-b ${BL1_BOOTKEY} -u ${BL1_USERKEY} -l ${BL1_LOADADDR} -s ${BL1_LOADADDR} -t;

        # Binary + NSIH : $BIN.raw
        ${TOOL_BINGEN} -k bl1 -n ${BL1_NSIH} -i ${BL1_DIR}/${BL1_BIN} \
		-b ${BL1_BOOTKEY} -u ${BL1_USERKEY} -l ${BL1_LOADADDR} -s ${BL1_LOADADDR} -t;

	cp ${BL1_DIR}/${BL1_BIN}.raw ${RESULT}
	cp ${BL1_DIR}/${BL1_BIN}.enc.raw ${RESULT}
}

function post_build_bl2 () {
        # Binary + NSIH : $BIN.raw
        ${TOOL_BINGEN} -k bl2 -n ${BL2_NSIH} -i ${BL2_DIR}/out/${BL2_BIN} \
		-b ${BL2_BOOTKEY} -u ${BL2_USERKEY} -l ${BL2_LOADADDR} -s ${BL2_LOADADDR} -t;

        cp ${BL2_DIR}/out/${BL2_BIN}.raw ${RESULT}/bl2.bin.raw;
}

function post_build_bl32 () {
        # Encrypt binary : $BIN.enc
        ${TOOL_BINENC} -n ${BL32_DIR}/out/${BL32_BIN} \
		-k $(cat ${BL32_AESKEY}) -v $(cat ${BL32_VECTOR}) -m enc -b 128;

        # (Encrypted binary) + NSIH : $BIN.enc.raw
        ${TOOL_BINGEN} -k bl32 -n ${BL32_NSIH} -i ${BL32_DIR}/out/${BL32_BIN}.enc \
		-b ${BL32_BOOTKEY} -u ${BL32_USERKEY} \
		-l ${BL32_LOADADDR} -s ${BL32_LOADADDR} -t;

        # Binary + NSIH : $BIN.raw
        ${TOOL_BINGEN} -k bl32 -n ${BL32_NSIH} -i ${BL32_DIR}/out/${BL32_BIN} \
		-b ${BL32_BOOTKEY} -u ${BL32_USERKEY} \
		-l ${BL32_LOADADDR} -s ${BL32_LOADADDR} -t;

	cp ${BL32_DIR}/out/${BL32_BIN}.raw ${RESULT}
	cp ${BL32_DIR}/out/${BL32_BIN}.enc.raw ${RESULT}
}

function post_build_uboot () {
        ${TOOL_BINGEN} -k bl33 -n ${UBOOT_NSIH} -i ${UBOOT_DIR}/${UBOOT_BIN} \
		-b ${UBOOT_BOOTKEY} -u ${UBOOT_USERKEY} \
		-l ${UBOOT_LOADADDR} -s ${UBOOT_LOADADDR} -t;

	cp ${UBOOT_DIR}/${UBOOT_BIN}.raw ${RESULT}

	# create param.bin
	${TOOL_MKPARAM} ${UBOOT_DIR} ${LINUX_TOOLCHAIN} ${RESULT}
}

function post_copy_tools () {
	for file in "${TOOL_FILES[@]}"; do
		[[ -d $file ]] && continue;
		cp -a $file ${RESULT}
	done
}

function post_ret_link () {
	if [[ $RESULT != ${BASEDIR}/out/result ]]; then
		rm -rf ${BASEDIR}/out/result
		ln -s ${RESULT} ${BASEDIR}/out/result
	fi
}

BOOT_PRECMD="mkdir -p ${RESULT}/boot;
	cp -a ${RESULT}/${KERNEL_BIN} ${RESULT}/boot;
	cp -a ${RESULT}/${DTB_BIN} ${RESULT}/boot;
	cp -a ${UBOOT_LOGO_BMP} ${RESULT}/boot;"

if [[ ${IMAGE_TYPE} == "ubi" ]]; then
	BOOT_POSTCMD="${TOOL_MKUBIFS} -r ${RESULT}/boot -v boot -i 0 -l ${IMAGE_BOOT_SIZE}
			-p ${FLASH_PAGE_SIZE} -b ${FLASH_BLOCK_SIZE} -c ${FLASH_DEVICE_SIZE}"
	ROOT_POSTCMD="${TOOL_MKUBIFS} -r ${RESULT}/rootfs -v rootfs -i 1 -l ${IMAGE_ROOT_SIZE}
			-p ${FLASH_PAGE_SIZE} -b ${FLASH_BLOCK_SIZE} -c ${FLASH_DEVICE_SIZE}"
else
	BOOT_POSTCMD="${TOOL_MKEXT4} -b 4096 -L boot -l ${IMAGE_BOOT_SIZE} $RESULT/boot.img $RESULT/boot/"
	ROOT_POSTCMD="${TOOL_MKEXT4} -b 4096 -s -L rootfs -l ${IMAGE_ROOT_SIZE} $RESULT/rootfs.img $RESULT/rootfs"
fi

# Build Targets
BUILD_IMAGES=(
	"MACHINE= nxp3220",
	"ARCH  	= arm",
	"TOOL	= ${LINUX_TOOLCHAIN}",
	"RESULT = ${RESULT}",
	"bl1   	=
		POSTCMD : post_build_bl1",
	"bl2   	=
		PATH  	: ${BL2_DIR},
		TOOL  	: ${BL_TOOLCHAIN},
		OPTION	: CHIPNAME=${BL2_CHIP} BOARD=${BL2_BOARD} PMIC=${BL2_PMIC},
		POSTCMD : post_build_bl2,
		JOBS  	: 1", # must be 1
	"bl32  =
		PATH  	: ${BL32_DIR},
		TOOL  	: ${BL_TOOLCHAIN},
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
		PRECMD  : $BOOT_PRECMD,
		POSTCMD : $BOOT_POSTCMD",
	"rootimg =
		POSTCMD	: $ROOT_POSTCMD",
	"tools  =
		POSTCMD	: post_copy_tools",
	"ret    =
		POSTCMD	: post_ret_link",
)
