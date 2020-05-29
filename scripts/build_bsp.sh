#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>
#
# BUILD_IMAGES=(
# 	"MACHINE= <name>",
# 	"ARCH  	= arm",
# 	"TOOL	= <path>/arm-none-gnueabihf-",
# 	"RESULT = <result dir>",
# 	"kernel	=
# 		PATH  : <kernel path>,
# 		CONFIG: <kernel defconfig>,
# 		IMAGE : <build image>,
# 		OUTPUT: <output file>",
#		....
#

eval $(locale | sed -e 's/\(.*\)=.*/export \1=en_US.UTF-8/')

declare -A BUILD_ENVIRONMENT=(
	["ARCH"]=" "
  	["MACHINE"]=" "
  	["TOOL"]=" "
  	["RESULT"]=" "
)

declare -A BUILD_ENTRY=(
  	["PATH"]=" "	# build path
	["CONFIG"]=" "	# default condig (defconfig) for make build
	["IMAGE"]=" "	# target image name for make build
	["TOOL"]=" "	# cross compiler for make build
	["OUTPUT"]=" "	# name of make built imag to copy to resultdir, copy after post command
	["OPTION"]=" "	# make option
	["PRECMD"]=" "	# pre command before make build.
	["POSTCMD"]=" "	# post command after make build and copy done.
  	["COPY"]=" "	# copy name to RESULT
  	["JOBS"]=" "	# build jobs number (-j n)
)

BUILD_TARGETS=()
BUILD_LOG_DIR=$(realpath $(dirname `realpath ${0}`))/.build

function err () { echo -e "\033[0;31m$@\033[0m"; }
function msg () { echo -e "\033[0;33m$@\033[0m"; }

function usage() {
	echo "Usage: `basename $0` [-f config] <targets> <command> <options>"
	echo ""
	echo " target:";
	echo -ne "\t";
	for i in "${BUILD_TARGETS[@]}"; do
		echo -n "$i ";
	done
	echo ""	
	echo " options:"
	echo -e "\t-i : show build command info"
	echo -e "\t-l : listup build targets"
	echo -e "\t-j : build jobs"
	echo -e "\t-o : build options"
	echo -e "\t-m : only execute make"
	echo -e "\t-p : only execute pre command, before make (related with PRECMD)"
	echo -e "\t-s : only execute post command, after done (related with POSTCMD)"
	echo -e "\t-c : only execute copy to result (related with COPY)"
	echo -e "\t-e : open config file with vim (with -f 'config')"
	echo -e "\t-v : print build log"
	echo -e "\t-vv: print build log and enable external shell tasks tracing (with 'set -x')"
	echo ""
	echo " command:"
	echo -e "\tdefconfig"
	echo -e "\tmenuconfig"
	echo -e "\tclean"
	echo -e "\tdistclean"
	echo -e "\tcleanbuild"
	echo -e "\trebuild"
	echo -e "\t- else command supported by target"
}

function print_env () {
	msg "=================================================================="
	for key in ${!BUILD_ENVIRONMENT[@]}; do
		[[ -z ${BUILD_ENVIRONMENT[$key]} ]] && continue;
		message=$(printf " %-8s = %s\n" $key ${BUILD_ENVIRONMENT[$key]})
		msg "$message"
	done
	msg "=================================================================="
}

function parse_env_value () {
	local key=$1 ret=$2
	local -n array=$3

	for i in "${array[@]}"; do
		if [[ $i = *"$key"* ]]; then
			local ent="$(echo $i| cut -d'=' -f 2)"
			ent="$(echo $ent| cut -d',' -f 1)"
			ent="$(echo -e "${ent}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
			eval "$ret=(\"${ent}\")"
			break
		fi
	done
}

function parse_build_env () {
	local list=("${@}")	# $1 = search array

	for key in ${!BUILD_ENVIRONMENT[@]}; do
		local val=""
		parse_env_value $key val list
		BUILD_ENVIRONMENT[$key]=$val
	done

	if [[ -n ${BUILD_ENVIRONMENT["RESULT"]} ]]; then
                mkdir -p ${BUILD_ENVIRONMENT["RESULT"]}
		[ $? -ne 0 ] && exit 1;
	fi
}

function setup_build_env () {
	[[ -z $1 ]] && return;

	local path=`realpath $(dirname "$1")`
	if [[ -z $path ]]; then
		err " No such 'TOOL': $(dirname "$1")"
		exit 1
	fi
	export PATH=$path:$PATH
}

function print_target () {
	local target=$1

	msg ""
	msg "------------------------------------------------------------------"
	echo -e "\033[1;31m [$target]\033[0m";
	for key in ${!BUILD_ENTRY[@]}; do
		[[ -z ${BUILD_ENTRY[$key]} ]] && continue;
		if [[ $key == "PATH" ]]; then
			message=$(printf " %-8s = %s\n" $key `realpath ${BUILD_ENTRY[$key]}`)
		else
			message=$(printf " %-8s = %s\n" $key "${BUILD_ENTRY[$key]}")
		fi
		msg "$message"
	done
	msg "------------------------------------------------------------------"
}

function parse_target_value () {
	local str=$1 key=$2
	local ret=$3

	local pos=`awk -v a="$str" -v b="$key" 'BEGIN{print index(a,b)}'`
	[ $pos -eq 0 ] && return;

	local val=${str:$pos}

	pos=`awk -v a="$val" -v b=":" 'BEGIN{print index(a,b)}'`
	val=${val:$pos}
	pos=`awk -v a="$val" -v b="," 'BEGIN{print index(a,b)}'`
	[ $pos -ne 0 ] && val=${val:0:$pos};

	if [ `expr "$val" : ".*[*].*"` -eq 0 ]; then
		val="$(echo $val| cut -d',' -f 1)"
	else
		val="$(echo "$val"| cut -d',' -f 1)"
	fi

	eval "$ret=(\"${val}\")"
}

function parse_target_ent () {
	local target=$1 ret=$2

	for i in "${BUILD_IMAGES[@]}"; do
		if [[ $i = *"$target"* ]]; then
			local ent="$(echo $(echo $i| cut -d'=' -f 1) | cut -d' ' -f 1)"
			[[ $target != $ent ]] && continue;

			local pos=`expr index "$i" '='`
			[ $pos -eq 0 ] && return;

			ent=${i:$pos}
			eval "$ret=(\"${ent}\")"
			break
		fi
	done
}

function parse_target () {
	local target=$1 entry

	parse_target_ent $target entry

	for key in ${!BUILD_ENTRY[@]}; do
		local value=""

		parse_target_value "$entry" "$key" value
		BUILD_ENTRY[$key]=$value

		if [[ $key == PRECMD ]] || [[ $key == POSTCMD ]] ||
			[[ $key == OPTION ]]; then
			continue
		fi

		# remove space
		local pos=`awk -v a="$value" -v b="[" 'BEGIN{print index(a,b)}'`
		[ $pos -ne 0 ] && continue;

		BUILD_ENTRY[$key]="$(echo "$value" | sed 's/[[:space:]]//g')"
	done
}

function exec_shell () {
	local log=$BUILD_LOG_DIR/${2}.script.log
	local result

	rm -f $log
	msg " $> ${1} "
	[[ $OPT_TRACE == true ]] && set -x;

	if type "${1}" 2>/dev/null | grep -q 'function'; then
		if [ $OPT_VERBOSE == false ]; then
			${1} >> $log 2>&1
		else
			${1}
		fi
	else
		if [ $OPT_VERBOSE == false ]; then
			bash -c "${1}" >> $log 2>&1
		else
			bash -c "${1}"
		fi
	fi

	result=$?
	[[ $OPT_TRACE == true ]] && set +x;
	[ $OPT_VERBOSE == false ] && [ $result -ne 0 ] && err " ERROR: script '${2}':$log\n";

	return $result
}

function exec_make () {
	local log=$BUILD_LOG_DIR/${2}.make.log
	local result

	rm -f $log
	msg " $> make ${1}"

	if [ $OPT_VERBOSE == false ] && [[ ${1} != *menuconfig* ]]; then
		make ${1} >> $log  2>&1
	else
		make ${1}
	fi

	result=$?
	if [ $OPT_VERBOSE == false ] && [ $result -eq 2 ] && [[ ${1} != *"clean"* ]]; then
		err " ERROR: make '${2}':$log\n";
	else
		result=0
	fi

	return $result
}

BUILD_COMMAND_EXCEPTION=(
	"*".dtb"*"
)

function make_target () {
	local target=$1
	local command=$2
	local arch=${BUILD_ENVIRONMENT["ARCH"]}
	local tool=${BUILD_ENTRY["TOOL"]}
	local path=$(realpath ${BUILD_ENTRY["PATH"]})
	local image=${BUILD_ENTRY["IMAGE"]}
	local config=${BUILD_ENTRY["CONFIG"]}
	local option="-j ${BUILD_ENTRY["JOBS"]} ${BUILD_ENTRY["OPTION"]}"

	if [ ! -d $path ]; then
		err " Invalid 'PATH' '$path' for $target ..."
		exit 1;
	fi

	if [[ ! -f $path/makefile ]] && [[ ! -f $path/Makefile ]]; then
		msg " Not found Makefile for $target in '$path' ..."
		return;
	fi

	# make clean
	if [[ $image != *".dtb"* ]]; then
		if [[ $command == distclean ]] || [[ $command == rebuild ]]; then
			exec_make "-C $path distclean" ${target}
			exec_make "-C $path clean" ${target}
		fi

		if [[ $command == clean ]] || [[ $command == cleanbuild ]]; then
			exec_make "-C $path clean" ${target}
		fi

		if  [[ $command == rebuild ]] || [[ $command == cleanbuild ]] &&
		    [[ -n ${BUILD_ENTRY["PRECMD"]} ]]; then
			exec_shell "${BUILD_ENTRY["PRECMD"]}" ${target}
			[ $? -ne 0 ] && exit 1;
		fi
	fi

	# exit clean
	[[ $command == distclean ]] || [[ $command == clean ]] && exit 0;

	# default config : defconfg
	if [[ -n $config ]]; then
		if [[ $command == defconfig ]] || [[ ! -f $path/.config ]]; then
			exec_make "-C $path ARCH=$arch CROSS_COMPILE=$tool $config" ${target}
			[ $? -ne 0 ] && exit 1;
		fi

		if [[ $command == menuconfig ]]; then
			exec_make "-C $path ARCH=$arch CROSS_COMPILE=$tool menuconfig" ${target}
			[ $? -ne 0 ] && exit 1;
		fi
	fi

	# exit config
	[[ $command == defconfig ]] || [[ $command == menuconfig ]] && exit 0;

	if [[ -n $command ]] && [[ $command != rebuild ]] && [[ $command != cleanbuild ]] ; then
		option=""
	else
		command=$image
	fi

	exec_make "-C $path ARCH=$arch CROSS_COMPILE=$tool $command $option" ${target}
}

function copy_result () {
	local out=$2 src=$1/$out
	local dir=$3 dst=$4

	if [ "$(ls $src| wc -l 2>/dev/null)" -eq 0 ]; then
		err " No such to copy : '$src' ..."
		return
	fi

	if [[ $src == "/" ]]; then
		err " Invalid directory : '$src' ..."
		return
	fi

	if [[ -z $out ]]; then
		err " Not declared 'OUTPUT' ..."
		return
	fi

	if [ `expr "$out" : ".*[*].*"` -eq 0 ]; then
		if [[ -z $dst ]]; then
			dst=$dir/$(basename $out)
		else
			dst=$dir/$dst
		fi
	else
		if [[ -n $dst ]]; then
			dst=$dir/$dst
		else
			dst=$dir/
		fi
	fi

	msg "------------------------------------------------------------------"
	message=$(printf " %-8s = %s\n" "RESULT" `realpath $src`)
	msg "$message"
	message=$(printf " %-8s = %s\n" "COPY" `realpath $dst`)
	msg "$message"
	msg "------------------------------------------------------------------"

	mkdir -p $dir
	[ ! -d $dir ] && return;
	[ -d $src ] && rm -rf $dst;

	local pos=`awk -v a="$src" -v b="[" 'BEGIN{print index(a,b)}'`
	if [ $pos -eq 0 ]; then
		cp -a $src $dst
	fi
}

function run_build () {
	local target=$1 command=$2

	parse_target $target
	print_target $target

	[[ -z ${BUILD_ENTRY["TOOL"]} ]] && BUILD_ENTRY["TOOL"]=${BUILD_ENVIRONMENT["TOOL"]};
	[[ -z ${BUILD_ENTRY["JOBS"]} ]] && BUILD_ENTRY["JOBS"]=$OPT_JOBS;
	BUILD_ENTRY["OPTION"]="${BUILD_ENTRY["OPTION"]} $OPT_OPTION"

	[ $OPT_INFO == true ] && return;

	mkdir -p ${BUILD_ENVIRONMENT["RESULT"]}
	[ $? -ne 0 ] && exit 1;

	mkdir -p $BUILD_LOG_DIR
	[ $? -ne 0 ] && exit 1;

	if [ $OPT_PRECMD == true ] && [[ -n ${BUILD_ENTRY["PRECMD"]} ]]; then
		exec_shell "${BUILD_ENTRY["PRECMD"]}" ${target}
		[ $? -ne 0 ] && exit 1;
	fi

	if [ $OPT_MAKE == true ] && [[ -n ${BUILD_ENTRY["PATH"]} ]]; then
		make_target "$target" "$command"
		[ $? -ne 0 ] && exit 1;
	fi


	if [ $OPT_COPY == true ]; then
		local path=${BUILD_ENTRY["PATH"]} out=${BUILD_ENTRY["OUTPUT"]}
		local dir=${BUILD_ENVIRONMENT["RESULT"]} ret=${BUILD_ENTRY["COPY"]}

		if [[ -n $out ]]; then
			copy_result "$path" "$out" "$dir" "$ret"
			[ $? -ne 0 ] && exit 1;
		fi
	fi

	if [ $OPT_POSTCMD == true ] && [[ -n ${BUILD_ENTRY["POSTCMD"]} ]]; then
		exec_shell "${BUILD_ENTRY["POSTCMD"]}" ${target}
		[ $? -ne 0 ] && exit 1;
	fi
}

function parse_build_targets () {
	local ret=$1

	for i in "${BUILD_IMAGES[@]}"; do
		local add=true
		local val="$(echo $i| cut -d'=' -f 1)"
		val="$(echo -e "${val}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

		# skip buil environments"
		for n in ${!BUILD_ENVIRONMENT[@]}; do
			if [[ $n == $val ]]; then
				add=false
				break
			fi
			[ $? -ne 0 ] && exit 1;
		done

		[ $add != true ] && continue;

		if [[ $i == *"="* ]];then
			eval "${ret}+=(\"${val}\")"
		fi
	done
}

OPT_INFO=false
OPT_MAKE=false
OPT_PRECMD=false
OPT_POSTCMD=false
OPT_COPY=false
OPT_VERBOSE=false
OPT_TRACE=false
OPT_JOBS=`grep processor /proc/cpuinfo | wc -l`

case "$1" in
	-f )
		build_config=$2
		build_target=()
		build_command=""
		show_list=false

		if [ ! -f $build_config ]; then
			err " Not found build config: $build_config"
			exit 1;
		fi

		# include config script file
		source $build_config

		parse_build_targets BUILD_TARGETS

		while [ "$#" -gt 2 ]; do
			count=0
			while true
			do
				if [[ ${BUILD_TARGETS[$count]} == $3 ]]; then
					build_target+=("${BUILD_TARGETS[$count]}");
					((count=0))
					shift 1
					continue
				fi
				((count++))
				[ $count -ge ${#BUILD_TARGETS[@]} ] && break;
			done

			case "$3" in
			-l )	show_list=true; shift 2;;
			-j )	OPT_JOBS=$4; shift 2;;
			-i ) 	OPT_INFO=true; shift 1;;
			-m )	OPT_MAKE=true; shift 1;;
			-p ) 	OPT_PRECMD=true; shift 1;;
			-s ) 	OPT_POSTCMD=true; shift 1;;
			-c )	OPT_COPY=true; shift 1;;
			-o )	OPT_OPTION="$4"; shift 2;;
			-v )	OPT_VERBOSE=true; shift 1;;
			-vv)	OPT_VERBOSE=true; OPT_TRACE=true; shift 1;;
			-e )
				vim $build_config
				exit 0;;
			-h )	usage;
				exit 1;;
			*)	[[ -n $3 ]] && build_command=$3;
				shift;;
			esac
		done

		if [ ${#build_target[@]} -eq 0 ] && [[ -n $build_command ]]; then
			if [[ $build_command != clean ]] &&
			   [[ $build_command != cleanbuild ]] &&
			   [[ $build_command != rebuild ]]; then
				err "------------------------------------------------------------------"
				err " Not support command: $build_command ...\n"
				echo -e  " Check command : clean, cleanbuild, rebuild"
				echo -en " Check targets : "
				for i in "${BUILD_TARGETS[@]}"; do
					echo -n "$i "
				done
				err "\n------------------------------------------------------------------"
				exit 1;
			fi
		fi

		if [ $OPT_MAKE == false ] && [ $OPT_COPY == false ] &&
		   [ $OPT_PRECMD == false ] && [ $OPT_POSTCMD == false ];
		then
			OPT_MAKE=true
			OPT_COPY=true
			OPT_PRECMD=true
			OPT_POSTCMD=true
		fi

		# target all
		[ ${#build_target[@]} -eq 0 ] && build_target=(${BUILD_TARGETS[@]});

		# parse environment
		parse_build_env "${BUILD_IMAGES[@]}"
		setup_build_env ${BUILD_ENVIRONMENT["TOOL"]}

		if [ $show_list == true ]; then
			msg "------------------------------------------------------------------"
			msg " Targets:"
			for i in "${BUILD_TARGETS[@]}"; do
				echo -n " $i"
			done
			msg "\n------------------------------------------------------------------"
			exit 0;
		fi

		[ $OPT_INFO == true ] && print_env;

		# build
		for i in "${build_target[@]}"; do
			run_build "$i" "$build_command"
		done
		;;

	-h | * )
		usage;
		exit 1
		;;
esac
