#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>
#
# - Build Config File Formats
# BUILD_IMAGES=(
# 	"MACHINE	= <machine name>",
# 	"ARCH  		= <architecture ex> arm, arm64>",
# 	"TOOL		= <crosstool compiler path for make build>",
# 	"RESULT 	= <to copy build images>",
# 	"<target>	=
#  		PATH	: <build source path>,
#		CONFIG	: <default condig (defconfig) for make build>,
#		IMAGE	: <target image name for make build>,
#		TOOL	: <crosstool compiler path to make for this target>,
#		OUTPUT	: <name of make built imag to copy to resultdir, copy after post command>,
#		OPTION	: <make option>,
#		PRECMD	: <pre command before make build>,
#		POSTCMD	: <post command after make build and copy done>,
# 		COPY	: <copy name to RESULT>,
#  		JOBS	: <build jobs number (-j n)>",
#

eval "$(locale | sed -e 's/\(.*\)=.*/export \1=en_US.UTF-8/')"

declare -A BUILD_ENV_ELEMENT=(
	["ARCH"]=" "
  	["MACHINE"]=" "
  	["TOOL"]=" "
  	["RESULT"]=" "
)

declare -A BUILD_TARGET_ELEMENT=(
	["PATH"]=" "	# build source path
	["CONFIG"]=" "	# default condig (defconfig) for make build
	["IMAGE"]=" "	# target image name for make build
	["TOOL"]=" "	# crosstool compiler path to make for this target
	["OUTPUT"]=" "	# name of make built imag to copy to resultdir, copy after post command
	["OPTION"]=" "	# make option
	["PRECMD"]=" "	# pre command before make build.
	["POSTCMD"]=" "	# post command after make build and copy done.
  	["COPY"]=" "	# copy name to RESULT
  	["JOBS"]=" "	# build jobs number (-j n)
)

declare -A BUILD_STAGE_COMMAND=(
	["precmd"]=true		# execute script 'PRECMD'
	["make"]=true		# make with 'PATH' and 'IMAGE'
	["copy"]=true		# execute copy with 'COPY'
	["postcmd"]=true	# execute script 'POSTCMD'
)

BUILD_EDIT_TOOL="vim"
BUILD_LOG_DIR="$(realpath "$(dirname "$(realpath "${0}")")")/.build"
BUILD_PROGRESS_PID="$BUILD_LOG_DIR/progress_pid"

BUILD_CONFIG_IMAGES=()	# copy BUILD_IMAGES
BUILD_CONFIG_TARGETS=()

BUILD_CONFIG=""
BUILD_TARGETS=()
BUILD_COMMAND=""
BUILD_JOBS="$(grep -c processor /proc/cpuinfo)"
BUILD_OPTION=""

DBG_VERBOSE=false
DBG_TRACE=false
CMD_SHOW_INFO=false
CMD_SHOW_LIST=false
CMD_EDIT=false

function err () { echo -e "\033[1;31m$*\033[0m"; }
function msg () { echo -e "\033[0;33m$*\033[0m"; }

function usage() {
	echo ""
	echo "Usage: $(basename "$0") -f config [options]"
	echo ""
	echo " options:"
	echo -e  "\t-t\t select build targets, ex> -t target ..."
	echo -e  "\t-c\t build command"
	echo -e  "\t\t - defconfig"
	echo -e  "\t\t - menuconfig"
	echo -e  "\t\t - clean"
	echo -e  "\t\t - distclean"
	echo -e  "\t\t - cleanbuild"
	echo -e  "\t\t - rebuild"
	echo -e  "\t\t - else command supported by target"
	echo -e  "\t-i\t show build target info"
	echo -e  "\t-l\t listup build targets"
	echo -e  "\t-j\t set build jobs"
	echo -e  "\t-o\t set build options"
	echo -e  "\t-e\t edit build config file"
	echo -e  "\t-v\t print build log"
	echo -e  "\t-D\t print build log and enable external shell tasks tracing (with 'set -x')"
	echo -ne "\t-s\t only execute build stage :"
	for i in "${!BUILD_STAGE_COMMAND[@]}"; do
		echo -n " $i";
	done
	echo ""
	echo -e  "\n\t Build sequence: PRECMD > make > result copy > POSTCMD"
	echo ""
}

function show_build_time () {
	local hrs=$(( SECONDS/3600 ));
	local min=$(( (SECONDS-hrs*3600)/60));
	local sec=$(( SECONDS-hrs*3600-min*60 ));

	printf "\n Total: %d:%02d:%02d\n" $hrs $min $sec
}

function show_progress () {
	local spin='-\|/'
	local pos=0
	local delay=0.3
	local start=$SECONDS

	while true; do
		local hrs=$(( (SECONDS-start)/3600 ));
		local min=$(( (SECONDS-start-hrs*3600)/60));
		local sec=$(( (SECONDS-start)-hrs*3600-min*60 ))

		pos=$(( (pos + 1) % 4 ))
		printf "\r Progress |${spin:$pos:1}| Time: %d:%02d:%02d" $hrs $min $sec
		sleep $delay
	done
}

function kill_progress () {
	local pid

	[[ ! -e $BUILD_PROGRESS_PID ]] && return;

	pid=$(cat "$BUILD_PROGRESS_PID")
	if [[ $pid -ne 0 ]] && [[ -e /proc/$pid ]]; then
		kill "$pid" 2> /dev/null
		wait "$pid" 2> /dev/null
		rm -f "$BUILD_PROGRESS_PID"
		echo ""
	fi
}

function run_progress () {
	kill_progress
	show_progress &
	echo $! > "$BUILD_PROGRESS_PID"
}

function copy_result () {
	local path=$1 src=$2 retdir=$3 dst=$4

	[[ -z $src ]] && return;

	if ! mkdir -p "$retdir"; then exit 1; fi

	src=$(realpath "$path/$src")
	dst=$(realpath "$retdir/$dst")
	if [[ -d $src ]] && [[ -d $dst ]]; then
		rm -rf "$dst";
	fi

	msg ""; msg " $> cp -a $src $dst"
	cp -a "$src" "$dst"
}

function print_env () {
	msg "==============================================================================="
	for key in "${!BUILD_ENV_ELEMENT[@]}"; do
		[[ -z ${BUILD_ENV_ELEMENT[$key]} ]] && continue;
		message=$(printf " %-8s = %s\n" "$key" "${BUILD_ENV_ELEMENT[$key]}")
		msg "$message"
	done
	msg "==============================================================================="
}

function parse_env_value () {
	local key=$1 ret=$2

	for i in "${BUILD_CONFIG_IMAGES[@]}"; do
		if [[ $i = *"$key"* ]]; then
			local elem
			elem="$(echo "$i" | cut -d'=' -f 2-)"
			elem="$(echo "$elem" | cut -d',' -f 1)"
			elem="$(echo -e "${elem}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
			eval "$ret=(\"${elem}\")"
			break
		fi
	done
}

function parse_env () {
	for key in "${!BUILD_ENV_ELEMENT[@]}"; do
		local val=""
		parse_env_value "$key" val
		BUILD_ENV_ELEMENT[$key]=$val
	done
}

function setup_env () {
	local path

	[[ -z $1 ]] && return;

	path=$(realpath "$(dirname "$1")")
	if [[ -z $path ]]; then
		err " No such 'TOOL': $(dirname "$1")"
		exit 1
	fi
	export PATH=$path:$PATH
}

function print_target_element () {
	local target=$1

	msg ""
	msg "-------------------------------------------------------------------------------"
	echo -e "\033[1;32m Build Target : $target\033[0m";
	for key in "${!BUILD_TARGET_ELEMENT[@]}"; do
		[[ -z "${BUILD_TARGET_ELEMENT[$key]}" ]] && continue;
		if [[ "${key}" == "PATH" ]]; then
			message=$(printf " %-12s = %s\n" "$key" "$(realpath "${BUILD_TARGET_ELEMENT[$key]}")")
		else
			message=$(printf " %-12s = %s\n" "$key" "${BUILD_TARGET_ELEMENT[$key]}")
		fi
		msg "$message"
	done
	msg "-------------------------------------------------------------------------------"
}

function parse_element_value () {
	local str=$1 key=$2 ret=$3
	local val

	[[ $str != *"$key"* ]] && return;

	val="${str#*$key}"
	val="$(echo "$val" | cut -d":" -f 2-)"
	val="$(echo "$val" | cut -d"," -f 1)"
	val="$(echo "$val" | cut -d"'" -f 2)"
	val="$(echo "$val" | cut -d"'" -f 1)"

	# remove first,last space and set multiple space to single space
	val="$(echo "$val" | sed 's/^[ \t]*//;s/[ \t]*$//')"
	val="$(echo "$val" | sed 's/\s\s*/ /g')"
	eval "$ret=(\"${val}\")"
}

function parse_target_element () {
	local target=$1
	local contents

	for i in "${BUILD_CONFIG_IMAGES[@]}"; do
		if [[ $i == *"$target"* ]]; then
			local elem

			elem="$(echo $(echo "$i" | cut -d'=' -f 1) | cut -d' ' -f 1)"
			[[ $target != "$elem" ]] && continue;

			# cut
			elem="${i#*$elem*=}"
			# remove line-feed, first and last blank
			contents="$(echo "$elem" | tr '\n' ' ')"
			contents="$(echo "$contents" | sed 's/^[ \t]*//;s/[ \t]*$//')"
			break
		fi
	done

	for key in "${!BUILD_TARGET_ELEMENT[@]}"; do
		local value=""

		parse_element_value "$contents" "$key" value

		BUILD_TARGET_ELEMENT[$key]=$value
		if [[ $key == PRECMD ]] || [[ $key == POSTCMD ]] || [[ $key == OPTION ]]; then
			continue;
		fi
	done

	if [[ -n ${BUILD_TARGET_ELEMENT["PATH"]} ]]; then
		BUILD_TARGET_ELEMENT["PATH"]=$(realpath "${BUILD_TARGET_ELEMENT["PATH"]}")
	fi

	if [[ -z ${BUILD_TARGET_ELEMENT["TOOL"]} ]]; then
		BUILD_TARGET_ELEMENT["TOOL"]=${BUILD_ENV_ELEMENT["TOOL"]};
	fi

	if [[ -z ${BUILD_TARGET_ELEMENT["JOBS"]} ]];then
		BUILD_TARGET_ELEMENT["JOBS"]=$BUILD_JOBS;
	fi

	if [[ -n $BUILD_OPTION ]]; then
		BUILD_TARGET_ELEMENT["OPTION"]+="$BUILD_OPTION"
	fi
}

function parse_targets () {
	for str in "${BUILD_CONFIG_IMAGES[@]}"; do
		local val add=true

		str="$(echo "$str" | tr '\n' ' ')"
		val="$(echo "$str" | cut -d'=' -f 1)"
		val="$(echo -e "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

		# skip buil environments"
		for n in "${!BUILD_ENV_ELEMENT[@]}"; do
			if [[ $n == "$val" ]]; then
				add=false
				break
			fi
		done

		[[ $add != true ]] && continue;

		if [[ $str == *"="* ]];then
			BUILD_CONFIG_TARGETS+=("$val")
		fi
	done
}

function setup_config () {
	local config=$1

	if [[ ! -f $config ]]; then
		err " Not found build config: $config"
		usage;
		exit 1;
	fi

	# include config script file
	source "$config"
	if [[ -z $BUILD_IMAGES ]]; then
		err "Not defined 'BUILD_IMAGES'"
		exit 1
	fi

	BUILD_CONFIG_IMAGES=("${BUILD_IMAGES[@]}");
}

function exec_shell () {
	local command=$1 target=$2 
	local log="$BUILD_LOG_DIR/$target.script.log"
	local ret

	command="$(echo "$command" | sed 's/\s\s*/ /g')"

	msg " "; msg " $> $command "
	rm -f "$log"

	[[ $DBG_TRACE == true ]] && set -x;
	[[ $DBG_VERBOSE == false ]] && run_progress;

	if type "$command" 2>/dev/null | grep -q 'function'; then
		if [[ $DBG_VERBOSE == false ]]; then
			$command >> "$log" 2>&1
		else
			$command
		fi
	else
		if [[ $DBG_VERBOSE == false ]]; then
			bash -c "$command" >> "$log" 2>&1
		else
			bash -c "$command"
		fi
	fi
	### get return value ###
	ret=$?

	[[ $DBG_TRACE == true ]] && set +x;
	if [[ $ret -ne 0 ]] && [[ $DBG_VERBOSE == false ]]; then
		err " ERROR: script '$target':$log\n";
	fi

	kill_progress
	return $ret
}

function exec_make () {
	local command=$1 target=$2 
	local log="$BUILD_LOG_DIR/$target.make.log"
	local ret

	command="$(echo "$command" | sed 's/\s\s*/ /g')"

	msg " "; msg " $> make $command"
	rm -f "$log"

	if [[ $DBG_VERBOSE == false ]] && [[ $command != *menuconfig* ]]; then
		run_progress
		make $command >> "$log"  2>&1
	else
		make $command
	fi
	### get return value ###
	ret=$?

	if [[ $ret -eq 2 ]] && [[ $DBG_VERBOSE == false ]] &&
	   [[ $command != *"clean"* ]]; then
		err " ERROR: make '$target':$log\n";
	else
		ret=0
	fi

	kill_progress
	return $ret
}

function precmd_target () {
	local target=$1

	if [[ -n ${BUILD_TARGET_ELEMENT["PRECMD"]} ]] &&
	   [[ ${BUILD_STAGE_COMMAND["precmd"]} == true ]]; then
		if ! exec_shell "${BUILD_TARGET_ELEMENT["PRECMD"]}" "$target"; then
			exit 1;
		fi
	fi
}

function make_target () {
	local target=$1 command=$2
	local path=${BUILD_TARGET_ELEMENT["PATH"]}
	local crosstool="ARCH=${BUILD_ENV_ELEMENT["ARCH"]} CROSS_COMPILE=${BUILD_TARGET_ELEMENT["TOOL"]}"
	local image=${BUILD_TARGET_ELEMENT["IMAGE"]}
	local config=${BUILD_TARGET_ELEMENT["CONFIG"]}
	local opt="${BUILD_TARGET_ELEMENT["OPTION"]} -j${BUILD_TARGET_ELEMENT["JOBS"]}"

	if [[ -z ${BUILD_TARGET_ELEMENT["PATH"]} ]] ||
	   [[ ${BUILD_STAGE_COMMAND["make"]} == false ]]; then
		return;
	fi

	if [[ ! -d $path ]]; then
		err " Invalid 'PATH' '$path' for $target ..."
		exit 1;
	fi

	if [[ ! -f $path/makefile ]] && [[ ! -f $path/Makefile ]]; then
		msg " Not found Makefile for $target in '$path' ..."
		return;
	fi

	# clean commands
	if [[ $image != *".dtb"* ]]; then
		if [[ $command == distclean ]] || [[ $command == rebuild ]]; then
			exec_make "-C $path clean" "$target"
			exec_make "-C $path distclean" "$target"
		fi

		if [[ $command == clean ]] || [[ $command == cleanbuild ]]; then
			exec_make "-C $path clean" "$target"
		fi

		if  [[ $command == rebuild ]] || [[ $command == cleanbuild ]] &&
		    [[ -n ${BUILD_TARGET_ELEMENT["PRECMD"]} ]]; then
			if ! exec_shell "${BUILD_TARGET_ELEMENT["PRECMD"]}" "$target";
			then
				exit 1;
			fi
		fi
	fi

	# exit clean commands
	[[ $command == distclean ]] || [[ $command == clean ]] && exit 0;

	# config commands
	if [[ -n $config ]]; then
		if [[ $command == defconfig ]] || [[ ! -f $path/.config ]]; then
			if ! exec_make "-C $path $crosstool $config" "$target";
			then
				exit 1;
			fi
		fi

		if [[ $command == menuconfig ]]; then
			if ! exec_make "-C $path $crosstool menuconfig" "$target";
			then
				exit 1;
			fi
		fi
	fi

	# exit config
	[[ $command == defconfig ]] || [[ $command == menuconfig ]] && exit 0;

	# set command with image
	if [[ $command == rebuild ]] || [[ $command == cleanbuild ]]; then
		command=$image;
	fi

	if ! exec_make "-C $path $crosstool $command $opt" "$target";
	then
		exit 1
	fi
}

function copy_target () {
	if [[ -n ${BUILD_TARGET_ELEMENT["OUTPUT"]} ]] &&
	   [[ ${BUILD_STAGE_COMMAND["copy"]} == true ]]; then
		if ! copy_result "${BUILD_TARGET_ELEMENT["PATH"]}" \
			    "${BUILD_TARGET_ELEMENT["OUTPUT"]}" \
			    "${BUILD_ENV_ELEMENT["RESULT"]}" \
			    "${BUILD_TARGET_ELEMENT["COPY"]}"; then
			exit 1;
		fi
	fi
}

function postcmd_target () {
	local target=$1

	if [[ -n ${BUILD_TARGET_ELEMENT["POSTCMD"]} ]] &&
	   [[ ${BUILD_STAGE_COMMAND["postcmd"]} == true ]]; then
		if ! exec_shell "${BUILD_TARGET_ELEMENT["POSTCMD"]}" "$target"; then
			exit 1;
		fi
	fi
}

function build_target () {
	local target=$1 command=$2

	parse_target_element "$target"
	print_target_element "$target"

	[[ $CMD_SHOW_INFO == true ]] && return;

	if ! mkdir -p "${BUILD_ENV_ELEMENT["RESULT"]}"; then exit 1; fi
	if ! mkdir -p "$BUILD_LOG_DIR"; then exit 1; fi

	# build commands
	precmd_target "$target"
	make_target "$target" "$command"
	copy_target
	postcmd_target "$target"
}

function run_build () {
	if [[ ${#BUILD_TARGETS[@]} -eq 0 ]]; then
		if [[ -n $BUILD_COMMAND ]] &&
		   [[ $BUILD_COMMAND != clean ]] &&
		   [[ $BUILD_COMMAND != cleanbuild ]] &&
		   [[ $BUILD_COMMAND != rebuild ]]; then
			err "-------------------------------------------------------------------------------"
			err " Not Support Command: $BUILD_COMMAND"
			err " *** if the target is not selected, support command:"
			msg " clean, cleanbuild, rebuild"
			err "-------------------------------------------------------------------------------"
			exit 1;
		fi

		BUILD_TARGETS=("${BUILD_CONFIG_TARGETS[@]}");
	else
		for i in "${BUILD_TARGETS[@]}"; do
			local found=false;
			for n in "${BUILD_CONFIG_TARGETS[@]}"; do
				if [[ $i == "$n" ]]; then
					found=true
					break;
				fi
			done
			if [[ $found == false ]]; then
				echo -ne "\n\033[1;31m Not Support Target: $i ( \033[0m"
				for t in "${BUILD_CONFIG_TARGETS[@]}"; do
					echo -n "$t "
				done
				echo -e "\033[1;31m)\033[0m\n"
				exit 1;
			fi
		done
	fi

	if [[ $CMD_SHOW_LIST == true ]]; then
		msg "-------------------------------------------------------------------------------"
		msg " Build Targets:"
		for i in "${BUILD_CONFIG_TARGETS[@]}"; do
			echo -n " $i"
		done
		msg "\n-------------------------------------------------------------------------------"
		exit 0;
	fi

	[[ $CMD_SHOW_INFO == true ]] && print_env;

	for t in "${BUILD_TARGETS[@]}"; do
		build_target "$t" "$BUILD_COMMAND"
	done

	show_build_time
}

function set_build_stage () {
	for i in "${!BUILD_STAGE_COMMAND[@]}"; do
		if [[ $i == "$1" ]]; then
			for n in "${!BUILD_STAGE_COMMAND[@]}"; do
				BUILD_STAGE_COMMAND[$n]=false
			done
			BUILD_STAGE_COMMAND[$i]=true
			return
		fi
	done

	echo -ne "\n\033[1;31m Not Support Stage Command: $i ( \033[0m"
	for i in "${!BUILD_STAGE_COMMAND[@]}"; do
		echo -n "$i "
	done
	echo -e "\033[1;31m)\033[0m\n"
	exit 1;
}

function parse_arguments () {
	while getopts "f:t:c:j:o:s:ilevDh" opt; do
	case $opt in
		f )	BUILD_CONFIG=$OPTARG;;
		t )	BUILD_TARGETS=("$OPTARG")
			until [[ $(eval "echo \${$OPTIND}") =~ ^-.* ]] || [[ -z "$(eval "echo \${$OPTIND}")" ]]; do
				BUILD_TARGETS+=("$(eval "echo \${$OPTIND}")")
				OPTIND=$((OPTIND + 1))
			done
			;;
		c )	BUILD_COMMAND="$OPTARG";;
		j )	BUILD_JOBS=$OPTARG;;
		v )	DBG_VERBOSE=true;;
		D )	DBG_VERBOSE=true; DBG_TRACE=true;;
		o )	BUILD_OPTION="$OPTARG";;
		i ) 	CMD_SHOW_INFO=true;;
		l )	CMD_SHOW_LIST=true;;
		e )	CMD_EDIT=true;
			break;;
		s ) 	set_build_stage "$OPTARG";;
		h )	usage;
			exit 1;;
	        * )	exit 1;;
	esac
	done
}

###############################################################################
# Run build
###############################################################################

parse_arguments "$@"
setup_config "$BUILD_CONFIG"

if [[ "${CMD_EDIT}" == true ]]; then
	$BUILD_EDIT_TOOL "$BUILD_CONFIG"
	exit 0;
fi

parse_targets
parse_env
setup_env "${BUILD_ENV_ELEMENT["TOOL"]}"

run_build
