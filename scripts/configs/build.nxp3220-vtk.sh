#!/bin/bash

TARGET_CHIP=nxp3220
TARGET_CHIP_ALIAS=$TARGET_CHIP
TARGET_BOARD=vtk

CONFIGDIR="$(cd "$(dirname "$0")" && pwd)"/configs

source $CONFIGDIR/build.common.sh
