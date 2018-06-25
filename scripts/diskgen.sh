#!/bin/bash

BASEDIR=$(cd "$(dirname "$0")" && pwd)
RESULT="$BASEDIR/../../result"

BLIMAGE=(
        "$RESULT/bl1-nxp3220.bin.raw" 	64
        "$RESULT/bl2-vtk.bin.raw" 	64
        "$RESULT/sss.raw" 		32
        "$RESULT/bl32.bin.raw" 		2048
        "$RESULT/u-boot.bin.raw"  	0
        )

BLOCK_SIZE=1024
BLOCK_COUNT=8192 # set disk image size kbyte

function generate_gptdisk()
{
	bli=("${@}")
	seek=17408	# FIX: 512 * 34 = 17408 (LBA34: 0 ~ 33)
	size=0; n=0;

	disk="bootdisk.img"

	[ -f $disk ] && sudo rm $disk;

	echo "BOOTDISK : $disk bs=$BLOCK_SIZE count= $BLOCK_COUNT"
	sudo dd if=/dev/zero of=$disk bs=$BLOCK_SIZE count=$BLOCK_COUNT

	echo "BOOTDISK : partition"

	# first partition's offset more than 3M
	sudo parted $disk --script -- mklabel gpt
	sudo parted $disk --script -- mkpart primary 4 -1

	# check the partition info with "parted" or fdisk command 
	# $> sudo parted bootdisk.img
	# $> print

	echo "BOOTDISK : boot images"

	for i in "${bli[@]}"
	do
		if [ $(( $n % 2 )) -eq 0 ]; then
			file=$i
		else
			seek=$(($seek + $size * 1024))
			size=$i

			echo "BOOTDISK : $seek :`readlink -e -n "$file"` $disk"
			if [ ! -f $file ]; then
				echo "**** No such file: skip 'dd'"
			else
				sudo dd if=$file of=$disk seek=$seek bs=1 conv=notrunc;sync
			fi
		fi
		n=$((n + 1));
	done

	# make to sparse
	echo "Make to a sparse file $disk"
	cp --sparse=always $disk tmp.img
	sudo mv tmp.img $disk
	echo -n "Actrual size: $(( $BLOCK_SIZE*$BLOCK_COUNT/1024/1024 ))M -> "
	echo -e "$(du -h $disk | cut -f1)"

	echo "================================================================"
	echo "Copy to SD card with command:"
	echo "$> sudo dd if=bootdisk.img of=/dev/sd? bs=1 seek=0"
	echo "================================================================"
	sync
}

generate_gptdisk "${BLIMAGE[@]}"

