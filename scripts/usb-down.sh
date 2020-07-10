#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>

BASEDIR=$(cd "$(dirname "$0")" && pwd)
USBDOWNLOADER=linux-usbdownloader
DOWNLOADER_TOOL="$BASEDIR/../bin/$USBDOWNLOADER"
RESULTDIR=$(realpath "./")
DN_DEVICE=
USB_WAIT_TIME=	# sec

declare -A TARGET_PRODUCT_ID=(
	["3220"]="nxp3220"	# VID 0x2375 : Digit
	["3225"]="nxp3225"	# VID 0x2375 : Digit
	["1234"]="artik310"	# VID 0x04e8 : Samsung
)

function err () { echo -e "\033[0;31m$*\033[0m"; }
function msg () { echo -e "\033[0;33m$*\033[0m"; }

function usage () {
	echo "usage: $(basename "$0") [-f config] [options] "
	echo ""
	echo " options:"
	echo -e "\t-f\t download config file"
	echo -e "\t-l\t download files"
	echo -e "\t\t EX> $(basename "$0") -f <config> -l <path>/file1 <path>/file2"
	echo -e "\t-s\t wait sec for next download"
	echo -e "\t-w\t wait sec for usb connect"
	echo -e "\t-e\t open download config file"
	echo -e "\t-p\t encryted file transfer"
	echo -e "\t-d\t download image path, default:'$RESULTDIR'"
	echo -e "\t-t\t set usb device name, this name overwrite configs 'TARGET' field"
	echo -e "\t\t support device [nxp3220,nxp3225,artik310]"
	echo -e ""
}

function get_prefix_element () {
	local value=$1			# $1 = store the prefix's value
	local params=("${@}")
	local prefix=("${params[1]}")	# $2 = search prefix in $2
	local images=("${params[@]:2}")	# $3 = search array

	for i in "${images[@]}"; do
		if [[ "$i" = *"$prefix"* ]]; then
			local comp="$(echo "$i" | cut -d':' -f 2)"
			comp="$(echo "$comp" | cut -d',' -f 1)"
			comp="$(echo -e "${comp}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
			eval "$value=(\"${comp}\")"
			break
		fi
	done
}

function get_usb_device () {
	local value=$1			# $1 = store the prefix's value
	local counter=0

	if [[ -n $USB_WAIT_TIME ]]; then
		msg " Wait $USB_WAIT_TIME sec connect";
	fi

	while true; do
		for i in "${!TARGET_PRODUCT_ID[@]}"; do
			local id="$(lsusb | grep "$i" | cut -d ':' -f 3 | cut -d ' ' -f 1)"
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
			err " Not found usb device !!!";
			exit 1
		fi
	done

	err " Not suport $id !!!"
	err "${!TARGET_PRODUCT_ID[@]}"
	exit 1;
}

function usb_download_config () {
	local device=""
	local images=("${@}")	# IMAGES

	get_prefix_element device "TARGET" "${images[@]}"

	if [ -z "$DN_DEVICE" ]; then
		get_usb_device device
		DN_DEVICE=$device # set DN_DEVICE with config file
	else
		device=$DN_DEVICE # overwrite device with input device parameter with '-t'
	fi

	msg "##################################################################"
	msg " CONFIG DEVICE: $device"
	msg "##################################################################"
	msg ""

	for i in "${images[@]}"; do
		local cmd file
		[[ "$i" = *"TARGET"* ]] && continue;
		[[ "$i" = *"BOARD"* ]] && continue;

		cmd=$(echo "$i" | cut -d':' -f 2)
		cmd="$(echo "$cmd" | tr '\n' ' ')"
		cmd="$(echo "$cmd" | sed 's/^[ \t]*//;s/[ \t]*$//')"
		file=$(echo "$cmd" | cut -d' ' -f 2)

		# reset load command with current file path
		if [[ ! -e $file ]]; then
			file=$(basename "$file")
			if [[ ! -e $file ]]; then
				err " DOWNLOAD: No such file $file"
				exit 1
			fi
			local opt="$(echo "$cmd" | cut -d' ' -f 1)"
			file=./$file
			cmd="$opt $file"
		fi

		msg " DOWNLOAD: $cmd"
		if ! sudo "$DOWNLOADER_TOOL" -t "$device" $cmd; then
			exit 1;
		fi
		msg " DOWNLOAD: DONE\n"

		sleep "$DN_SLEEP_SEC"	# wait for next connect
	done
}

# input parameters
# $1 = download file array
function usb_download_targets () {
	local files=("${@}")	# IMAGES
	local device=$DN_DEVICE

	if [[ -z $DN_DEVICE ]]; then
		get_usb_device device
	fi

	msg "##################################################################"
	msg " LOAD DEVICE: $device"
	msg "##################################################################"
	msg ""

	for i in "${files[@]}"; do
		i=$(realpath "$RESULTDIR/$i")
		if [[ ! -f $i ]]; then
			err " No such file: $i..."
			exit 1;
		fi

		if [[ -z $device ]]; then
			err " No Device ..."
			usage
			exit 1;
		fi

		msg " DOWNLOAD: $i"
		if ! sudo "$DOWNLOADER_TOOL" -t "$device" -f "$i"; then
			exit 1;
		fi
		msg " DOWNLOAD: DONE\n"

		sleep "$DN_SLEEP_SEC"
	done
}

DN_LOAD_TARGETS=()
DN_LOAD_CONFIG=
EDIT_FILE=false
DN_ENCRYPTED=false
DN_SLEEP_SEC=2

while getopts 'hf:l:t:s:d:w:ep' opt
do
        case $opt in
        f )	DN_LOAD_CONFIG=$OPTARG;;
        t )	DN_DEVICE=$OPTARG;;
        l )	DN_LOAD_TARGETS=("$OPTARG")
		until [[ $(eval "echo \${$OPTIND}") =~ ^-.* ]] || [[ -z $(eval "echo \${$OPTIND}") ]]; do
			DN_LOAD_TARGETS+=($(eval "echo \${$OPTIND}"))
                	OPTIND=$((OPTIND + 1))
		done
		;;
	e )	EDIT_FILE=true;;
	p )	DN_ENCRYPTED=true;;
	s )	DN_SLEEP_SEC=$OPTARG;;
	w )	USB_WAIT_TIME=$OPTARG;;
	d )	RESULTDIR=$(realpath "$OPTARG");;
        h | *)
        	usage
		exit 1;;
		esac
done

if [[ $EDIT_FILE == true ]]; then
	if [[ ! -f $DN_LOAD_CONFIG ]]; then
		err " No such file: $DN_LOAD_CONFIG"
		exit 1
	fi

	vim "$DN_LOAD_CONFIG"
	exit 0
fi

if [[ ! -f $DOWNLOADER_TOOL ]]; then
	DOWNLOADER_TOOL="./$USBDOWNLOADER"
fi

if [[ ! -z $DN_LOAD_CONFIG ]]; then
	if [[ ! -f $DN_LOAD_CONFIG ]]; then
		err " No such config: $DN_LOAD_CONFIG"
		exit 1
	fi

	# include input file
	source "$DN_LOAD_CONFIG"

	if [[ $DN_ENCRYPTED == false ]]; then
		usb_download_config "${DN_IMAGES[@]}"
	else
		usb_download_config "${DN_ENC_IMAGES[@]}"
	fi
fi

if [[ ${#DN_LOAD_TARGETS} -ne 0 ]]; then
	usb_download_targets "${DN_LOAD_TARGETS[@]}"
fi
