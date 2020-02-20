#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>
#

source $(realpath $(dirname "$0"))/configs/env_common.sh
function msg() {
	echo ""; echo  -e "\033[0;33m $@\033[0m"
}

# Add to build source at target script:
# export BASEDIR=`realpath "$(cd "$(dirname "$0")" && pwd)/../.."`
# TARGET_BL1_DIR=${BASEDIR}/firmwares/bl1-nxp3220

SECURE_BL1_IVECTOR=73FC7B44B996F9990261A01C9CB93C8F
SECURE_BL32_IVECTOR=73FC7B44B996F9990261A01C9CB93C8F

function post_build_bl1 () {
	local bl1_binary=${BL1_DIR}/${BL1_BIN}
	local outdir=${BL1_DIR}

	if [[ ! -z $TARGET_BL1_DIR ]]; then
		bl1_binary=${BL1_DIR}/out/${BL1_BIN}
		outdir=${BL1_DIR}/out
	fi

	# Copy encrypt keys
	cp ${SECURE_BL1_ENCKEY}  ${outdir}/$(basename $SECURE_BL1_ENCKEY)
	cp ${SECURE_BOOTKEY} ${outdir}/$(basename $SECURE_BOOTKEY)
	cp ${SECURE_USERKEY} ${outdir}/$(basename $SECURE_USERKEY)

	SECURE_BL1_ENCKEY=${outdir}/$(basename $SECURE_BL1_ENCKEY)
	SECURE_BOOTKEY=${outdir}/$(basename $SECURE_BOOTKEY)
	SECURE_USERKEY=${outdir}/$(basename $SECURE_USERKEY)

        # Encrypt binary : $BIN.enc
	msg "ENCRYPT: ${bl1_binary} -> ${bl1_binary}.enc"
       ${TOOL_BINENC} enc -e -nosalt -aes-128-cbc -in ${bl1_binary} -out ${bl1_binary}.enc \
		-K $(cat ${SECURE_BL1_ENCKEY}) -iv ${SECURE_BL1_IVECTOR};

        # (Encrypted binary) + NSIH : $BIN.bin.enc.raw
	msg "BINGEN : ${bl1_binary}.enc -> ${bl1_binary}.enc.raw"
        ${TOOL_BINGEN} -k bl1 -n ${BL1_NSIH} -i ${bl1_binary}.enc \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} -l ${BL1_LOADADDR} -s ${BL1_LOADADDR} -t;

        # Binary + NSIH : $BIN.raw
	msg "BINGEN : ${bl1_binary} -> ${bl1_binary}.raw"
        ${TOOL_BINGEN} -k bl1 -n ${BL1_NSIH} -i ${bl1_binary} \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} -l ${BL1_LOADADDR} -s ${BL1_LOADADDR} -t;

	cp ${SECURE_BL1_ENCKEY} ${RESULT}
	cp ${SECURE_BOOTKEY}.pub.hash.txt ${RESULT}

	cp ${bl1_binary}.raw ${RESULT}
	cp ${bl1_binary}.enc.raw ${RESULT}
}

function post_build_bl2 () {
        # Binary + NSIH : $BIN.raw
	msg "BINGEN : ${BL2_BIN} -> ${BL2_BIN}.raw"
        ${TOOL_BINGEN} -k bl2 -n ${BL2_NSIH} -i ${BL2_DIR}/out/${BL2_BIN} \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} -l ${BL2_LOADADDR} -s ${BL2_LOADADDR} -t;

        cp ${BL2_DIR}/out/${BL2_BIN}.raw ${RESULT}/bl2.bin.raw;
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
	msg "ENCRYPT: ${BL32_BIN} -> ${BL32_BIN}.enc"
	${TOOL_BINENC} enc -e -nosalt -aes-128-cbc \
		-in ${BL32_DIR}/out/${BL32_BIN} -out ${BL32_DIR}/out/${BL32_BIN}.enc \
		-K $(cat ${SECURE_BL32_ENCKEY}) -iv ${SECURE_BL32_IVECTOR};

        # (Encrypted binary) + NSIH : $BIN.enc.raw
	msg "BINGEN : ${BL32_BIN}.enc -> ${BL32_BIN}.enc.raw"
        ${TOOL_BINGEN} -k bl32 -n ${BL32_NSIH} -i ${BL32_DIR}/out/${BL32_BIN}.enc \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} \
		-l ${BL32_LOADADDR} -s ${BL32_LOADADDR} -t -e;

        # Binary + NSIH : $BIN.raw
	msg "BINGEN : ${BL32_BIN} -> ${BL32_BIN}.raw"
        ${TOOL_BINGEN} -k bl32 -n ${BL32_NSIH} -i ${BL32_DIR}/out/${BL32_BIN} \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} \
		-l ${BL32_LOADADDR} -s ${BL32_LOADADDR} -t;

	cp ${SECURE_BL32_ENCKEY} ${RESULT}

	cp ${BL32_DIR}/out/${BL32_BIN}.raw ${RESULT}
	cp ${BL32_DIR}/out/${BL32_BIN}.enc.raw ${RESULT}
}

function pre_build_uboot () {
	file=${UBOOT_DIR}/.uboot_defconfig
	[ -e ${file} ] && [[ $(cat ${file}) == "${UBOOT_DEFCONFIG}+bsp" ]] && return;
	rm -f ${file}; echo "${UBOOT_DEFCONFIG}+bsp" >> ${file};
	make -C ${UBOOT_DIR} distclean
}

function post_build_uboot () {
	msg "BINGEN : ${UBOOT_BIN} -> ${UBOOT_BIN}.raw"
        ${TOOL_BINGEN} -k bl33 -n ${UBOOT_NSIH} -i ${UBOOT_DIR}/${UBOOT_BIN} \
		-b ${SECURE_BOOTKEY} -u ${SECURE_USERKEY} \
		-l ${UBOOT_LOADADDR} -s ${UBOOT_LOADADDR} -t;

	cp ${UBOOT_DIR}/${UBOOT_BIN}.raw ${RESULT}

	# create param.bin
	${TOOL_MKPARAM} ${UBOOT_DIR} ${LINUX_TOOLCHAIN} ${RESULT}
}

function pre_build_kernel () {
	file=${KERNEL_DIR}/.kernel_defconfig
	[ -e ${file} ] && [[ $(cat ${file}) == "${KERNEL_DEFCONFIG}+bsp" ]] && return;
	rm -f ${file}; echo "${KERNEL_DEFCONFIG}+bsp" >> ${file};
	make -C ${KERNEL_DIR} distclean
}

function post_copy_tools () {
	for file in "${TOOL_FILES[@]}"; do
		[[ -d $file ]] && continue;
		cp -a $file ${RESULT}
	done
}

function post_data_image () {
	[[ ! ${IMAGE_DATA_SIZE} ]] || [[ ${IMAGE_TYPE} == "ubi" ]] && return;
	[[ ! -d $RESULT/userdata ]] && mkdir -p $RESULT/userdata;

	${TOOL_MKEXT4} -b 4096 -s -L userdata -l ${IMAGE_DATA_SIZE} $RESULT/userdata.img $RESULT/userdata
}

function post_ret_link () {

	if [[ -e ${BASEDIR}/out/result  ]] ||
	   [[ -h ${BASEDIR}/out/result ]]; then
		rm -f ${BASEDIR}/out/result
	fi

	ln -s ${RESULT} ${BASEDIR}/out/result
}

function pre_boot_image () {
	mkdir -p ${RESULT}/boot;
	cp -a ${RESULT}/${KERNEL_BIN} ${RESULT}/boot;
	cp -a ${RESULT}/${DTB_BIN} ${RESULT}/boot;
	if [ -f ${UBOOT_LOGO_BMP} ]; then
		cp -a ${UBOOT_LOGO_BMP} ${RESULT}/boot;
	fi
}

if [[ ${IMAGE_TYPE} == "ubi" ]]; then
	BOOT_POSTCMD="${TOOL_MKUBIFS} -r ${RESULT}/boot -v boot -i 0 -l ${IMAGE_BOOT_SIZE}
			-p ${FLASH_PAGE_SIZE} -b ${FLASH_BLOCK_SIZE} -c ${FLASH_DEVICE_SIZE}"
	ROOT_POSTCMD="${TOOL_MKUBIFS} -r ${RESULT}/rootfs -v rootfs -i 1 -l ${IMAGE_ROOT_SIZE}
			-p ${FLASH_PAGE_SIZE} -b ${FLASH_BLOCK_SIZE} -c ${FLASH_DEVICE_SIZE}"
else
	BOOT_POSTCMD="${TOOL_MKEXT4} -L boot -s -b 4k -l ${IMAGE_BOOT_SIZE} $RESULT/boot.img $RESULT/boot/"
	ROOT_POSTCMD="${TOOL_MKEXT4} -L rootfs -s -b 4k -l ${IMAGE_ROOT_SIZE} $RESULT/rootfs.img $RESULT/rootfs"
fi

# Build Targets
BUILD_IMAGES=(
	"MACHINE= nxp3220",
	"ARCH  	= arm",
	"TOOL	= ${LINUX_TOOLCHAIN}",
	"RESULT = ${RESULT}",
	"bl1   	=
		PATH  	: ${BL1_DIR},
		TOOL  	: ${BL_TOOLCHAIN},
		POSTCMD : post_build_bl1,
		JOBS  	: 1", # must be 1
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
		PRECMD	: pre_build_uboot,
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
		OUTPUT	: arch/arm/boot/${KERNEL_BIN},
		PRECMD	: pre_build_kernel",
	"dtb   	=
		PATH  	: ${KERNEL_DIR},
		IMAGE 	: ${DTB_BIN},
		OUTPUT	: arch/arm/boot/dts/${DTB_BIN}",
	"bootimg =
		PRECMD  : pre_boot_image,
		POSTCMD : $BOOT_POSTCMD",
	"rootimg =
		POSTCMD	: $ROOT_POSTCMD",
	"dataimg =
		POSTCMD	: post_data_image",
	"tools  =
		POSTCMD	: post_copy_tools",
	"ret    =
		POSTCMD	: post_ret_link",
)
