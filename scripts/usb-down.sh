#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>

BASEDIR=$(cd "$(dirname "$0")" && pwd)
DOWNLOADER=$BASEDIR/../bin/linux-usbdownloader
DN_TARGET=

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
	echo "  -i : build info with -f file name"
	echo "  -e : open file with vim"
	echo "  -p : encryted file transfer"
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

function usb_download_array() {
	local target=""
	local images=("${@}")	# IMAGES

	get_prefix_element target "TARGET" "${images[@]}"

	if [ -z "$DN_TARGET" ]; then
 		if [ -z "$target" ]; then
			echo -e "\033[47;31m Not find TARGET !!!\033[0m"
			echo -e "[${images[@]}]"
			return
		fi
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

		echo -e "\033[47;34m DOWNLOAD: $i \033[0m"
		if [ $show_info == true ]; then
			continue
		fi

		local cmd="$(echo $i| cut -d':' -f 2)"
		local file="$(echo $cmd| cut -d' ' -f 2)"

		if [ ! -e "$file" ]; then
			echo -e "\033[47;31m DOWNLOAD: No such file $file\033[0m"
			exit 1
		fi

		sudo $DOWNLOADER -t $target $cmd
		echo -e "\033[47;32m DOWNLOAD: DONE \033[0m"

		[ $? -ne 0 ] && exit 1;

		sleep $sleep_sec	# wait for next connect
	done
}

# input parameters
# $1 = download file array
function usb_download_files() {
	local files=("${@}")	# IMAGES
	local target=$DN_TARGET

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

		sudo $DOWNLOADER -t $target -f $i

		echo -e "\033[47;32m DOWNLOAD: DONE \033[0m"

		[ $? -ne 0 ] && exit 1;

		sleep $sleep_sec
	done
}

dn_load_objs=()
dn_load_file=
edit_file=false
show_info=false
encryted=false
sleep_sec=2

while getopts 'hf:l:t:s:eip' opt
do
        case $opt in
        f )
 		dn_load_file=$OPTARG
		;;
        t )
		DN_TARGET=$OPTARG
		;;
        l )
		dn_load_objs=("$OPTARG")
		until [[ $(eval "echo \${$OPTIND}") =~ ^-.* ]] || [ -z $(eval "echo \${$OPTIND}") ]; do
        	        dn_load_objs+=($(eval "echo \${$OPTIND}"))
                	OPTIND=$((OPTIND + 1))
		done
		;;
	i )
		show_info=true
		;;
	e )
		edit_file=true
		;;
	p )
		encryted=true
		;;
	s )
		sleep_sec=$OPTARG
		;;
        h | *)
        	usage
		exit 1;;
		esac
done

if [ $edit_file == true ]; then
	if [ ! -f $dn_load_file ]; then
		echo "No such file $argc"
		exit 1
	fi

	vim $dn_load_file
	exit 0
fi

if [ ! -z $dn_load_file ]; then
	if [ ! -f $dn_load_file ]; then
		echo "No such file $argc"
		exit 1
	fi

	# include input file
	. $dn_load_file

	if [ $encryted == false ]; then
		usb_download_array "${DN_IMAGES[@]}"
	else
		usb_download_array "${DN_ENC_IMAGES[@]}"
	fi
fi

if [ ${#dn_load_objs} -ne 0 ]; then
	usb_download_files "${dn_load_objs[@]}"
fi
