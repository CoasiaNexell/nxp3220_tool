#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
RESULTDIR=`readlink -f "./"`

DISK_IMAGE_NAME="disk.img"
DISK_UPDATE_DEV=""
DISK_UPDATE_PART=false

SIMG2DEV=simg2dev
ANDROID_IMAGE_WRITER=$BASEDIR/../bin/$SIMG2DEV

declare -A DISK_PARTITION=(
	["partition"]="gpt"
	["gpt"]="gpt"
	["dos"]="msdos"
	["mbr"]="msdos"
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
DISK_MARGIN=$((500 * $SZ_MB))
DISK_SIZE=$((8 * $SZ_GB))

LOOP_DEVICE=
LOSETUP_LOOP_DEV=false
_SPACE_='            '

function usage () {
	echo "usage: `basename $0` -f [partmap file] <target ...> <options>"
	echo ""
	echo "[OPTIONS]"
	echo "  -d : path for the target images, default: '$RESULTDIR'"
	echo "  -i : partmap info"
	echo "  -l : listup <target ...>  in partmap list"
	echo "  -s : disk size: n GB (default $(($DISK_SIZE / $SZ_GB)) GB)"
	echo "  -r : disk margin size: n MB (default $(($DISK_MARGIN / $SZ_MB)) MB)"
	echo "  -u : update to device with <target> image, ex> -u /dev/sd? boot"
	echo "  -n : new disk image name (default $DISK_IMAGE_NAME)"
	echo "  -p : updates the partition table also. this option is valid when '-u'"
	echo "  -t : run losetup(loop device) to mount the disk image"
	echo ""
	echo "Partmap struct:"
	echo "  fash=<>,<>:<>:<partition>:<start:hex>,<size:hex>"
	echo "  part   : gpt/dos(mbr) else ..."
	echo ""
	echo "DISK update:"
	echo "  $> sudo dd if=<path>/<image> of=/dev/sd? bs=1M"
	echo "  $> sync"
	echo ""
	echo "DISK mount: with '-t' option for test"
	echo "  $> sudo losetup -f"
	echo "  $> sudo losetup /dev/loopN <image>"
	echo "  $> sudo mount /dev/loopNpn <directory>"
	echo "  $> sudo losetup -d /dev/loopN"
	echo ""
	echo "Required packages:"
	echo "  parted"
}

function convert_byte_to_hn () {
	local val=$1 ret=$2

	if [[ $((val)) -ge $((SZ_GB)) ]]; then
		val="$((val/$SZ_GB))G";
	elif [[ $((val)) -ge $((SZ_MB)) ]]; then
		val="$((val/$SZ_MB))M";
	elif [[ $((val)) -ge $((SZ_KB)) ]]; then
		val="$((val/$SZ_KB))K";
	else
		val="$((val))B";
	fi
	eval "$ret=\"${val}\""
}

function make_partition () {
	local disk=$1 start=$2 size=$3
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

function dd_write () {
	local disk=$1 start=$2 size=$3 file=$4 option=$5

	[[ -z $file ]] || [[ ! -f $file ]] && return;

	sudo dd if=$file of=$disk seek=$(($start / $BLOCK_UNIT)) bs=$BLOCK_UNIT $option status=none;
	if [ $? -ne 0 ]; then
		[[ -n $LOOP_DEVICE ]] && sudo losetup -d $LOOP_DEVICE
	 	exit 1;
	fi
}

function disk_partition () {
	[[ -n $DISK_UPDATE_DEV ]] && [[ $DISK_UPDATE_PART == false ]] && return

	# make partition table type (gpt/msdos)
	if [[ -n $DISK_PART_TYPE ]]; then
		sudo parted $disk --script -- unit s mklabel $DISK_PART_TYPE
	fi

	if [ $? -ne 0 ]; then
		[[ -n $LOOP_DEVICE ]] && sudo losetup -d $LOOP_DEVICE
		exit 1;
	fi

	local n=1
	for i in ${DISK_PART_IMAGE[@]}
	do
		part=$(echo $i| cut -d':' -f 1)
		seek=$(echo $i| cut -d':' -f 3)
		size=$(echo $i| cut -d':' -f 4)

		printf " %s.$n:" $DISK_PART_TYPE | tr 'a-z' 'A-Z'
		[[ ! -z $seek ]] && printf "%s0x%x:" "${_SPACE_:${#seek}}" $seek;
		[[ ! -z $size ]] && printf "%s0x%x:" "${_SPACE_:${#size}}" $size;
		[[ ! -z $part ]] && printf " %s\n" $part

		make_partition "$disk" "$seek" "$size"
		((n++))
	done
}

function disk_write () {
	local index=$1
	local -n __array__=$2

	for i in ${__array__[@]}
	do
		seek=$(echo $i| cut -d':' -f 3)
		size=$(echo $i| cut -d':' -f 4)
		file=$(echo $i| cut -d':' -f 5)

		[[ -z $file ]] || [[ ! -f $file ]] && continue;

		printf "$index"
		[[ ! -z $seek ]] && printf "%s0x%x:" "${_SPACE_:${#seek}}" $seek;
		[[ ! -z $size ]] && printf "%s0x%x:" "${_SPACE_:${#size}}" $size;
		[[ ! -z $file ]] && printf " %s\n" `readlink -e -n $file`

		if [[ ! -z "$(file $file | grep 'Android sparse')" ]]; then
			if [ ! -f $ANDROID_IMAGE_WRITER ]; then
				ANDROID_IMAGE_WRITER=./$SIMG2DEV
			fi
			sudo $ANDROID_IMAGE_WRITER "$file" "$disk" "$seek" > /dev/null
			[ $? -ne 0 ] && exit 1;
		else
			dd_write "$disk" "$seek" "$size" "$file" "conv=notrunc"
		fi
	done
}

function create_disk_image () {
	local disk="$RESULTDIR/$DISK_IMAGE_NAME"
	local image=$disk

	if [[ -n $DISK_UPDATE_DEV ]]; then
		disk=$DISK_UPDATE_DEV
		image=$disk
		LOSETUP_LOOP_DEV=false # not support
	fi

	if [[ ! -n $DISK_UPDATE_DEV ]]; then
		echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
		echo -e "\033[1;34m Creat disk image ...\033[0m"
		echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
		echo -e "\033[0;33m DISK : $(basename $disk)\033[0m"
		echo -e "\033[0;33m SIZE : $(($DISK_SIZE / $SZ_MB)) MB - Margin $(($DISK_MARGIN / $SZ_MB)) MB\033[0m"
		echo -e "\033[0;33m PART : $(echo $DISK_PART_TYPE | tr 'a-z' 'A-Z')\033[0m"
		echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
	else
		echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
		echo -e "\033[1;34m Update disk images ...\033[0m"
		echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
		echo -e "\033[0;33m DISK : $disk\033[0m"
		echo -ne "\033[0;33m IMG  : \033[0m"
		for i in ${DISK_TARGET_NAME[@]}
		do
			echo -ne "\033[0;33m$i \033[0m"
		done
		echo -e "\033[0;33m \033[0m"
		echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
	fi

	# create disk image
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
		echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
	fi

	disk_partition
	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"

	disk_write " PART :" DISK_PART_IMAGE
	[ ${#DISK_PART_IMAGE[@]} -ne 0 ] &&
	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"

	disk_write " DATA :" DISK_DATA_IMAGE
	[ ${#DISK_DATA_IMAGE[@]} -ne 0 ] &&
	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"

	[[ -n $LOOP_DEVICE ]] && sudo losetup -d $LOOP_DEVICE

	echo -e "\033[0;33m RET : `readlink -e -n $image`\033[0m"
	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
	if [[ -z "$(echo $disk | grep '/dev/sd')" ]]; then
		echo -e "\033[0;33m $> sudo dd if=`readlink -e -n $image` of=/dev/sd? bs=1M\033[0m"
		echo -e "\033[0;33m $> sync\033[0m"
		if [ $LOSETUP_LOOP_DEV == true ]; then
			echo -e "\033[0;33m sudo losetup -f\033[0m"
			echo -e "\033[0;33m sudo losetup ${LOOP_DEVICE} ${DISK_IMAGE_NAME}\033[0m"
			echo -e "\033[0;33m sudo mount ${LOOP_DEVICE}pn <directory>\033[0m"
			echo -e "\033[0;33m sudo losetup -d ${LOOP_DEVICE}\033[0m"
		fi
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

		# get partition type: gpt/dos
		local part=
		for i in "${!DISK_PARTITION[@]}"; do
			if [[ $i == $type ]]; then
				part=${DISK_PARTITION[$i]};
				break;
			fi
		done

		[ $(($seek)) -gt $(($offset)) ] && offset=$(($seek));
		[ $(($size)) -eq 0 ] && size=$(printf "0x%x" $(($DISK_SIZE - $DISK_MARGIN - $offset)));

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
	local -n __array__=$2

	for i in "${__array__[@]}"
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
			line="$(echo "$line" | sed 's/[[:space:]]//g')"
			if [[ "$line" == *"#"* ]];then
				continue
			fi
			DISK_TARGET_CONTEXT+=($line)
		done < $mapfile

		parse_target maplist DISK_TARGET_CONTEXT

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
			-d )	RESULTDIR=`readlink -f $4`; ((options+=2)); shift 2;;
			-s )	DISK_SIZE=$(($4 * $SZ_GB)); ((options+=2)); shift 2;;
			-r )	DISK_MARGIN=$(($4 * $SZ_MB)); ((options+=2)); shift 2;;
			-n )	DISK_IMAGE_NAME=$4; ((options+=2)); shift 2;;
			-u )	DISK_UPDATE_DEV=$4; ((options+=2));
				if [[ ! -e $DISK_UPDATE_DEV ]]; then
					echo -e "\033[47;31m No such file or disk : $DISK_UPDATE_DEV \033[0m"
					exit 1;
				fi

				for i in ${DISK_CHECK_SYSTEM[@]}
				do
					if [[ ! -z "$(echo $DISK_UPDATE_DEV | grep "$i" -m ${#DISK_UPDATE_DEV})" ]]; then
						echo -ne "\033[47;31m Can be 'system' region: $DISK_UPDATE_DEV, continue y/n ?> \033[0m"
						read input
						if [ $input != 'y' ]; then
							exit 1
						fi
						echo -ne "\033[47;31m Check again: $DISK_UPDATE_DEV, continue y/n ?> \033[0m"
						read input
						if [ $input != 'y' ]; then
							exit 1
						fi
					fi
				done
				shift 2;;
			-p )
				DISK_UPDATE_PART=true;((options+=1));
				shift 1;;
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
					size=$(echo "$(echo "$i" | cut -d':' -f4)" | cut -d',' -f2)
					convert_byte_to_hn $size size
					printf "[%s]\t %s\n" $size $i
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
		num=$((args - num - options))

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
