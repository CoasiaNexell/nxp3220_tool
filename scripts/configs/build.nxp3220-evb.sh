#!/bin/bash

TARGET_RESULT=result-nxp3220-evb

# For BL2
TARGET_BL2_CHIP=nxp3220
TARGET_BL2_BOARD=evb
TARGET_BL2_PMIC=nxe1500
TARGET_BL2_NSIH=nsih_evb_ddr3_800Mhz.txt

# For BL32
TARGET_BL32_LOADADDR=0x5F000000

# For Kernel
TARGET_KERNEL_DEFCONFIG=nxp3220_evb_defconfig
TARGET_KERNEL_DTB=nxp3220-evb
TARGET_KERNEL_IMAGE=zImage

# For U-boot
TARGET_UBOOT_DEFCONFIG=nxp3220_evb_defconfig

# For Buildroot
TARGET_BR2_DEFCONFIG=nxp3220_sysv_defconfig

# For Filesystem image
TARGET_IMAGE_TYPE="ext4"
TARGET_BOOT_IMAGE_SIZE=32M
TARGET_ROOT_IMAGE_SIZE=1G

# build script
BUILD_CONFIG_DIR="$(cd "$(dirname "$0")" && pwd)"/configs
source $BUILD_CONFIG_DIR/build.common.sh
