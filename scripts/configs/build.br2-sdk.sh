#!/bin/bash

BASEDIR="$(cd "$(dirname "$0")" && pwd)/../.."
KERNEL_DIR=$BASEDIR/kernel-4.14
LIBRARY_DIR=$BASEDIR/library
BR2_DIR=$BASEDIR/buildroot

BR2_TOOLCHAIN_DIR=$BR2_DIR/output/host
BR2_INSTALL_DIR=$BR2_TOOLCHAIN_DIR/arm-buildroot-linux-gnueabihf/sysroot
BR2_TOOLCHAIN="$BR2_TOOLCHAIN_DIR/bin/arm-linux-gnueabihf"

SETUP_ENV=". $BASEDIR/tools/scripts/env_setup_br2_sdk.sh $BR2_TOOLCHAIN_DIR"
MK_LIB="$BASEDIR/tools/scripts/mk_library.sh"
MK_SDK="$BASEDIR/tools/scripts/mk_br2sdk.sh"

# Build commands
BUILD_PREPARE="mkdir -p $BR2_INSTALL_DIR/usr/include/nexell; cp $KERNEL_DIR/include/uapi/drm/nexell_drm.h $BR2_INSTALL_DIR/usr/include/nexell"
BUILD_NX_VIDEO_API="$SETUP_ENV; $MK_LIB -l $LIBRARY_DIR/nx-video-api -d $BR2_INSTALL_DIR -t $BR2_TOOLCHAIN"

# Build Targets
BUILD_IMAGES=(
	"prepare = POSTCMD : $BUILD_PREPARE",
	"nx-video-api =	POSTCMD : $BUILD_NX_VIDEO_API",
	"sdk = POSTCMD : $MK_SDK",
)
