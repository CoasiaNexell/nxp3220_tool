#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>

BASEDIR=$(cd "$(dirname "$0")" && pwd)
USBDOWNLOADER=linux-usbdownloader
DOWNLOADER_TOOL=$BASEDIR/../bin/$USBDOWNLOADER
RESULTDIR=`realpath "./"`
DN_TARGET=
USB_WAIT_TIME=	# sec

declare -A TARGET_PRODUCT_ID=(
	["3220"]="nxp3220"	# VID 0x2375 : Digit
	["3225"]="nxp3225"	# VID 0x2375 : Digit
	["1234"]="artik310"	# VID 0x04e8 : Samsung
)

function usage() {
	echo "usage: `basename $0` [-f file name][-l file file][-s] "
	echo ""
	echo "  -t : set target name, target name overwrite configs 'TARGET' field"
	echo "     : support target [nxp3220,artik310]"
	echo "       EX> `basename $0` -t <target> -l <path>/file1 <path>/file2"
	echo ""
	echo "  -f : download with file config"
	echo "       EX> `basename $0` -f <file name>"
	echo ""
	echo "  -l : set file name to download files with target option(-t)"
	echo "       EX> `basename $0` -t <target> -l <path>/file1 <path>/file2"
	echo ""
	echo "  -s : wait sec for next download"
	echo "  -w : wait sec for usb connect"
	echo "  -i : usb down info with -f file name"
	echo "  -e : open file with vim"
	echo "  -p : encryted file transfer"
	echo "  -d : download image path, default:'$RESULTDIR'"
	echo ""
}

function get_prefix_element() {
	local value=$1			# $1 = store the prefix's value
	local params=("${@}")
	local prefix=("${params[1]}")	# $2 = search prefix in $2
	local images=("${params[@]:2}")	# $3 = search array
	local find=false

	for i in "${images[@]}"
	do
		if [[ "$i" = *"$prefix"* ]]; then
			local comp="$(echo $i| cut -d':' -f 2)"
			comp="$(echo $comp| cut -d',' -f 1)"
			comp="$(echo -e "${comp}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
			eval "$value=(\"${comp}\")"
			break
		fi
	done
}

function get_usb_target() {
	local value=$1			# $1 = store the prefix's value
	local counter=0

	if [[ -n $USB_WAIT_TIME ]]; then
		echo -e "\033[47;31m Wait $USB_WAIT_TIME sec connect\033[0m";
	fi

	while true; do
		for i in "${!TARGET_PRODUCT_ID[@]}"
		do
			local id="$(lsusb | grep $i | cut -d ':' -f 3 | cut -d ' ' -f 1)"
			if [ "$i" == "$id" ]; then
				id=${TARGET_PRODUCT_ID[$i]}
				eval "$value=(\"${id}\")"
				return
			fi
		done

		if [[ -n $USB_WAIT_TIME ]]; then
			counter=$((counter+1))
			sleep 1
		fi

		if [[ "$counter" -ge "$USB_WAIT_TIME" ]]; then
			echo -e "\033[47;31m Not found usb device !!!\033[0m";
			exit 1
		fi
	done

	echo -e "\033[47;31m Not suport $id !!!\033[0m"
	echo -e "[${!TARGET_PRODUCT_ID[@]}]"
	exit 1;
}

function usb_download_array() {
	local target=""
	local images=("${@}")	# IMAGES

	get_prefix_element target "TARGET" "${images[@]}"

	if [ -z "$DN_TARGET" ]; then
		get_usb_target target
		DN_TARGET=$target # set DN_TARGET with config file
	else
		target=$DN_TARGET # overwrite target with input target parameter with '-t'
	fi

	echo "##################################################################"
	echo -e "\033[47;34m CONFIG TARGET: $target \033[0m"
	echo "##################################################################"
	echo ""

	for i in "${images[@]}"
	do
		# skip
		if [[ "$i" = *"TARGET"* ]]; then
			continue
		fi

		# skip
		if [[ "$i" = *"BOARD"* ]]; then
			continue
		fi

		if [ $SHOW_INFO == true ]; then
			continue
		fi

		local cmd="$(echo $i| cut -d':' -f 2)"
		local file="$(echo $cmd | cut -d' ' -f 2)"

		# reset load command with current file path
		if [ ! -e "$file" ]; then
			file=$(basename $file)
			if [ ! -e "$file" ]; then
				echo -e "\033[47;31m DOWNLOAD: No such file $file\033[0m"
				exit 1
			fi
			local opt="$(echo $cmd | cut -d' ' -f 1)"
			file=./$file
			cmd="$opt $file"
		fi

		if [ ! -f $DOWNLOADER_TOOL ]; then
			DOWNLOADER_TOOL=./$USBDOWNLOADER
		fi

		echo -e "\033[47;34m DOWNLOAD: $cmd \033[0m"
		sudo $DOWNLOADER_TOOL -t $target $cmd
		echo -e "\033[47;32m DOWNLOAD: DONE \033[0m"

		[ $? -ne 0 ] && exit 1;

		sleep $DN_SLEEP_SEC	# wait for next connect
	done
}

# input parameters
# $1 = download file array
function usb_download_files() {
	local files=("${@}")	# IMAGES
	local target=$DN_TARGET

	if [ -z "$DN_TARGET" ]; then
		get_usb_target target
	fi

	echo "##################################################################"
	echo -e "\033[47;34m LOAD TARGET: $target \033[0m"
	echo "##################################################################"
	echo ""

	for i in "${files[@]}"
	do
		if [ ! -f $i ]; then
			echo -e "\033[47;31m No such file: $i... \033[0m"
			exit 1;
		fi

		if [ -z "$target" ]; then
			echo -e "\033[47;31m No Target... \033[0m"
			usage
			exit 1;
		fi

		echo -e "\033[47;34m DOWNLOAD: $i \033[0m"

		if [ ! -f $DOWNLOADER_TOOL ]; then
			DOWNLOADER_TOOL=./$USBDOWNLOADER
		fi

		sudo $DOWNLOADER_TOOL -t $target -f $i

		echo -e "\033[47;32m DOWNLOAD: DONE \033[0m"

		[ $? -ne 0 ] && exit 1;

		sleep $DN_SLEEP_SEC
	done
}

DN_LOAD_OBJS=()
DN_LOAD_FILE=
EDIT_FILE=false
SHOW_INFO=false
DN_ENCRYPTED=false
DN_SLEEP_SEC=2

while getopts 'hf:l:t:s:d:w:eip' opt
do
        case $opt in
        f )
		DN_LOAD_FILE=$OPTARG
		;;
        t )
		DN_TARGET=$OPTARG
		;;
        l )
		DN_LOAD_OBJS=("$OPTARG")
		until [[ $(eval "echo \${$OPTIND}") =~ ^-.* ]] || [ -z $(eval "echo \${$OPTIND}") ]; do
			DN_LOAD_OBJS+=($(eval "echo \${$OPTIND}"))
                	OPTIND=$((OPTIND + 1))
		done
		;;
	i )
		SHOW_INFO=true
		;;
	e )
		EDIT_FILE=true
		;;
	p )
		DN_ENCRYPTED=true
		;;
	s )
		DN_SLEEP_SEC=$OPTARG
		;;
	w )
		USB_WAIT_TIME=$OPTARG
		;;
	d )
		RESULTDIR=`realpath $OPTARG`
		;;
        h | *)
        	usage
		exit 1;;
		esac
done

if [ $EDIT_FILE == true ]; then
	if [ ! -f $DN_LOAD_FILE ]; then
		echo -e "\033 No such file: $DN_LOAD_FILE \033[0m"
		exit 1
	fi

	vim $DN_LOAD_FILE
	exit 0
fi

if [ ! -z $DN_LOAD_FILE ]; then
	if [ ! -f $DN_LOAD_FILE ]; then
		echo -e "\033 No such file: $DN_LOAD_FILE \033[0m"
		exit 1
	fi

	# include input file
	source $DN_LOAD_FILE

	if [ $DN_ENCRYPTED == false ]; then
		usb_download_array "${DN_IMAGES[@]}"
	else
		usb_download_array "${DN_ENC_IMAGES[@]}"
	fi
fi

if [ ${#DN_LOAD_OBJS} -ne 0 ]; then
	usb_download_files "${DN_LOAD_OBJS[@]}"
fi
