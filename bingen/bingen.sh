#!/bin/bash

set -x

CURRENT_PATH=$(cd "$(dirname "$0")" && pwd)

PKKEYGEN="pkkeygen"
RSASIGN="rsasign"
BOOTGEN="bootgen"
NANDGEN="nandgen"
RESULT="result-bin"

PKKEYGEN_TOOL_PATH="${CURRENT_PATH}/${PKKEYGEN}"
RSASIGN_TOOL_PATH="${CURRENT_PATH}/${RSASIGN}"
BINGEN_TOOL_PATH="${CURRENT_PATH}/${BOOTGEN}"
NANDGEN_TOOL_PATH="${CURRENT_PATH}/${NANDGEN}"
RESULT_TOOL_PATH="${CURRENT_PATH}/${RESULT}"

function build_and_copy()
{
	mkdir $RESULT_TOOL_PATH

#	cp bootgen/raptor.txt $RESULT_TOOL_PATH
#	cp ~/test.bin $RESULT_TOOL_PATH/bootimage

	cd $PKKEYGEN_TOOL_PATH
	make clean;make
	cp $PKKEYGEN $RESULT_TOOL_PATH/


	cd $RSASIGN_TOOL_PATH
	make clean;make
	cp $RSASIGN $RESULT_TOOL_PATH/


	cd $BINGEN_TOOL_PATH
	make clean;make
	cp $BOOTGEN $RESULT_TOOL_PATH/

	cd $NANDGEN_TOOL_PATH
	make clean;make
	cp $NANDGEN $RESULT_TOOL_PATH/

	cd ../
}

function gen_private_key()
{
	cd $RESULT_TOOL_PATH
	./$PKKEYGEN filename=$RESULT_TOOL_PATH/bootkey.key
	./$PKKEYGEN filename=$RESULT_TOOL_PATH/userkey.key
}

function excute_rsasign()
{
	cd $RESULT_TOOL_PATH
	./$RSASIGN bootkey.key bootimage
	./$RSASIGN userkey.key userkey.key

	cp userkey.key.pub $RESULT_TOOL_PATH/bootimage.usr
}

function excute_bingen()
{
	cd $RESULT_TOOL_PATH
	./$BOOTGEN -n raptor.txt -i bootimage -t BL1
}

function excute_nandgen()
{
	cd $RESULT_TOOL_PATH
	./$NANDGEN -p 1024 -i bootimage.img
}

build_and_copy
gen_private_key
excute_rsasign
excute_bingen
#excute_nandgen
