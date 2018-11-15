#!/bin/bash

TARGET_BL1_NAME=nxp3220

TARGET_BL2_CHIP=sip_s31nx
TARGET_BL2_BOARD=vtk
TARGET_BL2_PMIC=sm5011
TARGET_BL2_NSIH=nsih_vtk_ddr3_800Mhz

TARGET_KERNEL_DEFCONFIG=sip_s31nx_vtk_defconfig
TARGET_KERNEL_DTB=sip-s31nx-vtk

TARGET_UBOOT_DEFCONFIG=sip_s31nx_vtk_defconfig

TARGET_BR2_DEFCONFIG=nxp3220_sysv_defconfig

CONFIGDIR="$(cd "$(dirname "$0")" && pwd)"/configs

source $CONFIGDIR/build.common.sh
