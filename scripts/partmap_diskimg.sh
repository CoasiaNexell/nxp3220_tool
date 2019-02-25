#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
RESULTDIR="$BASEDIR/../../result"

DISK_NAME="disk.img"

DISK_TARGET_CONTEXT=()
DISK_TARGET_NAME=()

DISK_PART_IMAGE=()
DISK_DATA_IMAGE=()
DISK_PART_TYPE=

SZ_KB=$((1024))
SZ_MB=$(($SZ_KB * 1024))
SZ_GB=$(($SZ_MB * 1024))

BLOCK_UNIT=$((512)) # FIX
DISK_RESERVED=$((500 * $SZ_MB))
DISK_SIZE=$((8 * $SZ_GB))

LOOP_DEVICE=
LOSETUP_LOOP_DEV=false

function usage () {
	echo "usage: `basename $0` -f [partmap file] <targets> <options>"
	echo ""
	echo "[OPTIONS]"
	echo "  -d : file path for disk image, default: `readlink -e -n $RESULTDIR`"
	echo "  -i : partmap info"
	echo "  -l : listup target in partmap list"
	echo "  -s : disk size: n GB (default $(($DISK_SIZE / $SZ_GB)) GB)"
	echo "  -r : reserved size: n MB (default $(($DISK_RESERVED / $SZ_MB)) MB)"
	echo "  -t : 'dd' with losetup loop device to mount image"
	echo "  -n : set disk image name (default $DISK_NAME)"
	echo ""
	echo "Partmap struct:"
	echo "  fash=<>,<>:<>:<partition>:<start:hex>,<size:hex>"
	echo "  part   : gpt or mbr else ..."
	echo ""
	echo "DISK mount: with '-t' option"
	echo "  $> sudo losetup -f"
	echo "  $> sudo losetup /dev/loopN <image>"
	echo "  $> sudo mount /dev/loopNpn mnt"
	echo "  $> sudo losetup -d /dev/loopN"
	echo ""
	echo "Required packages:"
	echo "  parted"
	echo "  simg2img (android-tools)"
}

function make_partition () {
	local disk=$1 start=$2 size=$3 file=$4
	local end=$(($start + $size))

	# unit:
	# ¡®s¡¯   : sector (n bytes depending on the sector size, often 512)
	# ¡®B¡¯   : byte

	sudo parted --script $disk -- unit s mkpart primary $(($start / $BLOCK_UNIT)) $(($(($end / $BLOCK_UNIT)) - 1))
	if [ $? -ne 0 ]; then
		[[ -n $LOOP_DEVICE ]] && sudo losetup -d $LOOP_DEVICE
	 	exit 1;
	fi
}

function dd_push_image () {
	local disk=$1 start=$2 size=$3 file=$4 option=$5

	[[ -z $file ]] || [[ ! -f $file ]] && return;

	sudo dd if=$file of=$disk seek=$(($start / $BLOCK_UNIT)) bs=$BLOCK_UNIT $option status=none;
	if [ $? -ne 0 ]; then
		[[ -n $LOOP_DEVICE ]] && sudo losetup -d $LOOP_DEVICE
	 	exit 1;
	fi
}

function create_disk_image () {
	local disk="$RESULTDIR/$DISK_NAME"
	local image=$disk

	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
	echo -e "\033[0;33m DISK : $(basename $disk)\033[0m"
	echo -e "\033[0;33m SIZE : $(($DISK_SIZE / $SZ_MB)) MB - $(($DISK_RESERVED / $SZ_MB)) MB\033[0m"
	echo -e "\033[0;33m PART : $(echo $DISK_PART_TYPE | tr 'a-z' 'A-Z')\033[0m"
	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"

	# create disk image with DD
	sudo dd if=/dev/zero of=$disk bs=1 count=0 seek=$(($DISK_SIZE)) status=none
	[ $? -ne 0 ] && exit 1;

	if [ $LOSETUP_LOOP_DEV == true ]; then
		LOOP_DEVICE=$(sudo losetup -f)
		sudo losetup $LOOP_DEVICE $disk
		[ $? -ne 0 ] && exit 1;

		# Change disk name
		disk=$LOOP_DEVICE
		echo -e "\033[0;33m LOOP: $disk\033[0m"
	fi

	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
	for i in ${DISK_DATA_IMAGE[@]}
	do
		seek=$(echo $i| cut -d':' -f 3)
		size=$(echo $i| cut -d':' -f 4)
		file=$(echo $i| cut -d':' -f 5)

		printf " DATA :"
		[ ! -z "$seek" ] && printf " %6d KB:" $(($seek / $SZ_KB));
		[ ! -z "$size" ] && printf " %6d KB:" $(($size / $SZ_KB))
		[ ! -z "$file" ] && printf " %s\n" $file

		dd_push_image "$disk" "$seek" "$size" "$file" "conv=notrunc"
	done
	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"

	# make partition table type
	case $DISK_PART_TYPE in
	gpt ) sudo parted $disk --script -- unit s mklabel gpt;;
	mbr ) sudo parted $disk --script -- unit s mklabel msdos;;
	--) ;;
	esac

	if [ $? -ne 0 ]; then
		[[ -n $LOOP_DEVICE ]] && sudo losetup -d $LOOP_DEVICE
	 	exit 1;
	fi

	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
	for i in ${DISK_PART_IMAGE[@]}
	do
		tmpf=
		seek=$(echo $i| cut -d':' -f 3)
		size=$(echo $i| cut -d':' -f 4)
		file=$(echo $i| cut -d':' -f 5)

		if [[ -n $file ]] && [[ -f $file ]] &&
		   [[ ! -z "$(file $file | grep 'Android sparse')" ]]; then
			simg2img $file $file.tmp
			file=$file.tmp
			tmpf=$file
		fi

		printf " %s  :" $(echo $DISK_PART_TYPE | tr 'a-z' 'A-Z');
		[ ! -z "$seek" ] && printf " %6d MB:" $(($seek / $SZ_MB));
		[ ! -z "$size" ] && printf " %6d MB:" $(($size / $SZ_MB))
		[ ! -z "$file" ] && printf " %s " $file

		if [[ -n $tmpf ]]; then
			printf "(UNPACK)\n"
		else
			printf "\n" $file
		fi

		make_partition "$disk" "$seek" "$size" "$file"
		dd_push_image "$disk" "$seek" "$size" "$file" "conv=notrunc"

		if [[ -n $tmpf ]]; then
			rm $tmpf
		fi
	done

	[[ -n $LOOP_DEVICE ]] && sudo losetup -d $LOOP_DEVICE

	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
	echo -e "\033[0;33m RET  : `readlink -e -n $image`\033[0m"
	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
	echo -e "\033[0;33m $> sudo dd if=`readlink -e -n $image` of=/dev/sd? bs=1M\033[0m"
	echo -e "\033[0;33m $> sync\033[0m"
	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
}

function parse_images () {
	local offset=0

	for i in "${DISK_TARGET_NAME[@]}"
	do
		file=""
		for n in "${DISK_TARGET_CONTEXT[@]}"
		do
			name=$(echo $n| cut -d':' -f 2)
			if [ "$i" == "$name" ]; then
				type=$(echo $n| cut -d':' -f 3)
				seek=$(echo $(echo $n| cut -d':' -f 4) | cut -d',' -f 1)
				size=$(echo $(echo $n| cut -d':' -f 4) | cut -d',' -f 2)
				file=$(echo $(echo $n| cut -d':' -f 5) | cut -d';' -f 1)
				break;
			fi
		done

		# get partition type: gpt/mbr
		local part=
		case "$type" in
		gpt ) part=$type;;
		mbr ) part=$type;;
		--) ;;
		esac

		[ $(($seek)) -gt $(($offset)) ] && offset=$(($seek));
		[ $(($size)) -eq 0 ] && size=$(($DISK_SIZE - $DISK_RESERVED - $offset));

		# check file path
		if [[ -n $file ]]; then
			file="$RESULTDIR/$file"
			if [ ! -f "$file" ]; then
				file=./$(basename $file)
				if [ ! -f "$file" ]; then
					file="$file(NONE)";
				else
					RESULTDIR=./
				fi
			fi
		fi

		if [[ -n $part ]]; then
			if [[ -n $DISK_PART_TYPE ]] && [[ $part != $DISK_PART_TYPE ]]; then
				echo -e "\033[47;31m Another partition $type: $DISK_PART_TYPE !!!\033[0m";
				exit 1;
			fi
			DISK_PART_TYPE=$part
			DISK_PART_IMAGE+=("$name:$type:$seek:$size:$file");
		else
			DISK_DATA_IMAGE+=("$name:$type:$seek:$size:$file");
		fi
	done
}

function parse_target () {
	local value=$1	# $1 = store the value
	local params=("${@}")
	local images=("${params[@]:1}")	 # $3 = search array

	for i in "${images[@]}"
	do
		local val="$(echo $i| cut -d':' -f 2)"
		eval "${value}+=(\"${val}\")"
	done
}

case "$1" in
	-f )
		mapfile=$2
		maplist=()
		args=$# options=0 counts=0

		if [ ! -f $mapfile ]; then
			echo -e "\033[47;31m No such to partmap: $mapfile \033[0m"
			exit 1;
		fi

		while read line;
		do
			if [[ "$line" == *"#"* ]];then
				continue
			fi

			DISK_TARGET_CONTEXT+=($line)
		done < $mapfile

		parse_target maplist "${DISK_TARGET_CONTEXT[@]}"

		while [ "$#" -gt 2 ]; do
			# argc
			for i in "${maplist[@]}"
			do
				if [ "$i" == "$3" ]; then
					DISK_TARGET_NAME+=("$i");
					shift 1
					break
				fi
			done

			case "$3" in
			-d )	RESULTDIR=$4; ((options+=2)); shift 2;;
			-s )	DISK_SIZE=$(($4 * $SZ_GB)); ((options+=2)); shift 2;;
			-r )	DISK_RESERVED=$(($4 * $SZ_MB)); ((options+=2)); shift 2;;
			-n )	DISK_NAME=$4; ((options+=2)); shift 2;;
			-l )
				echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
				echo -en " Partmap targets: "
				for i in "${maplist[@]}"
				do
					echo -n "$i "
				done
				echo -e "\n\033[0;33m------------------------------------------------------------------ \033[0m"
				exit 0;;
			-i )
				echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
				for i in "${DISK_TARGET_CONTEXT[@]}"
				do
					val="$(echo "$(echo "$i" | cut -d':' -f4)" | cut -d',' -f2)"
					if [[ $val -ge "$SZ_GB" ]]; then
						len="$((val/$SZ_GB)) GB"
					elif [[ $val -ge "$SZ_MB" ]]; then
						len="$((val/$SZ_MB)) MB"
					else
						len="$((val/$SZ_KB)) KB"
					fi
					echo -e "$i [$len]"
				done
				echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
				exit 0;;
			-t )
				LOSETUP_LOOP_DEV=true;((options+=1));
				 shift 1;;
			-e )
				vim $mapfile
				exit 0;;
			-h )	usage;	exit 1;;
			* )
				if [ $((counts+=1)) -gt $args ]; then
					break;
				fi
				;;
			esac
		done

		((args-=2))
		num=${#DISK_TARGET_NAME[@]}
		num=$((args-num-options))

		if [ $num -ne 0 ]; then
			echo -e "\033[47;31m Unknown target: $mapfile\033[0m"
			echo -en " Check targets: "
			for i in "${maplist[@]}"
			do
				echo -n "$i "
			done
			echo ""
			exit 1
		fi

		if [ ${#DISK_TARGET_NAME[@]} -eq 0 ]; then
			DISK_TARGET_NAME=(${maplist[@]})
		fi

		parse_images $mapfile
		create_disk_image
		;;
	-h | * )
		usage;
		exit 1;;
esac
