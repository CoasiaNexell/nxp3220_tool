#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>
#
# - Config File Formats
# BUILD_IMAGES=(
# 	"MACHINE	= <machine name>",
# 	"ARCH  		= <architecture ex> arm, arm64>",
# 	"TOOL		= <crosstool compiler path for make build>",
# 	"RESULT 	= <to copy build images>",
#
# 	"<TARGET>	=
#  		PATH		: <Makefile source path to make build>,
#		CONFIG		: <default config (defconfig) for make build>,
#		IMAGE		: <make build target name for make build>,
#		TOOL		: <crosstool compiler path to make for this target>,
#		OUTPUT		: <name of make built imag to copy to resultdir, copy after post command>,
#		OPTION		: <make option>,
#		PRECMD		: <pre command before make build>,
#		POSTCMD		: <post command after make build and copy done>,
#		CLEANCMD	: clean command>,
# 		COPY		: <copy name to RESULT>,
#  		JOBS		: <build jobs number (-j n)>",
#

eval "$(locale | sed -e 's/\(.*\)=.*/export \1=en_US.UTF-8/')"

EDIT_TOOL="vim"			# editor with '-e' option

# config script's environment elements
declare -A BUILD_CONFIG_ENV=(
	["ARCH"]=" "
  	["MACHINE"]=" "
  	["TOOL"]=" "
  	["RESULT"]=" "
)

# config script's target elements
declare -A BUILD_CONFIG_TARGET=(
	["PATH"]=" "		# Makefile source path to make build
	["CONFIG"]=" "		# default config (defconfig) for make build
	["IMAGE"]=" "		# make build target name for make build
	["TOOL"]=" "		# crosstool compiler path to make for this target
	["OUTPUT"]=" "		# name of make built imag to copy to resultdir, copy after post command
	["OPTION"]=" "		# make option
	["PRECMD"]=" "		# pre command before make build.
	["POSTCMD"]=" "		# post command after make build and copy done.
	["CLEANCMD"]=" "	# clean command.
	["COPY"]=" "		# copy name to RESULT
	["JOBS"]=" "		# build jobs number (-j n)
)

BUILD_CONFIG_SCRIPT=""		# build config script file
BUILD_CONFIG_IMAGE=()		# store $BUILD_IMAGES

declare -A BUILD_STAGE=(
	["precmd"]=true		# execute script 'PRECMD'
	["make"]=true		# make with 'PATH' and 'IMAGE'
	["copy"]=true		# execute copy with 'COPY'
	["postcmd"]=true	# execute script 'POSTCMD'
)

BUILD_TARGET_LIST=()
BUILD_TARGET=()
BUILD_COMMAND=""
BUILD_CLEANALL=false
BUILD_OPTION=""
BUILD_JOBS="$(grep -c processor /proc/cpuinfo)"

CMD_SHOW_INFO=false
CMD_SHOW_LIST=false
CMD_EDIT=false

DBG_VERBOSE=false
DBG_TRACE=false

BUILD_LOG_DIR="$(realpath "$(dirname "$(realpath "${0}")")")/.build"
BUILD_PROGRESS_PID="$BUILD_LOG_DIR/progress_pid"

function err () { echo -e "\033[0;31m$*\033[0m"; }
function msg () { echo -e "\033[0;33m$*\033[0m"; }

function usage() {
	echo ""
	echo "Usage: $(basename "$0") -f config [options]"
	echo ""
	echo " options:"
	echo -e  "\t-t\t select build targets, ex> -t target ..."
	echo -e  "\t-c\t build command"
	echo -e  "\t\t support 'cleanbuild','rebuild' and commands supported by target"
	echo -e  "\t-r\t build clean all targets"
	echo -e  "\t-i\t show build target info"
	echo -e  "\t-l\t listup build targets"
	echo -e  "\t-j\t set build jobs"
	echo -e  "\t-o\t set build options"
	echo -e  "\t-e\t edit build config file"
	echo -e  "\t-v\t print build log"
	echo -e  "\t-D\t print build log and enable external shell tasks tracing (with 'set -x')"
	echo -ne "\t-s\t only execute stage :"
	for i in "${!BUILD_STAGE[@]}"; do
		echo -n " '$i'";
	done
	echo -e  "\n\t\t Build stage order  : precmd > make > copy > postcmd"
	echo ""
}

function show_build_time () {
	local hrs=$(( SECONDS/3600 ));
	local min=$(( (SECONDS-hrs*3600)/60));
	local sec=$(( SECONDS-hrs*3600-min*60 ));

	printf "\n Total: %d:%02d:%02d\n" $hrs $min $sec
}

function show_progress () {
	local spin='-\|/' pos=0
	local delay=0.3 start=$SECONDS

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

function print_env () {
	msg "==============================================================================="
	for key in "${!BUILD_CONFIG_ENV[@]}"; do
		[[ -z ${BUILD_CONFIG_ENV[$key]} ]] && continue;
		message=$(printf " %-8s = %s\n" "$key" "${BUILD_CONFIG_ENV[$key]}")
		msg "$message"
	done
	msg "==============================================================================="
}

function parse_env () {
	for key in "${!BUILD_CONFIG_ENV[@]}"; do
		local val=""
		for i in "${BUILD_CONFIG_IMAGE[@]}"; do
			if [[ $i = *"$key"* ]]; then
				local elem
				elem="$(echo "$i" | cut -d'=' -f 2-)"
				elem="$(echo "$elem" | cut -d',' -f 1)"
				elem="$(echo -e "${elem}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
				val=$elem
				break
			fi
		done
		BUILD_CONFIG_ENV[$key]=$val
	done
}

function setup_env () {
	[[ -z $1 ]] && return;

	local path=$(realpath "$(dirname "$1")")
	if [[ -z $path ]]; then
		err " No such 'TOOL': $(dirname "$1")"
		exit 1
	fi
	export PATH=$path:$PATH
}

function print_target () {
	local target=$1

	msg ""
	msg "-------------------------------------------------------------------------------"
	echo -e "\033[1;32m Build Target : $target\033[0m";
	for key in "${!BUILD_CONFIG_TARGET[@]}"; do
		[[ -z "${BUILD_CONFIG_TARGET[$key]}" ]] && continue;
		if [[ "${key}" == "PATH" ]]; then
			message=$(printf " %-12s = %s\n" "$key" "$(realpath "${BUILD_CONFIG_TARGET[$key]}")")
		else
			message=$(printf " %-12s = %s\n" "$key" "${BUILD_CONFIG_TARGET[$key]}")
		fi
		msg "$message"
	done
	msg "-------------------------------------------------------------------------------"
}

function parse_target () {
	local target=$1
	local contents

	# get target's contents
	for i in "${BUILD_CONFIG_IMAGE[@]}"; do
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

	# parse contents's elements
	for key in "${!BUILD_CONFIG_TARGET[@]}"; do
		local val=""

		if [[ $contents != *"$key"* ]]; then
			BUILD_CONFIG_TARGET[$key]=$val
			continue;
		fi

		val="${contents#*$key}"
		val="$(echo "$val" | cut -d":" -f 2-)"
		val="$(echo "$val" | cut -d"," -f 1)"
		val="$(echo "$val" | cut -d"'" -f 2)"
		val="$(echo "$val" | cut -d"'" -f 1)"

		# remove first,last space and set multiple space to single space
		val="$(echo "$val" | sed 's/^[ \t]*//;s/[ \t]*$//')"
		val="$(echo "$val" | sed 's/\s\s*/ /g')"

		BUILD_CONFIG_TARGET[$key]="$val"
	done

	if [[ -n ${BUILD_CONFIG_TARGET["PATH"]} ]]; then
		BUILD_CONFIG_TARGET["PATH"]=$(realpath "${BUILD_CONFIG_TARGET["PATH"]}")
	fi

	if [[ -z ${BUILD_CONFIG_TARGET["TOOL"]} ]]; then
		BUILD_CONFIG_TARGET["TOOL"]=${BUILD_CONFIG_ENV["TOOL"]};
	fi

	if [[ -z ${BUILD_CONFIG_TARGET["JOBS"]} ]];then
		BUILD_CONFIG_TARGET["JOBS"]=$BUILD_JOBS;
	fi

	if [[ -n $BUILD_OPTION ]]; then
		BUILD_CONFIG_TARGET["OPTION"]+="$BUILD_OPTION"
	fi
}

function listup_target () {
	for str in "${BUILD_CONFIG_IMAGE[@]}"; do
		local val add=true

		str="$(echo "$str" | tr '\n' ' ')"
		val="$(echo "$str" | cut -d'=' -f 1)"
		val="$(echo -e "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

		# skip buil environments"
		for n in "${!BUILD_CONFIG_ENV[@]}"; do
			if [[ $n == "$val" ]]; then
				add=false
				break
			fi
		done

		[[ $add != true ]] && continue;

		if [[ $str == *"="* ]];then
			BUILD_TARGET_LIST+=("$val")
		fi
	done
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
		make $command >> "$log" 2>&1
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

function do_precmd () {
	local target=$1

	if [[ -z ${BUILD_CONFIG_TARGET["PRECMD"]} ]] ||
	   [[ $BUILD_CLEANALL == true ]] ||
	   [[ ${BUILD_STAGE["precmd"]} == false ]]; then
		return;
	fi

	if ! exec_shell "${BUILD_CONFIG_TARGET["PRECMD"]}" "$target"; then
		exit 1;
	fi
}

function do_make () {
	local target=$1 command=$2
	local path=${BUILD_CONFIG_TARGET["PATH"]}
	local crosstool="ARCH=${BUILD_CONFIG_ENV["ARCH"]} CROSS_COMPILE=${BUILD_CONFIG_TARGET["TOOL"]}"
	local image=${BUILD_CONFIG_TARGET["IMAGE"]}
	local defconfig=${BUILD_CONFIG_TARGET["CONFIG"]}
	local opt="${BUILD_CONFIG_TARGET["OPTION"]} -j${BUILD_CONFIG_TARGET["JOBS"]}"
	local save_config="${path}/.${target}_defconfig"
	local config_ver="BSP:${defconfig}"

	declare -A make_mode=(
		["distclean"]=false
		["clean"]=false
		["defconfig"]=false
		["menuconfig"]=false
		)

	if [[ -z ${BUILD_CONFIG_TARGET["PATH"]} ]] ||
	   [[ ${BUILD_STAGE["make"]} == false ]]; then
		return;
	fi

	if [[ ! -d ${BUILD_CONFIG_TARGET["PATH"]} ]]; then
		err " Not found 'PATH': '${BUILD_CONFIG_TARGET["PATH"]}'"
		exit 1;
	fi

	if [[ ! -f $path/makefile ]] && [[ ! -f $path/Makefile ]]; then
		msg " Not found Makefile in '$path' ..."
		return;
	fi

	if [[ $image != *".dtb"* ]]; then
		if [[ $command == clean ]] || [[ $command == cleanbuild ]] ||
		   [[ $command == rebuild ]]; then
			make_mode["clean"]=true
		fi

		if [[ $command == cleanall ]] ||
		   [[ $command == distclean ]] || [[ $command == rebuild ]]; then
			make_mode["clean"]=true;
			make_mode["distclean"]=true;
		fi

		if [[ -n ${BUILD_CONFIG_TARGET["OPTION"]} ]]; then
			config_ver+=":${BUILD_CONFIG_TARGET["OPTION"]}"
		fi

		# check saved config
		if [[ ! -e $save_config ]] ||
		   [[ $(cat "$save_config") != "$config_ver" ]]; then
			make_mode["defconfig"]=true
			make_mode["clean"]=true;
			make_mode["distclean"]=true

			rm -f "$save_config";
			echo "$config_ver" >> "$save_config";
		fi

		# check .config
		if [[ -n $defconfig ]]; then
			if [[ $command == defconfig ]] || [[ $command == rebuild ]] ||
			   [[ ! -f $path/.config ]]; then
				make_mode["defconfig"]=true
				make_mode["clean"]=true;
				make_mode["distclean"]=true;
			fi

			if [[ $command == menuconfig ]]; then
				make_mode["menuconfig"]=true
			fi
		fi
	fi

	# make clean
	if [[ ${make_mode["clean"]} == true ]]; then
		exec_make "-C $path clean" "$target"
		[[ $command == clean ]] && exit 0;
	fi

	# make distclean
	if [[ ${make_mode["distclean"]} == true ]]; then
		exec_make "-C $path distclean" "$target"
		if [[ $command == distclean ]]|| [[ $BUILD_CLEANALL == true ]]; then
			rm -f "$save_config";
			[[ $BUILD_CLEANALL == true ]] && return;
			exit 0;
		fi
	fi

	# make defconfig
	if [[ ${make_mode["defconfig"]} == true ]]; then
		if ! exec_make "-C $path $crosstool $defconfig" "$target"; then
			exit 1;
		fi
		[[ $command == defconfig ]] && exit 0;
	fi

	# make menuconfig
	if [[ ${make_mode["menuconfig"]} == true ]]; then
		exec_make "-C $path $crosstool menuconfig" "$target";
		exit 0;
	fi

	# Set command with image
	if [[ -z $command ]] ||
	   [[ $command == rebuild ]] || [[ $command == cleanbuild ]]; then
		command=$image
	fi

	# make <command>
	if ! exec_make "-C $path $crosstool $command $opt" "$target"; then
		exit 1
	fi
}

function do_copy () {
	local target=$1
	local path=${BUILD_CONFIG_TARGET["PATH"]}
	local src=${BUILD_CONFIG_TARGET["OUTPUT"]}
	local retdir=${BUILD_CONFIG_ENV["RESULT"]}
	local dst=${BUILD_CONFIG_TARGET["COPY"]}

	if [[ -z $src ]] ||
	   [[ $BUILD_CLEANALL == true ]] ||
	   [[ ${BUILD_STAGE["copy"]} == false ]]; then
		return;
	fi

	if ! mkdir -p "$retdir"; then exit 1; fi

	src=$(realpath "$path/$src")
	dst=$(realpath "$retdir/$dst")
	if [[ -d $src ]] && [[ -d $dst ]]; then
		rm -rf "$dst";
	fi

	msg ""; msg " $> cp -a $src $dst"
	[[ $DBG_VERBOSE == false ]] && run_progress;

	cp -a "$src" "$dst"

	kill_progress
}

function do_postcmd () {
	local target=$1

	if [[ -z ${BUILD_CONFIG_TARGET["POSTCMD"]} ]] ||
	   [[ $BUILD_CLEANALL == true ]] ||
	   [[ ${BUILD_STAGE["postcmd"]} == false ]]; then
		return;
	fi

	if ! exec_shell "${BUILD_CONFIG_TARGET["POSTCMD"]}" "$target"; then
		exit 1;
	fi
}

function do_cleancmd () {
	local target=$1

	if [[ -z ${BUILD_CONFIG_TARGET["CLEANCMD"]} ]] ||
	   [[ $BUILD_CLEANALL == false ]]; then
		return;
	fi

	if ! exec_shell "${BUILD_CONFIG_TARGET["CLEANCMD"]}" "$target"; then
		exit 1;
	fi
}

function build_target () {
	local target=$1 command=$2

	parse_target "$target"
	print_target "$target"

	[[ $CMD_SHOW_INFO == true ]] && return;

	if ! mkdir -p "${BUILD_CONFIG_ENV["RESULT"]}"; then exit 1; fi
	if ! mkdir -p "$BUILD_LOG_DIR"; then exit 1; fi

	do_precmd "$target"
	do_make "$target" "$command"
	do_copy "$target"
	do_postcmd "$target"
	do_cleancmd "$target"
}

function run_build () {
	for i in "${BUILD_TARGET[@]}"; do
		local found=false;
		for n in "${BUILD_TARGET_LIST[@]}"; do
			if [[ $i == "$n" ]]; then
				found=true
				break;
			fi
		done
		if [[ $found == false ]]; then
			echo -ne "\n\033[1;31m Not Support Target: $i ( \033[0m"
			for t in "${BUILD_TARGET_LIST[@]}"; do
				echo -n "$t "
			done
			echo -e "\033[1;31m)\033[0m\n"
			exit 1;
		fi
	done

	if [[ ${#BUILD_TARGET[@]} -eq 0 ]]; then
		if [[ $BUILD_CLEANALL != true ]] &&
		   [[ -n $BUILD_COMMAND ]] &&
                   [[ $BUILD_COMMAND != cleanbuild ]] && [[ $BUILD_COMMAND != rebuild ]]; then
			err "-------------------------------------------------------------------------------"
			err " Not Support command : $BUILD_COMMAND"
			msg " If the target is not selected, Support commands: cleanbuild, rebuild"
			err "-------------------------------------------------------------------------------"
			exit 1;
		fi
		BUILD_TARGET=("${BUILD_TARGET_LIST[@]}");
	fi

	if [[ $CMD_SHOW_LIST == true ]]; then
		msg "-------------------------------------------------------------------------------"
		msg " Build Targets:"
		for i in "${BUILD_TARGET_LIST[@]}"; do
			echo -n " $i"
		done
		msg "\n-------------------------------------------------------------------------------"
		exit 0;
	fi

	[[ $CMD_SHOW_INFO == true ]] && print_env;

	for t in "${BUILD_TARGET[@]}"; do
		build_target "$t" "$BUILD_COMMAND"
	done

	[[ $BUILD_CLEANALL == true ]] &&
	[[ -d $BUILD_LOG_DIR ]] && rm -rf "$BUILD_LOG_DIR";

	show_build_time
}

function setup_stage () {
	for i in "${!BUILD_STAGE[@]}"; do
		if [[ $i == "$1" ]]; then
			for n in "${!BUILD_STAGE[@]}"; do
				BUILD_STAGE[$n]=false
			done
			BUILD_STAGE[$i]=true
			return
		fi
	done

	echo -ne "\n\033[1;31m Not Support Stage Command: $i ( \033[0m"
	for i in "${!BUILD_STAGE[@]}"; do
		echo -n "$i "
	done
	echo -e "\033[1;31m)\033[0m\n"
	exit 1;
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
		err " Not defined 'BUILD_IMAGES'"
		exit 1
	fi

	BUILD_CONFIG_IMAGE=("${BUILD_IMAGES[@]}");
}

function parse_arguments () {
	while getopts "f:t:c:rj:o:s:ilevDh" opt; do
	case $opt in
		f )	BUILD_CONFIG_SCRIPT=$OPTARG;;
		t )	BUILD_TARGET=("$OPTARG")
			until [[ $(eval "echo \${$OPTIND}") =~ ^-.* ]] || [[ -z "$(eval "echo \${$OPTIND}")" ]]; do
				BUILD_TARGET+=("$(eval "echo \${$OPTIND}")")
				OPTIND=$((OPTIND + 1))
			done
			;;
		c )	BUILD_COMMAND="$OPTARG";;
		r )	BUILD_CLEANALL=true; BUILD_COMMAND="distclean";;
		j )	BUILD_JOBS=$OPTARG;;
		v )	DBG_VERBOSE=true;;
		D )	DBG_VERBOSE=true; DBG_TRACE=true;;
		o )	BUILD_OPTION="$OPTARG";;
		i ) 	CMD_SHOW_INFO=true;;
		l )	CMD_SHOW_LIST=true;;
		e )	CMD_EDIT=true;
			break;;
		s ) 	setup_stage "$OPTARG";;
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
setup_config "$BUILD_CONFIG_SCRIPT"

if [[ "${CMD_EDIT}" == true ]]; then
	$EDIT_TOOL "$BUILD_CONFIG_SCRIPT"
	exit 0;
fi

parse_env
setup_env "${BUILD_CONFIG_ENV["TOOL"]}"
listup_target

run_build
