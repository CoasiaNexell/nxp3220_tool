#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Deokjin, Lee <truevirtue@nexell.co.kr>

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)
RESULT_PATH="$BASEDIR/../../result"
OUTPUT_PATH="$RESULT_PATH"

GENERATE_TARGETS=("gpt" "loader" "mbr")

IMAGE_PARTMAP=(
        "$RESULT_PATH/bl1-nxp3220.bin.raw" 	64
        "$RESULT_PATH/bl2-vtk.bin.raw"		64
        "$RESULT_PATH/sss.raw" 			32
        "$RESULT_PATH/bl32.bin.raw" 		2048
        "$RESULT_PATH/u-boot.bin.raw"  		0
        )

# Block Variables
BLOCK_SIZE=1024
BLOCK_COUNT=8192				# set disk image size kbyte

function usage() {
	echo "Usage: `basename $0` [-f file name] [build target: gpt/mbr/loader] -d [result_path]"
	echo "Sample examples you can try."
	echo "Example0) ./$0 -f ../files/partmap_emmc.txt"
	echo "Example1) ./$0 -f ../files/partmap_emmc.txt -d ../../result_evb"
	echo "Example2) ./$0 -f ../files/partmap_emmc.txt gpt mbr -d ../../result_evb"
	echo ""
	echo "Fusing: If you are trying to Fusing SD Card"
	echo "Example0) sudo dd if=/dev/zero of=../../result/fip-gpt bs=512"
	echo "Example1) sudo dd if=/dev/zero of=../../result/fip-mbr bs=512"
	echo "Use the u-boot command if you are going to fusing to SPI flash or eMMC."
}

# Firmware Image Package - GPT Partition
function generate_gpt_image() {
	local images_list=("${@}")
	local seek=17408				# FIX: (512 * 34) = 17408 (LBA34: 0 ~ 33)
	local size=0; n=0;

	disk="fip-gpt.img"

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

	for i in "${images_list[@]}"
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

	mv $disk $OUTPUT_PATH/$disk

	echo -e "\n\033[1;23m ----------------------------------------------------------------- \033[0m"
	echo " *** Move   : $disk ***"
        echo " *** Result : `readlink -e -n "$OUTPUT_PATH/$disk"` ***"
	echo -e "\033[1;23m ----------------------------------------------------------------- \033[0m"

	sync
}

# Firmware Image Package - Loader Image
function generate_loader_image() {
	local images_list=("${@}")
	local seek=0
	local size=0; n=0;

	image="fip-loader.img"

	[ -f $image ] && sudo rm $image;

	echo -e "\n\033[0;31m================================================================== \033[0m"
	echo " FIP-LOADER: Support the Loader Image (eMMC/SD/SPI)	      "
	echo -e "\033[0;31m================================================================== \033[0m"

	echo "Step 01. Write image for match the format"

	for i in "${images_list[@]}"
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

	mv $image $OUTPUT_PATH/$image

	echo -e "\n\033[1;23m ----------------------------------------------------------------- \033[0m"
	echo " *** Move   : $image ***"
	echo " *** Result : `readlink -e -n "$OUTPUT_PATH/$image"` ***"
	echo -e "\033[1;23m ----------------------------------------------------------------- \033[0m"

	sync
}

# Firmware Image Package - MBR Partition
function generate_mbr_image() {
	local images_list=("${@}")
	local seek=512
	local size=0; n=0;

	image="fip-mbr.img"

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

	for i in "${images_list[@]}"
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

	mv $image $OUTPUT_PATH/$image

	echo -e "\n\033[1;23m ----------------------------------------------------------------- \033[0m"
	echo " *** Move   : $image ***"
        echo " *** Result : `readlink -e -n "$OUTPUT_PATH/$image"` ***"
	echo -e "\033[1;23m ----------------------------------------------------------------- \033[0m"
	sync
}

function parsing_partmap() {
	local partmap_file=$1
	local partmap_context=
	local count=0
	local number=0

	if [ ! -f $partmap_file ]; then
		echo -e "\033[47;31m No such to partmap: $partmap_file \033[0m"
		exit 1;
	fi

	while read line;
	do
		if [[ "$line" == *"#"* ]];then
			continue
		fi

		partmap_context+=($line)
	done < $partmap_file

	for i in ${partmap_context[@]}
	do
		# parsing information
		fname=$(echo $(echo $i| cut -d':' -f 5) | cut -d';' -f 1)
		size=$(echo $(echo $i| cut -d':' -f 4) | cut -d',' -f 2)
		# convert the for unit (KB)
		size=$((size/1024))

		if [ $count -eq 0 ]; then
			number=0
		else
			number=$((count*2))
		fi

		# check the index number
		if [ $number -eq 4 ]; then
			# skip the SSS image
			count=$((count+1))
			number=$((count*2))
		elif [ $number -eq 10 ]; then
			break;
		fi

		IMAGE_PARTMAP[$number]=$RESULT_PATH/$fname
		IMAGE_PARTMAP[$((number+1))]=$size

		count=$((count+1))
	done
}

# main
case "$1" in
	-f )
		partmap_file=$2
		generate_targets=()
		count=0

		while [ "$#" -gt 2 ]; do
			count=0
			while true; do
				if [ "${GENERATE_TARGETS[$count]}" == "$3" ]; then
					generate_targets+=("$3");
					shift 1
				fi

				count=$((count+1))
				if [ $count -ge ${#GENERATE_TARGETS[@]} ]; then
					break;
				fi
			done

			case "$3" in
				-d )	OUTPUT_PATH=$4;
					OUTPUT_PATH="$(realpath $OUTPUT_PATH)"
					shift 2;;
				-h )	usage; exit 1;;
				* )	shift;;
			esac
		done

		# parsing partmap file
		parsing_partmap $partmap_file

		if [ ${#generate_targets[@]} -eq 0 ]; then
			generate_targets=(${GENERATE_TARGETS[@]})
		fi

		# generate images
		for target in "${generate_targets[@]}"
		do
			if [ "$target" == "gpt" ]; then
				generate_gpt_image "${IMAGE_PARTMAP[@]}"
			elif [ "$target" == "loader" ]; then
				generate_loader_image "${IMAGE_PARTMAP[@]}"
			elif [ "$target" == "mbr" ]; then
				generate_mbr_image "${IMAGE_PARTMAP[@]}"
			fi
		done
		;;
	-h | * )
		usage
		exit 1
esac
