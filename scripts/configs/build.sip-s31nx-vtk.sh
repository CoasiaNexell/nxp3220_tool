#!/bin/bash

TARGET_CHIP=sip-s31nx
TARGET_CHIP_ALIAS=sip_s31nx
TARGET_BOARD=vtk

CONFIGDIR="$(cd "$(dirname "$0")" && pwd)"/configs

source $CONFIGDIR/build.common.sh
