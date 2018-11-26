#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>

BASEDIR="$(cd "$(dirname "$0")" && pwd)"

PARTMAP_FILE=
PARTMAP_IMAGE_DIR="$BASEDIR/../../result"
PARTMAP_CONTEXT=()
PARTMAP_TARGETS=()

function usage () {
	echo "usage: `basename $0` -f [partmap file] <targets> <options>"
	echo ""
	echo "Partmap struct"
	echo -e "\t\"fash=<device>,<device number>:<target name>:<device area>:<start address:hex>,<size:hex>:<download image>\""
	echo -e "\t<device>      : support 'mmc'"
	echo -e "\t<device area> : support for 'mmc': 'bootsector', 'raw', 'partition'"
	echo ""
	echo "Fastboot command"
	echo -e "\t1. sudo fastboot flash partmap <partmap.txt>"
	echo -e "\t2. sudo fastboot flash <target> <image>"
	echo ""
	echo "[options]"
	echo "  -d : download image path for fastboot, default: `readlink -e -n $PARTMAP_IMAGE_DIR`"
	echo "  -i : partmap info"
	echo "  -l : listup target in partmap list"
	echo "  -r : send reboot command after end of fastboot"
	echo ""
}

function parse_targets () {
	local value=$1	# $1 = store the value
	local params=("${@}")
	local images=("${params[@]:1}")	 # $3 = search array

	for i in "${images[@]}"
	do
		local val="$(echo $i| cut -d':' -f 2)"
		eval "${value}+=(\"${val}\")"
	done
}

function update_fastboot () {
	partmap_images=()

	for i in "${PARTMAP_TARGETS[@]}"
	do
		image=""
		for n in "${PARTMAP_CONTEXT[@]}"
		do
			local v="$(echo $n| cut -d':' -f 2)"
			if [ "$i" == "$v" ]; then
				image="$(echo $(echo $n| cut -d':' -f 5)| cut -d';' -f 1)"
				[ -z "$image" ] && continue;
				image="$PARTMAP_IMAGE_DIR/$image"
				break;
			fi
		done

		[ -z "$image" ] && continue;

		if [ ! -f "$image" ]; then
			echo -e "\033[47;31m Not found '$i': $image\033[0m"
			continue
		fi
		partmap_images+=("$i:`readlink -e -n "$image"`");
	done

	echo -e "\033[0;33m Partmap: $PARTMAP_FILE\033[0m"
	sudo fastboot flash partmap $PARTMAP_FILE
	[ $? -ne 0 ] && exit 1;

	for i in ${partmap_images[@]}
	do
		target=$(echo $i| cut -d':' -f 1)
		image=$(echo $i| cut -d':' -f 2)

		echo -e "\033[0;33m $target:\t$image\033[0m"
		sudo fastboot flash $target $image
		[ $? -ne 0 ] && exit 1;
	done
}

send_reboot=false

case "$1" in
	-f )
		PARTMAP_FILE=$2
		partmap_lists=()
		args=$# options=0 counts=0

		if [ ! -f $PARTMAP_FILE ]; then
			echo -e "\033[47;31m No such to partmap: $PARTMAP_FILE \033[0m"
			exit 1;
		fi

		while read line;
		do
			if [[ "$line" == *"#"* ]];then
				continue
			fi

			PARTMAP_CONTEXT+=($line)
		done < $PARTMAP_FILE

		parse_targets partmap_lists "${PARTMAP_CONTEXT[@]}"

		while [ "$#" -gt 2 ]; do
			# argc
			for i in "${partmap_lists[@]}"
			do
				if [ "$i" == "$3" ]; then
					PARTMAP_TARGETS+=("$i");
					((counts+=1))
					shift 1
					break
				fi
			done

			case "$3" in
			-d )	PARTMAP_IMAGE_DIR=$4; ((options+=2)); shift 2;;
			-r ) 	send_reboot=true; ((options+=1)); shift 1;;
			-l )
				echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
				echo -en " Partmap targets: "
				for i in "${partmap_lists[@]}"
				do
					echo -n "$i "
				done
				echo -e "\n\033[0;33m------------------------------------------------------------------ \033[0m"
				exit 0;;
			-i )
				echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
				for i in "${PARTMAP_CONTEXT[@]}"
				do
					echo "$i"
				done
				echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
				exit 0;;
			-e )
				vim $PARTMAP_FILE
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
		num=${#PARTMAP_TARGETS[@]}
		num=$((args-num-options))

		if [ $num -ne 0 ]; then
			echo -e "\033[47;31m Unknown target: $PARTMAP_FILE\033[0m"
			echo -en " Check targets: "
			for i in "${partmap_lists[@]}"
			do
				echo -n "$i "
			done
			echo ""
			exit 1
		fi

		if [ ${#PARTMAP_TARGETS[@]} -eq 0 ]; then
			PARTMAP_TARGETS=(${partmap_lists[@]})
		fi

		update_fastboot
		;;
	-r )
		send_reboot=true; shift 1;;
	-h | * )
		usage;
		exit 1;;
esac

if [ $send_reboot == true ]; then
	echo -e "\033[47;30m send reboot command...\033[0m"
	sudo fastboot reboot
fi
