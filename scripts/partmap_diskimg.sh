#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
RESULTDIR="$BASEDIR/../../result"

DISK_IMAGE_NAME="disk.img"
DISK_UPDATE_DEV=""

declare -A DISK_PARTITION=(
	["mbr"]="msdos"
	["gpt"]="gpt"
)

DISK_CHECK_SYSTEM=(
	"/dev/sr"
	"/dev/sda"
	"/dev/sdb"
	"/dev/sdc"
)

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
	echo "  -u : device/image name to write <targets> image"
	echo "  -n : disk image name (default $DISK_IMAGE_NAME)"
	echo "  -t : 'dd' with losetup loop device to mount image"
	echo ""
	echo "Partmap struct:"
	echo "  fash=<>,<>:<>:<partition>:<start:hex>,<size:hex>"
	echo "  part   : gpt or mbr else ..."
	echo ""
	echo "DISK update:"
	echo "  $> sudo dd if=<path>/<image> of=/dev/sd? bs=1M"
	echo "  $> sync"
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
	local disk="$RESULTDIR/$DISK_IMAGE_NAME"
	local image=$disk

	if [[ -n $DISK_UPDATE_DEV ]]; then
		disk=$DISK_UPDATE_DEV
		image=$disk
		LOSETUP_LOOP_DEV=false # not support
	fi

	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
	if [[ ! -n $DISK_UPDATE_DEV ]]; then
		echo -e "\033[0;33m DISK : $(basename $disk)\033[0m"
		echo -e "\033[0;33m SIZE : $(($DISK_SIZE / $SZ_MB)) MB - $(($DISK_RESERVED / $SZ_MB)) MB\033[0m"
		echo -e "\033[0;33m PART : $(echo $DISK_PART_TYPE | tr 'a-z' 'A-Z')\033[0m"
	else
		echo -e "\033[0;33m DISK : $disk\033[0m"
		echo -ne "\033[0;33m IMG  : \033[0m"
		for i in ${DISK_TARGET_NAME[@]}
		do
			echo -ne "\033[0;33m$i \033[0m"
		done
		echo -e "\033[0;33m \033[0m"
	fi
	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"

	# create disk image with DD
	if [[ ! -n $DISK_UPDATE_DEV ]]; then
		sudo dd if=/dev/zero of=$disk bs=1 count=0 seek=$(($DISK_SIZE)) status=none
		[ $? -ne 0 ] && exit 1;
	fi

	if [ $LOSETUP_LOOP_DEV == true ]; then
		LOOP_DEVICE=$(sudo losetup -f)
		sudo losetup $LOOP_DEVICE $disk
		[ $? -ne 0 ] && exit 1;

		# Change disk name
		disk=$LOOP_DEVICE
		echo -e "\033[0;33m LOOP : $disk\033[0m"
	fi

	# make partition table type (gpt/msdos)
	if [[ -n $DISK_PART_TYPE ]]; then
		sudo parted $disk --script -- unit s mklabel $DISK_PART_TYPE
	fi

	if [ $? -ne 0 ]; then
		[[ -n $LOOP_DEVICE ]] && sudo losetup -d $LOOP_DEVICE
	 	exit 1;
	fi

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

		printf " PART :"
		[ ! -z "$seek" ] && printf "%6d MB:" $(($seek / $SZ_MB));
		[ ! -z "$size" ] && printf "%6d MB:" $(($size / $SZ_MB))
		[ ! -z "$file" ] && printf " %s " `readlink -e -n $file`

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
	[ ${#DISK_PART_IMAGE[@]} -ne 0 ] &&
	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"

	for i in ${DISK_DATA_IMAGE[@]}
	do
		seek=$(echo $i| cut -d':' -f 3)
		size=$(echo $i| cut -d':' -f 4)
		file=$(echo $i| cut -d':' -f 5)

		printf " DATA :"
		[ ! -z "$seek" ] && printf "%6d KB:" $(($seek / $SZ_KB));
		[ ! -z "$size" ] && printf "%6d KB:" $(($size / $SZ_KB))
		[ ! -z "$file" ] && printf " %s\n" `readlink -e -n $file`

		dd_push_image "$disk" "$seek" "$size" "$file" "conv=notrunc"
	done

	[ ${#DISK_DATA_IMAGE[@]} -ne 0 ] &&
	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"

	[[ -n $LOOP_DEVICE ]] && sudo losetup -d $LOOP_DEVICE

	echo -e "\033[0;33m RET : `readlink -e -n $image`\033[0m"
	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
	if [[ -z "$(echo $disk | grep '/dev/sd')" ]]; then
		echo -e "\033[0;33m $> sudo dd if=`readlink -e -n $image` of=/dev/sd? bs=1M\033[0m"
		echo -e "\033[0;33m $> sync\033[0m"
		echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
	fi

	sync
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
		for i in "${!DISK_PARTITION[@]}"; do
			if [[ $i == $type ]]; then
				part=${DISK_PARTITION[$i]};
				break;
			fi
		done

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
			-n )	DISK_IMAGE_NAME=$4; ((options+=2)); shift 2;;
			-u )	DISK_UPDATE_DEV=$4; ((options+=2));
				if [[ ! -e $DISK_UPDATE_DEV ]]; then
					echo -e "\033[47;31m No such file or disk : $DISK_UPDATE_DEV \033[0m"
					exit 1;
				fi
				for i in ${DISK_CHECK_SYSTEM[@]}
				do
					if [[ ! -z "$(echo $DISK_UPDATE_DEV | grep "$i" -m ${#DISK_UPDATE_DEV})" ]]; then
						echo -ne "\033[47;31m Can be 'SYSTEM' region: $DISK_UPDATE_DEV, continue y/n ?> \033[0m"
						read input
						if [ $input != 'y' ]; then
							exit 1
						fi
					fi
				done
				shift 2;;
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
