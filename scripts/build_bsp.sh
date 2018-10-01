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

#set -x
declare -A BUILD_ENVIRONMENT=(
	["ARCH"]=" "
  	["MACHINE"]=" "
  	["TOOL"]=" "
  	["RESULT"]=" "
)

BUILD_TARGETS=()

declare -A TARGET_COMPONENTS=(
  	["PATH"]=" "	# build path
  	["CONFIG"]=" "	# build default condig (defconfig)
  	["IMAGE"]=" "	# build image
  	["TOOL"]=" "	# cross compiler
  	["OUTPUT"]=" "	# output image to copy, copy after post command
  	["OPTION"]=" "	# build option
  	["PRECMD"]=" "	# pre command before build
  	["POSTCMD"]=" "	# post command after copy done
  	["COPY"]=" "	# copy name to RESULT
  	["JOBS"]=" "	# build jobs number (-j n)
)

function usage() {
	echo -n "Usage: `basename $0` [-f file name]"
	for i in "${BUILD_TARGETS[@]}"
	do
		echo -n "[$i]";
	done
	echo -e " [options] [command]";
	echo "[options]"
	echo "  -i : build info with -f file name"
	echo "  -j : set build jobs"
	echo "  -b : only run build command, run make"
	echo "  -r : only run pre command, run before build (related with PRECMD)"
	echo "  -s : only run post command, run after copy done (related with POSTCMD)"
	echo "  -c : only run copy to result (related with COPY)"
	echo "  -e : open file with vim"
	echo ""
	echo "[command] if not set, build 'IMAGE'"
	echo " defconfig    : set default config"
	echo " menuconfig   : menuconfig "
	echo " clean        : clean"
	echo " distclean    : distclean"
	echo " cleanbuild   : clean and build"
	echo " rebuild      : distclean and defconfig and build"
	echo " ...          : build command supported by target"
}

function parse_build_env() {
	local value=$1	# $1 = store the prefix's value
	local params=("${@}")
	local prefix=("${params[1]}")		# $2 = search prefix
	local separator=("${params[2]}")	# $3 = search separator
	local images=("${params[@]:3}")		# $4 = search array

	for i in "${images[@]}"
	do
		if [[ "$i" = *"$prefix"* ]]; then
			local comp="$(echo $i| cut -d$separator -f 2)"
			comp="$(echo $comp| cut -d',' -f 1)"
			comp="$(echo -e "${comp}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
			eval "$value=(\"${comp}\")"
			break
		fi
	done
}

function parse_build_targets() {
	local value=$1	# $1 = store the value
	local params=("${@}")
	local separator=("${params[1]}") # $2 = search separator
	local images=("${params[@]:2}")	 # $3 = search array

	for i in "${images[@]}"
	do
		local add=true
		local val="$(echo $i| cut -d$separator -f 1)"
		val="$(echo -e "${val}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

		for n in ${!BUILD_ENVIRONMENT[@]}
		do
			if [ "$n" == $val ]; then
				add=false
				break
			fi
		done

		[ $add != true ] && continue;

		eval "${value}+=(\"${val}\")"
	done
}
function parse_prefix_target() {
	local value=$1	# $1 = store the value
	local params=("${@}")
	local prefix=("${params[1]}")	 # $2 = search prefix
	local separator=("${params[2]}") # $3 = search separator
	local images=("${params[@]:3}")	 # $4 = search array

	for i in "${images[@]}"
	do
		if [[ "$i" = *"$prefix"* ]]; then
			#local comp="$(echo $i| cut -d$separator -f 2)"
			local pos=`expr index "$i" $separator`
			if [ $pos -eq 0 ]; then
				return
			fi
			local comp=${i:$pos}
			eval "$value=(\"${comp}\")"
			break
		fi
	done
}

function parse_target_comp() {
	local value=$1	# $1 = store the value
	local prefix=$2
	local separator=$3
	local string=$4

	local pos=`awk -v a="$string" -v b="$prefix" 'BEGIN{print index(a,b)}'`
	if [ $pos -eq 0 ]; then
		return
	fi

	local val=${string:$pos}

	pos=`awk -v a="$val" -v b="$separator" 'BEGIN{print index(a,b)}'`
	val=${val:$pos}

	pos=`awk -v a="$val" -v b="," 'BEGIN{print index(a,b)}'`
	if [ $pos -ne 0 ]; then
		val=${val:0:$pos}
	fi

	if [ `expr "$val" : ".*[*].*"` -eq 0 ]; then
		val="$(echo $val| cut -d',' -f 1)"
	else
		val="$(echo "$val"| cut -d',' -f 1)"
	fi

	eval "$value=(\"${val}\")"
}

function parse_environment() {
	local images=("${@}")	# $1 = search array

	for key in ${!BUILD_ENVIRONMENT[@]}
	do
		local val=""
  		parse_build_env val "$key" "=" "${images[@]}"
		BUILD_ENVIRONMENT[$key]=$val
	done
}

function setup_environment() {
	local tool=$1

	if [ -z $tool ]; then
		return
	fi

	local tool_path=`readlink -e -n "$(dirname "$tool")"`
	if [ -z $tool_path ]; then
		echo -e "\033[47;31m No such 'TOOL': $(dirname "$tool") \033[0m"
		exit 1
	fi

	tool=$(basename $tool)
	export PATH=$tool_path:$PATH
}

function print_environments() {
	echo -e "\n\033[0;33m++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ \033[0m"
	for key in ${!BUILD_ENVIRONMENT[@]}
	do
		if [ -z "${BUILD_ENVIRONMENT[$key]}" ]; then
			continue
		fi
  		echo -e "$key\t: ${BUILD_ENVIRONMENT[$key]}"
	done
	echo -e "\033[0;33m++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ \033[0m"
}

function print_components() {
	echo -e "\n\033[0;31m================================================================== \033[0m"
	echo -e "\033[47;30m $build_target \033[0m"
	for key in ${!TARGET_COMPONENTS[@]}
	do
		if [ -z "${TARGET_COMPONENTS[$key]}" ]; then
			continue
		fi
  		echo -e "$key\t: ${TARGET_COMPONENTS[$key]}"
	done
	echo -e "\033[0;31m================================================================== \033[0m"
}

function fn_copy_target() {
	local out=$2 src=$1/$out
	local dir=$3 dst=$4

	if [ "$(ls $src| wc -l 2>/dev/null)" -eq 0 ]; then
		echo -e "\033[47;31m No such to copy : '$src' ... \033[0m"
		return
	fi

	if [ "$src" == "/" ]; then
		echo -e "\033[47;31m Invalid directory : '$src' ... \033[0m"
		return
	fi

	if [ -z "$out" ]; then
		echo -e "\033[47;31m No 'OUTPUT' ... \033[0m"
		return
	fi

	if [ `expr "$out" : ".*[*].*"` -eq 0 ]; then
		if [ -z "$dst" ]; then
			dst=$dir/$(basename $out)
		else
			dst=$dir/$dst
		fi
	else
		dst=$dir/
	fi

	echo -e "\n\033[2;32m ----------------------------------------------------------------- \033[0m"
	echo -e " COPY     : $src"
	echo -e " TO       : $dst"
	echo -e "\033[1;32m ----------------------------------------------------------------- \033[0m"

	mkdir -p $dir

	if [ ! -d $dir ]; then
		echo -e "\033[47;31m Faild mkdir: '$dir' ... \033[0m"
		return
	fi

	if [ -d "$src" ]; then
		rm -rf $dst
	fi

	local pos=`awk -v a="$src" -v b="[" 'BEGIN{print index(a,b)}'`
	if [ $pos -eq 0 ]; then
		cp -a $src $dst
	fi
}

function fn_parse_target() {
	local params=("${@}")
	local prefix=("${params[0]}")	# $0 = target name for search
	local images=("${params[@]:1}")	# $1 = search array
	local target

	parse_prefix_target target "$prefix" "=" "${images[@]}"

	for key in ${!TARGET_COMPONENTS[@]}
	do
		local comp=""
  		parse_target_comp comp "$key" ":" "$target"
		TARGET_COMPONENTS[$key]=$comp

		if [ "$key" == "PRECMD" ] || [ "$key" == "POSTCMD" ]; then
			continue
		fi

		# remove space
		local pos=`awk -v a="$comp" -v b="[" 'BEGIN{print index(a,b)}'`
		if [ $pos -ne 0 ]; then
			continue
		fi
		TARGET_COMPONENTS[$key]="$(echo "$comp" | sed 's/[[:space:]]//g')"
	done
}

function fn_make_target() {
	local target=$1 cmd=$2
	local path=${TARGET_COMPONENTS["PATH"]}
	local tool=${TARGET_COMPONENTS["TOOL"]}
	local defconfig=${TARGET_COMPONENTS["CONFIG"]}
	local jobs="-j ${TARGET_COMPONENTS["JOBS"]}"
	local option=${TARGET_COMPONENTS["OPTION"]}

	if [ ! -d $path ]; then
		echo -e "\033[47;31m No such to build $target: '$path' ... \033[0m"
		return
	fi

	if [ ! -f "$path/makefile" ] && [ ! -f "$path/Makefile" ]; then
		return
	fi

	if [ $target != "dtb" ]; then
		if [ "$cmd" == "distclean" ] || [ "$cmd" == "rebuild" ]; then
			make -C $path distclean
		fi
	fi

	if [ $target != "dtb" ]; then
		if [ "$cmd" == "clean" ] || [ "$cmd" == "cleanbuild" ] ||
		   [ "$cmd" == "rebuild" ]; then
			make -C $path clean
		fi
	fi

	local mach=${BUILD_ENVIRONMENT["MACHINE"]}
	local arch=${BUILD_ENVIRONMENT["ARCH"]}

	if [ ! -z $defconfig ]; then
		if [ "$cmd" == "defconfig" ] || [ ! -f "$path/.config" ]; then
			make -C $path ARCH=$arch CROSS_COMPILE=$tool $defconfig
			[ $? -ne 0 ] && exit 1;
		fi

		if [ "$cmd" == "menuconfig" ]; then
			make -C $path ARCH=$arch CROSS_COMPILE=$tool menuconfig
			[ $? -ne 0 ] && exit 1;
		fi
	fi

	# exit after excute default build commands
	if [ "$cmd" == "distclean" ] || [ "$cmd" == "clean" ] ||
	   [ "$cmd" == "defconfig" ] || [ "$cmd" == "menuconfig" ]; then
		exit 1; # Exit to skip next build step
	fi

	if [ ! -z "$cmd" ] && [ "$cmd" != "rebuild" ] && [ "$cmd" != "cleanbuild" ] ; then
		jobs="" image="" option=""
	else
		cmd=${TARGET_COMPONENTS["IMAGE"]}
	fi

	make -C $path ARCH=$arch CROSS_COMPILE=$tool $cmd $option $jobs
}

function fn_build_target() {
	local target=$1 command=$2

	fn_parse_target "$target" "${BUILD_IMAGES[@]}"

	if [ -z ${TARGET_COMPONENTS["TOOL"]} ]; then
		TARGET_COMPONENTS["TOOL"]=${BUILD_ENVIRONMENT["TOOL"]}
	fi

	if [ -z ${TARGET_COMPONENTS["JOBS"]} ]; then
		TARGET_COMPONENTS["JOBS"]=$build_jobs
	fi

	print_components

	if [ $show_info == true ]; then
		return
	fi

	if [ $run_prev_cmd == true ] && [ ! -z "${TARGET_COMPONENTS["PRECMD"]}" ]; then
		echo -e "\033[47;34m PRECMD : ${TARGET_COMPONENTS["PRECMD"]} \033[0m"
		bash -c "${TARGET_COMPONENTS["PRECMD"]}"
		[ $? -ne 0 ] && exit 1;
		echo -e "\033[47;32m PRECMD : DONE \033[0m"
	fi

	if [ $run_make_cmd == true ]; then
		fn_make_target "$target" "$command"
		[ $? -ne 0 ] && exit 1;
	fi

	if [ $run_copy_ret == true ]; then
		local path=${TARGET_COMPONENTS["PATH"]} out=${TARGET_COMPONENTS["OUTPUT"]}
		local dir=${BUILD_ENVIRONMENT["RESULT"]} ret=${TARGET_COMPONENTS["COPY"]}

		if [ ! -z "$out" ]; then
			fn_copy_target "$path" "$out" "$dir" "$ret"
			[ $? -ne 0 ] && exit 1;
		fi
	fi

	if [ $run_post_cmd == true ] && [ ! -z "${TARGET_COMPONENTS["POSTCMD"]}" ]; then
		echo -e "\033[47;34m POSTCMD: ${TARGET_COMPONENTS["POSTCMD"]} \033[0m"
		bash -c "${TARGET_COMPONENTS["POSTCMD"]}"
		[ $? -ne 0 ] && exit 1;
		echo -e "\033[47;32m POSTCMD: DONE \033[0m"
	fi
}

case "$1" in
	-f )
		build_file=$2
		build_targets=()
		build_command=""
		build_jobs=`grep processor /proc/cpuinfo | wc -l`

		show_info=false
		edit_file=false

		run_make_cmd=false
		run_prev_cmd=false
		run_post_cmd=false
		run_copy_ret=false

		if [ ! -f $build_file ]; then
			echo "No such file to build config: $build_file"
			echo -e "\033[47;31m No such to build config: $build_file \033[0m"
			exit 1;
		fi

		# include input file
		. $build_file

		parse_build_targets BUILD_TARGETS "=" "${BUILD_IMAGES[@]}"

		while [ "$#" -gt 2 ]; do
			# argc: bl1,bl2,bl32,uboot,kernel,dtb,br2
			for i in "${BUILD_TARGETS[@]}"
			do
				if [ "$i" == "$3" ]; then
					build_targets+=("$i");
					shift 1
					continue
				fi
			done

			case "$3" in
			-j )	build_jobs=$4; shift 2;; # get jobs
			-i ) 	show_info=true; shift 1;;
			-b )	run_make_cmd=true; shift 1;;
			-r ) 	run_prev_cmd=true; shift 1;;
			-s ) 	run_post_cmd=true; shift 1;;
			-c )	run_copy_ret=true; shift 1;;
			-e ) 	edit_file=true; break; shift 1;;
			-h )	usage;	exit 1;;
			*)	[ ! -z $3 ] && build_command=$3;
				shift;;
			esac
		done

		if [ $edit_file == true ]; then
			vim $build_file
			exit 0;
		fi

		if [ $run_make_cmd == false ] &&
		   [ $run_copy_ret == false ] &&
		   [ $run_prev_cmd == false ] &&
		   [ $run_post_cmd == false ]; then
			run_make_cmd=true
			run_copy_ret=true
			run_prev_cmd=true
			run_post_cmd=true
		fi

		# build all
		if [ ${#build_targets} -eq 0 ]; then
			build_targets=(${BUILD_TARGETS[@]})
		fi

		# parse environment
		parse_environment "${BUILD_IMAGES[@]}"
		setup_environment ${BUILD_ENVIRONMENT["TOOL"]}

		if [ $show_info == true ]; then
			print_environments
		fi

		# build
		for i in "${build_targets[@]}"
		do
			build_target=$i
			fn_build_target "$build_target" "$build_command"
		done
		;;

	-h | * )
		usage;
		exit 1
		;;
esac

unset BUILD_ENVIRONMENT
unset TARGET_COMPONENTS
