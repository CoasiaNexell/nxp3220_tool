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

#set -x
declare -A BUILD_ENVIRONMENT=(
	["ARCH"]=" "
  	["MACHINE"]=" "
  	["TOOL"]=" "
  	["RESULT"]=" "
)

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

BUILD_TARGETS=()

function usage() {
	echo -n "Usage: `basename $0` [-f file]"
	for i in "${BUILD_TARGETS[@]}"
	do
		echo -n "[$i]";
	done
	echo -e " [options] [command]";
	echo "[options]"
	echo "  -i : show build command info"
	echo "  -l : listup build targets"
	echo "  -j : set build jobs"
	echo "  -m : run make"
	echo "  -p : run pre command, before make (related with PRECMD)"
	echo "  -s : run post command, after done (related with POSTCMD)"
	echo "  -c : run copy to result (related with COPY)"
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

function get_build_env() {
	local ret=$1 prefix=$2 sep=$3
	local -n array=$4

	for i in "${array[@]}"
	do
		if [[ "$i" = *"$prefix"* ]]; then
			local comp="$(echo $i| cut -d$sep -f 2)"
			comp="$(echo $comp| cut -d',' -f 1)"
			comp="$(echo -e "${comp}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
			eval "$ret=(\"${comp}\")"
			break
		fi
	done
}

function get_build_targets() {
	local ret=$1 sep=$2
	local -n array=$3

	for i in "${array[@]}"
	do
		local add=true
		local val="$(echo $i| cut -d$sep -f 1)"
		val="$(echo -e "${val}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

		# skip buil environments"
		for n in ${!BUILD_ENVIRONMENT[@]}
		do
			if [ "$n" == $val ]; then
				add=false
				break
			fi
			[ $? -ne 0 ] && exit 1;
		done

		[ $add != true ] && continue;

		if [[ "$i" == *"="* ]];then
			eval "${ret}+=(\"${val}\")"
		fi
	done
}

function get_target_prefix() {
	local ret=$1 prefix=$2 sep=$3
	local -n array=$4

	for i in "${array[@]}"
	do
		if [[ "$i" = *"$prefix"* ]]; then
			local comp="$(echo $(echo $i| cut -d$sep -f 1) | cut -d' ' -f 1)"
			if [ "$prefix" != "$comp" ]; then
				continue
			fi
			local pos=`expr index "$i" $sep`
			if [ $pos -eq 0 ]; then
				return
			fi
			comp=${i:$pos}
			eval "$ret=(\"${comp}\")"
			break
		fi
	done
}

function get_target_comp() {
	local ret=$1 prefix=$2 sep=$3
	local string=$4

	local pos=`awk -v a="$string" -v b="$prefix" 'BEGIN{print index(a,b)}'`
	if [ $pos -eq 0 ]; then
		return
	fi

	local val=${string:$pos}

	pos=`awk -v a="$val" -v b="$sep" 'BEGIN{print index(a,b)}'`
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

	eval "$ret=(\"${val}\")"
}

function parse_environment() {
	local image=("${@}")	# $1 = search array

	for key in ${!BUILD_ENVIRONMENT[@]}
	do
		local val=""
		get_build_env val "$key" "=" image
		BUILD_ENVIRONMENT[$key]=$val
	done

	if [[ -n ${BUILD_ENVIRONMENT["RESULT"]} ]]; then
                mkdir -p ${BUILD_ENVIRONMENT["RESULT"]}
	fi
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
	local target=$1
	echo -e "\n\033[0;33m================================================================== \033[0m"
	echo -e "\033[0;33m $target \033[0m"
	echo -e ""
	for key in ${!TARGET_COMPONENTS[@]}
	do
		if [ -z "${TARGET_COMPONENTS[$key]}" ]; then
			continue
		fi
		if [ $key == "PATH" ]; then
			echo -e "$key\t: `realpath ${TARGET_COMPONENTS[$key]}`"
		else
			echo -e "$key\t: ${TARGET_COMPONENTS[$key]}"
		fi
	done
	echo -e "\033[0;33m================================================================== \033[0m"
}

function setup_path() {
	if [[ -z $1 ]]; then
		return
	fi

	local path=`readlink -e -n "$(dirname "$1")"`
	if [[ -z $path ]]; then
		echo -e "\033[47;31m No such 'TOOL': $(dirname "$1") \033[0m"
		exit 1
	fi

	export PATH=$path:$PATH
}

function copy_target() {
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
		if [ ! -z $dst ]; then
			dst=$dir/$dst
		else
			dst=$dir/
		fi
	fi

	echo -e "\n\033[2;32m ----------------------------------------------------------------- \033[0m"
	echo -e " COPY     : `realpath $src`"
	echo -e " TO       : `realpath $dst`"
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

function parse_target() {
	local prefix=$1 target
	local -n image=$2

	get_target_prefix target "$prefix" "=" image

	for key in ${!TARGET_COMPONENTS[@]}
	do
		local comp=""
		get_target_comp comp "$key" ":" "$target"
		TARGET_COMPONENTS[$key]=$comp

		if [ "$key" == "PRECMD" ] || [ "$key" == "POSTCMD" ] ||
			[ "$key" == "OPTION" ]; then
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

function make_target() {
	local target=$1 cmd=$2
	local tool=${TARGET_COMPONENTS["TOOL"]}
	local path=${TARGET_COMPONENTS["PATH"]}
	local image=${TARGET_COMPONENTS["IMAGE"]}
	local defconfig=${TARGET_COMPONENTS["CONFIG"]}
	local jobs="-j ${TARGET_COMPONENTS["JOBS"]}"
	local option=${TARGET_COMPONENTS["OPTION"]}

	if [[ -z $path ]]; then
		return
	fi

	path=`realpath ${TARGET_COMPONENTS["PATH"]}`

	if [[ ! -d $path ]]; then
		echo -e "\033[47;31m Invalid 'PATH' $target: '$path' ... \033[0m"
		exit 1;
	fi

	if [ ! -f "$path/makefile" ] && [ ! -f "$path/Makefile" ]; then
		echo -e "\033[47;31m Not found Makefile $target: '$path' ... \033[0m"
		return;
	fi

	if [[ $image != *".dtb"* ]]; then
		if [ "$cmd" == "distclean" ] || [ "$cmd" == "rebuild" ]; then
			make -C $path distclean
		fi

		if [ "$cmd" == "clean" ] || [ "$cmd" == "cleanbuild" ] ||
		   [ "$cmd" == "rebuild" ]; then
			make -C $path clean
		fi

		if  [ "$cmd" == "rebuild" ] || [ "$cmd" == "cleanbuild" ] &&
		    [ ! -z "${TARGET_COMPONENTS["PRECMD"]}" ]; then
			local exec=${TARGET_COMPONENTS["PRECMD"]}
			echo -e "\033[47;34m PRECMD : ${exec} \033[0m"
			if type "${exec}" 2>/dev/null | grep -q 'function'; then
				${exec}
			else
				bash -c "${exec}"
			fi
			[ $? -ne 0 ] && exit 1;
			echo -e "\033[47;34m PRECMD : DONE \033[0m"
		fi
	fi

	# exit after excute default build commands
	if [ "$cmd" == "distclean" ] || [ "$cmd" == "clean" ]; then
		exit 1; # Exit to skip next build step
	fi

	local mach=${BUILD_ENVIRONMENT["MACHINE"]}
	local arch=${BUILD_ENVIRONMENT["ARCH"]}

	if [ ! -z $defconfig ]; then

		setup_path $tool

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
		jobs="" option=""
	else
		cmd=${TARGET_COMPONENTS["IMAGE"]}
	fi

	echo -e "\n\033[0;33m------------------------------------------------------------------ \033[0m"
	echo -e "make -C $path ARCH=$arch CROSS_COMPILE=$tool $cmd $option $jobs"
	echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"

	make -C $path ARCH=$arch CROSS_COMPILE=$tool $cmd $option $jobs
}

function build_target() {
	local target=$1 command=$2

	parse_target "$target" BUILD_IMAGES

	if [ -z ${TARGET_COMPONENTS["TOOL"]} ]; then
		TARGET_COMPONENTS["TOOL"]=${BUILD_ENVIRONMENT["TOOL"]}
	fi

	if [ -z ${TARGET_COMPONENTS["JOBS"]} ]; then
		TARGET_COMPONENTS["JOBS"]=$BUILD_OPT_JOBS
	fi

	print_components $target

	if [ $BUILD_OPT_INFO == true ]; then
		return
	fi

	mkdir -p ${BUILD_ENVIRONMENT["RESULT"]}

	if [ $BUILD_OPT_PRECMD == true ] && [ ! -z "${TARGET_COMPONENTS["PRECMD"]}" ]; then
		local exec=${TARGET_COMPONENTS["PRECMD"]}
		echo -e "\033[47;34m PRECMD : ${exec} \033[0m"
		if type "${exec}" 2>/dev/null | grep -q 'function'; then
			${exec}
		else
			bash -c "${exec}"
		fi
		[ $? -ne 0 ] && exit 1;
		echo -e "\033[47;34m PRECMD : DONE \033[0m"
	fi

	if [ $BUILD_OPT_MAKE == true ]; then
		make_target "$target" "$command"
		[ $? -ne 0 ] && exit 1;
	fi


	if [ $BUILD_OPT_COPY == true ]; then
		local path=${TARGET_COMPONENTS["PATH"]} out=${TARGET_COMPONENTS["OUTPUT"]}
		local dir=${BUILD_ENVIRONMENT["RESULT"]} ret=${TARGET_COMPONENTS["COPY"]}

		if [ ! -z "$out" ]; then
			copy_target "$path" "$out" "$dir" "$ret"
			[ $? -ne 0 ] && exit 1;
		fi
	fi

	if [ $BUILD_OPT_POSTCMD == true ] && [ ! -z "${TARGET_COMPONENTS["POSTCMD"]}" ]; then
		local exec=${TARGET_COMPONENTS["POSTCMD"]}
		echo -e "\033[47;34m POSTCMD: ${exec} \033[0m"
		if type "${exec}" 2>/dev/null | grep -q 'function'; then
			${exec}
		else
			bash -c "${exec}"
		fi
		[ $? -ne 0 ] && exit 1;
		echo -e "\033[47;34m POSTCMD: DONE \033[0m"
	fi
}

BUILD_OPT_JOBS=`grep processor /proc/cpuinfo | wc -l`
BUILD_OPT_INFO=false
BUILD_OPT_MAKE=false
BUILD_OPT_PRECMD=false
BUILD_OPT_POSTCMD=false
BUILD_OPT_COPY=false

case "$1" in
	-f )
		bsp_file=$2
		bsp_targets=()
		command=""
		dump_lists=false

		if [ ! -f $bsp_file ]; then
			echo -e "\033[47;31m Not found build config: $bsp_file \033[0m"
			exit 1;
		fi

		# include input file
		source $bsp_file

		get_build_targets BUILD_TARGETS "=" BUILD_IMAGES

		while [ "$#" -gt 2 ]; do
			count=0
			while true
			do
				if [ "${BUILD_TARGETS[$count]}" == "$3" ]; then
					bsp_targets+=("${BUILD_TARGETS[$count]}");
					((count=0))
					shift 1
					continue
				fi
				((count++))
				[ $count -ge ${#BUILD_TARGETS[@]} ] && break;
			done

			case "$3" in
			-l )	dump_lists=true; shift 2;;
			-j )	BUILD_OPT_JOBS=$4; shift 2;;
			-i ) 	BUILD_OPT_INFO=true; shift 1;;
			-m )	BUILD_OPT_MAKE=true; shift 1;;
			-p ) 	BUILD_OPT_PRECMD=true; shift 1;;
			-s ) 	BUILD_OPT_POSTCMD=true; shift 1;;
			-c )	BUILD_OPT_COPY=true; shift 1;;
			-e )
				vim $bsp_file
				exit 0;;
			-h )	usage;	exit 1;;
			*)	[[ ! -z $3 ]] && command=$3;
				shift;;
			esac
		done

		if [ ${#bsp_targets[@]} -eq 0 ] && [ ! -z $command ]; then
			if [ "$command" != "clean" ] &&
			   [ "$command" != "cleanbuild" ] &&
			   [ "$command" != "rebuild" ]; then
				echo -e "\033[47;31m Unknown target or command: $command ... \033[0m"
				echo -e " Check command : clean, cleanbuild, rebuild"
				echo -en " Check targets : "
				for i in "${BUILD_TARGETS[@]}"
				do
					echo -n "$i "
				done
				echo ""
				exit 1;
			fi
		fi

		if [ $BUILD_OPT_MAKE == false ] &&
		   [ $BUILD_OPT_COPY == false ] &&
		   [ $BUILD_OPT_PRECMD == false ] &&
		   [ $BUILD_OPT_POSTCMD == false ]; then
			BUILD_OPT_MAKE=true
			BUILD_OPT_COPY=true
			BUILD_OPT_PRECMD=true
			BUILD_OPT_POSTCMD=true
		fi

		# build all
		if [ ${#bsp_targets[@]} -eq 0 ]; then
			bsp_targets=(${BUILD_TARGETS[@]})
		fi

		# parse environment
		parse_environment "${BUILD_IMAGES[@]}"
		setup_path ${BUILD_ENVIRONMENT["TOOL"]}

		if [ $dump_lists == true ]; then
			echo -e "\033[0;33m------------------------------------------------------------------ \033[0m"
			echo -en "\033[47;30m Build targets: \033[0m"
			for i in "${BUILD_TARGETS[@]}"
			do
				echo -n " $i"
			done
			echo -e "\n\033[0;33m------------------------------------------------------------------ \033[0m"
			exit 0;
		fi

		if [ $BUILD_OPT_INFO == true ]; then
			print_environments
		fi

		# build
		for i in "${bsp_targets[@]}"
		do
			build_target "$i" "$command"
		done
		;;

	-h | * )
		usage;
		exit 1
		;;
esac
