#!/bin/bash

BASEDIR=$(cd "$(dirname "$0")" && pwd)
RESULT="$BASEDIR/../../result"

BLIMAGE=(
        "$RESULT/bl1-nxp3220.bin.raw" 		64
        "$RESULT/bl2-vtk.bin.raw"		64
        "$RESULT/sss.raw" 			32
        "$RESULT/bl32.bin.raw" 			2048
        "$RESULT/u-boot.bin.raw"  		0
        )

BLIMAGE_ENC=(
        "$RESULT/bl1-nxp3220.bin.enc.raw"	64
        "$RESULT/bl2-vtk.bin.raw"		64
        "$RESULT/sss.raw" 			32
        "$RESULT/bl32.bin.enc.raw"		2048
        "$RESULT/u-boot.bin.raw"  		0
        )

BLOCK_SIZE=1024
BLOCK_COUNT=8192				# set disk image size kbyte
ENC_OPTION=0					# (0: Not AES-CBC Encrypt, 1: Encrypt)

# Firmware Image Package - GPT Partition
function generate_gpt_image()
{
	bli=("${@}")
	seek=17408				# FIX: 512 * 34 = 17408 (LBA34: 0 ~ 33)
	size=0; n=0;

	if [ $ENC_OPTION == 1 ]; then
		disk="fip-gpt.enc.img"
	else
		disk="fip-gpt.img"
	fi

	[ -f $disk ] && sudo rm $disk;

	echo -e "\n\033[0;31m================================================================== \033[0m"
	echo " FIP-GPT : Support the GUID Partition Table Image		      "
	echo -e "\033[0;31m================================================================== \033[0m"

	sudo dd if=/dev/zero of=$disk bs=$BLOCK_SIZE count=$BLOCK_COUNT

	echo "Step 01. Generate GPT Partition"

	# first partition's offset more than 3M
	sudo parted $disk --script -- mklabel gpt
	sudo parted $disk --script -- mkpart primary 4 -1

	# check the partition info with "parted" or fdisk command
	# $> sudo parted fip-gpt.img
	# $> print

	echo "Step 02. Write image for match the format"

	for i in "${bli[@]}"
	do
		if [ $(( $n % 2 )) -eq 0 ]; then
			file=$i
		else
			seek=$(($seek + $size * 1024))
			size=$i

			echo "fip-gpt : $seek :`readlink -e -n "$file"` $disk"
			if [ ! -f $file ]; then
				echo ""
				echo "**** no such file: $file"
				echo ""
			else
				sudo dd if=$file of=$disk seek=$seek bs=1 conv=notrunc;sync
			fi
		fi
		n=$((n + 1));
	done

	# make to sparse
	echo ""
	echo "make to a sparse file $disk"
	cp --sparse=always $disk tmp.img
	sudo mv tmp.img $disk
	echo -n "actrual size: $(( $BLOCK_SIZE*$BLOCK_COUNT/1024/1024 ))M -> "
	echo -e "$(du -h $disk | cut -f1)"

	echo -e "\n\033[2;32m ----------------------------------------------------------------- \033[0m"
	echo " Copy to SD Card with Command:"
	echo " $> sudo dd if=fip-gpt.img of=/dev/sd? bs=1 seek=0"
	echo -e "\033[1;32m ----------------------------------------------------------------- \033[0m"

	mv $disk $RESULT/$disk

	echo -e "\n\033[1;23m ----------------------------------------------------------------- \033[0m"
	echo " *** Move   : $disk ***"
        echo " *** Result : `readlink -e -n "$RESULT/$disk"` ***"
	echo -e "\033[1;23m ----------------------------------------------------------------- \033[0m"

	sync
}

# Firmware Image Package - Loader Image
function generate_loader_image()
{
	bli=("${@}")
	seek=0
	size=0; n=0;

	if [ $ENC_OPTION == 1 ]; then
		image="fip-loader.enc.img"
	else
		image="fip-loader.img"
	fi

	[ -f $image ] && sudo rm $image;

	echo -e "\n\033[0;31m================================================================== \033[0m"
	echo " FIP-LOADER: Support the Loader Image (eMMC/SD/SPI)	      "
	echo -e "\033[0;31m================================================================== \033[0m"

	echo "Step 01. Write image for match the format"

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

			echo "fip-loader : $seek :`readlink -e -n "$file"` $image"
			if [ ! -f $file ]; then
				echo ""
				echo "**** no such file: $file"
				echo ""
			else
				sudo dd if=$file of=$image seek=$seek bs=1 conv=notrunc;sync
			fi
		fi
		n=$((n + 1));
	done

	# make to sparse
	echo ""
	echo "make to a sparse file $image"
	cp --sparse=always $image tmp.img
	sudo mv tmp.img $image
	echo -n "actrual size: $(( $BLOCK_SIZE*$BLOCK_COUNT/1024/1024 ))M -> "
	echo -e "$(du -h $image | cut -f1)"

	echo -e "\n\033[2;32m ----------------------------------------------------------------- \033[0m"
	echo " Copy to SD Card with Command:"
	echo " $> sudo dd if=fip-loader.img of=/dev/sd? bs=1 seek=0"
	echo -e "\033[1;32m ----------------------------------------------------------------- \033[0m"

	mv $image $RESULT/$image

	echo -e "\n\033[1;23m ----------------------------------------------------------------- \033[0m"
	echo " *** Move   : $image ***"
	echo " *** Result : `readlink -e -n "$RESULT/$image"` ***"
	echo -e "\033[1;23m ----------------------------------------------------------------- \033[0m"

	sync
}

# Firmware Image Package - MBR Partition
function generate_mbr_image()
{
	bli=("${@}")
	seek=512
	size=0; n=0;

	if [ $ENC_OPTION == 1 ]; then
		image="fip-mbr.enc.img"
	else
		image="fip-mbr.img"
	fi

	[ -f $image ] && sudo rm $image;

	echo -e "\n\033[0;31m================================================================== \033[0m"
	echo " FIP-MBR : Support the MBR Image (eMMC/SD)		      "
	echo -e "\033[0;31m================================================================== \033[0m"

	sudo dd if=/dev/zero of=$image bs=$BLOCK_SIZE count=$BLOCK_COUNT

	echo "Step 01. Generate the MBR"

	# first partition's offset more than 3M
	sudo parted $image --script -- mklabel msdos
	sudo parted $image --script -- mkpart primary 4 -1

	echo "Step 02. Write image for match the format"

	for i in "${bli[@]}"
	do
		if [ $(( $n % 2 )) -eq 0 ]; then
			file=$i
		else
			#
			if [ $n == 3 ]; then
				seek=$(($seek + 0x4200))
			fi
			seek=$(($seek + $size * 1024))
			size=$i

			echo "fip-mbr : $seek :`readlink -e -n "$file"` $image"
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
	echo "make to a sparse file $image"
	cp --sparse=always $image tmp.img
	sudo mv tmp.img $image
	echo -n "actrual size: $(( $BLOCK_SIZE*$BLOCK_COUNT/1024/1024 ))M -> "
	echo -e "$(du -h $image | cut -f1)"

	echo -e "\n\033[2;32m ----------------------------------------------------------------- \033[0m"
	echo " Copy to SD Card with Command:"
	echo " $> sudo dd if=fip-gpt.img of=/dev/sd? bs=1 seek=0"
	echo -e "\033[1;32m ----------------------------------------------------------------- \033[0m"

	mv $image $RESULT/$image

	echo -e "\n\033[1;23m ----------------------------------------------------------------- \033[0m"
	echo " *** Move   : $image ***"
        echo " *** Result : `readlink -e -n "$RESULT/$image"` ***"
	echo -e "\033[1;23m ----------------------------------------------------------------- \033[0m"
	sync
}

# Firmware Image Package
generate_gpt_image 	"${BLIMAGE[@]}"
generate_loader_image	"${BLIMAGE[@]}"
generate_mbr_image	"${BLIMAGE[@]}"

# Encrypted Firmware Image package
ENC_OPTION=1
generate_gpt_image	"${BLIMAGE_ENC[@]}"
generate_loader_image	"${BLIMAGE_ENC[@]}"
generate_mbr_image	"${BLIMAGE_ENC[@]}"
