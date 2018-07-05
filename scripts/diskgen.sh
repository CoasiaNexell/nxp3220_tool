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

function generate_gpt_sd_disk()
{
	bli=("${@}")
	seek=17408	# FIX: 512 * 34 = 17408 (LBA34: 0 ~ 33)
	size=0; n=0;

	disk="bootdisk.img"

	[ -f $disk ] && sudo rm $disk;

	echo "================================================================"
	echo "BOOTDISK : $disk bs=$BLOCK_SIZE count= $BLOCK_COUNT"
	echo "================================================================"

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
				echo ""
				echo "**** No such file: $file"
				echo ""
			else
				sudo dd if=$file of=$disk seek=$seek bs=1 conv=notrunc;sync
			fi
		fi
		n=$((n + 1));
	done

	# make to sparse
	echo ""
	echo "Make to a sparse file $disk"
	cp --sparse=always $disk tmp.img
	sudo mv tmp.img $disk
	echo -n "Actrual size: $(( $BLOCK_SIZE*$BLOCK_COUNT/1024/1024 ))M -> "
	echo -e "$(du -h $disk | cut -f1)"

	echo ""
	echo "Copy to SD card with command:"
	echo "$> sudo dd if=bootdisk.img of=/dev/sd? bs=1 seek=0"
	echo ""

	mv $disk $RESULT/$disk

	echo "*** MOVE   : $image ***"
        echo "*** RESULT : `readlink -e -n "$RESULT/$disk"` ***"

	sync
}

function generate_gpt_emmc_img()
{
	bli=("${@}")
	seek=0	# FIX: 512 * 34 = 17408 (LBA34: 0 ~ 33)
	block_size=512  # FIX: 512
	size=0; n=0;

	image="emmcboot.img"

	[ -f $image ] && sudo rm $image;

	echo "================================================================"
	echo "EMMCBOOT : emmc boot images"
	echo "================================================================"

	for i in "${bli[@]}"
	do
		if [ $(( $n % 2 )) -eq 0 ]; then
			file=$i
		else
			if [ ! -f $file ]; then
				echo ""
				echo "**** No such file: $file"
				echo ""
			else
				echo "EMMCBOOT: $seek :`readlink -e -n "$file"` $image"
				sudo dd if=$file of=$image seek=$seek bs=1;sync

				# get next offset
				size=$(stat -c %s $file)
				next=`expr $seek + $size + $block_size - 1`
				next=`expr $next / $block_size`
				next=`expr $next \* $block_size`
				seek=$next
			fi
		fi
		n=$((n + 1));
	done

	echo ""
	echo -n "Actrual size: "
	echo -e "$(du -h $image | cut -f1)"

	mv $image $RESULT/$image

	echo "*** MOVE   : $image ***"
        echo "*** RESULT : `readlink -e -n "$RESULT/$image"` ***"

	sync
}

function generate_spi_img()
{
	bli=("${@}")
	seek=0
	size=0; n=0;
	image="spi.img"
	[ -f $image ] && sudo rm $image;

	echo "================================================================"
	echo "BOOTIMAGE : SPI boot Image									  "
	echo "================================================================"

	for i in "${bli[@]}"
	do
		if [ $(( $n % 2 )) -eq 0 ]; then
			file=$i
		else
			# bl2 offset is 0x1440 (81Kbyte)
			if [ $n == 3 ]; then
				seek=$(($seek + 0x4400))
			fi
			seek=$(($seek + $size * 1024))
			size=$i

			echo "SPIIMAGE : $seek :`readlink -e -n "$file"` $image"
			if [ ! -f $file ]; then
				echo ""
				echo "**** No such file: $file"
				echo ""
			else
				sudo dd if=$file of=$image seek=$seek bs=1 conv=notrunc;sync
			fi
		fi
		n=$((n + 1));
	done

	# make to sparse
	echo ""
	echo "Make to a sparse file $image"
	cp --sparse=always $image tmp.img
	sudo mv tmp.img $image
	echo -n "Actrual size: $(( $BLOCK_SIZE*$BLOCK_COUNT/1024/1024 ))M -> "
	echo -e "$(du -h $image | cut -f1)"

	echo ""
	echo "Copy to SPI Image with command:"
	echo "$> sudo dd if=spi.img of=/dev/sd? bs=1 seek=0"
	echo ""

	mv $image $RESULT/$image

	echo "*** MOVE   : $image ***"
	echo "*** RESULT : `readlink -e -n "$RESULT/$image"` ***"

	sync
}

generate_gpt_sd_disk  "${BLIMAGE[@]}"
generate_gpt_emmc_img "${BLIMAGE[@]}"
generate_spi_img "${BLIMAGE[@]}"
