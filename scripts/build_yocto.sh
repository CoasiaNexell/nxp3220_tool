#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>

ROOT_DIR=`readlink -e -n "$(cd "$(dirname "$0")" && pwd)/../.."`

MACHINE_TYPE=$1
IMAGE_TYPE=$2

# path
YOCTO_DIR=$ROOT_DIR/yocto
POKY_DIR=$ROOT_DIR/yocto/poky
BUILD_DIR=$ROOT_DIR/yocto/build
META_DIR=$YOCTO_DIR/meta-nexell/meta-nxp3220
RESULT_DIR=$ROOT_DIR/yocto/out
RESULT_OUT=

# related machine
MACHINE_DIR=$META_DIR/conf/machine
IMAGE_DIR=$META_DIR/recipes-core/images

BB_CONF_DIR=$META_DIR/tools/configs/machines
BB_IMAGE_DIR=$META_DIR/tools/configs/images
BB_BUILD_DIR=$BUILD_DIR/build-$MACHINE_TYPE

declare -A BSP_PATH=(
	["BSP_ROOT_DIR"]="$ROOT_DIR"
)

declare -A BUILD_TARGETS=(
  	["bl1"]="bl1-nxp3220"
  	["bl2"]="bl2-nxp3220"
  	["bl32"]="bl32-nxp3220"
  	["uboot"]="virtual/bootloader"
  	["kernel"]="virtual/kernel"
  	["bootimg"]="nexell-bootimg"
  	["dataimg"]="nexell-dataimg"
)

declare -A BUILD_COMMANDS=(
  	["clean"]="buildclean"
  	["distclean"]="cleansstate"
  	["cleanall"]="cleanall"
  	["menuconfig"]="menuconfig"
  	["savedefconfig"]="savedefconfig"
)

declare -A RESULT_TARGETS=(
  	["bl1"]="bl1-nxp3220.*"
  	["bl2"]="bl2*"
  	["bl32"]="bl32.*"
  	["u-boot"]="u-boot*"
  	["env"]="params_env.*"
  	["boot"]="boot/"
  	["bootimg"]="boot.img"
  	["rootfsimg"]="rootfs.img"
  	["dataimg"]="userdata.img"
)

function err() {
	echo  -e "\033[0;31m $@\033[0m"
}

function msg() {
	echo  -e "\033[0;33m $@\033[0m"
}

MACHINE_TABLE=""
IMAGE_TABLE=""
IMAGE_CONF_TABLE=""

function get_avail_types () {
	local dir=$1 sep=$2 table=$3 val
	[ ! -d $dir ] && return;

	cd $dir
	local value=$(find ./ -print \
		2> >(grep -v 'No such file or directory' >&2) | \
		grep -w ".*\.${sep}" | sort)

	for i in $value; do
		i="$(echo "$i" | cut -d'/' -f2)"
		if [ ! -z $(echo "$i" | awk -F".${sep}" '{print $2}') ]; then
			continue
		fi
		val="${val} $(echo "$i" | awk -F".${sep}" '{print $1}')"
		eval "$table=(\"${val}\")"
	done
}

function check_machine_type () {
	local mach=$1
	for i in ${MACHINE_TABLE}; do
		if [ "${i}" == "${mach}" ]; then
			return
		fi
	done

	err "Unknown Machine: $mach"
	err "Availiable: ${MACHINE_TABLE}"
	usage
	exit 1;
}

function check_image_type () {
	local image=$1
	for i in ${IMAGE_TABLE}; do
		if [ "${i}" == "${image}" ]; then
			return
		fi
	done

	err "Unknown Image type: $image"
	err "Availiable: ${IMAGE_TABLE}"
	usage
	exit 1;
}

function check_image_config () {
	local cfg=$1
	[ -z $cfg ] && return;

	for i in ${IMAGE_CONF_TABLE}; do
		if [ "${i}" == "${cfg}" ]; then
			return
		fi
	done

	err "Unknown Image config: $cfg"
	err "Availiable: ${IMAGE_CONF_TABLE}"
	usage
	exit 1;
}

function merge_conf_file () {
	local src=$1 cmp=$2 dst=$3
	while IFS=$'\t' read -r i;
        do
                merged=false
                while IFS=$'\t' read -r n;
                do
			if [ -z "$n" ]; then
				break;
			fi

			if [ "${i:0:1}" = "#" ]; then
				merged=true
				break;
			fi

			case "$i" in
				*BBMASK* | *_append*)
					break;;
				--)
					;;
			esac

			vi="$(echo "$(echo $i | cut -d'=' -f 1)" | cut -d' ' -f 1)"
			vn="$(echo "$(echo $n | cut -d'=' -f 1)" | cut -d' ' -f 1)"
                        if [ "$vi" == "$vn" ]; then
                                sed -i "s/$n/$i/" $dst
                                merged=true
                                break;
                        fi
                done < $src

                if [ $merged == false ] && [ "${i:0:1}" != "#" ]; then
                	echo "$i" >> $dst;
                fi
        done < $cmp
}

# overwrite to build_<machine>/conf/local.conf
function parse_machine_confing () {
        local cmp=$BB_CONF_DIR/$MACHINE_TYPE.conf
	local src=$BB_CONF_DIR/local.conf dst=$BB_BUILD_DIR/conf/local.conf

        cp $src $dst
	[ $? -ne 0 ] && exit 1;

	if [ ! -f $cmp ]; then
		replace="\"$MACHINE_TYPE\""
		sed -i "s/.*MACHINE.*/MACHINE = $replace/" $dst
		return
	fi

        msg "-----------------------------------------------------------------"
	msg " PARSE    : $src"
	msg " PATCH    : $cmp"
	msg " TO       : $dst"
        msg "-----------------------------------------------------------------"

	merge_conf_file $src $cmp $dst

	echo "" >> $dst
	for i in ${!BSP_PATH[@]}
	do
		prefix="$i"
		replace="\"${BSP_PATH[$i]//\//\\/}\""
		sed -i "s/.*$prefix =.*/$prefix = $replace/" $dst
	done
}

function parse_image_config () {
        local dst=$BB_BUILD_DIR/conf/local.conf
	local type=${IMAGE_TYPE##*-} conf=$OPT_IMAGE_CONF

	for i in $BB_IMAGE_DIR/$type.conf $BB_IMAGE_DIR/$conf.conf
	do
		[ ! -f $i ] && continue;
        	msg "-----------------------------------------------------------------"
		msg " PARSE    : $i"
		msg " TO       : $dst"
        	msg "-----------------------------------------------------------------"

		merge_conf_file $dst $i $dst
        done
}

function parse_image_type () {
	local dst=$BB_BUILD_DIR/conf/local.conf
	replace="\"$IMAGE_TYPE\""
	sed -i "s/.*INITRAMFS_IMAGE.*/INITRAMFS_IMAGE = $replace/" $dst
}

function parse_machine_jobs () {
	if [ -z $OPT_BUILD_JOBS ]; then
		return
	fi

	local file=$BB_BUILD_DIR/conf/local.conf
	if grep -q BB_NUMBER_THREADS "$file"; then
		replace="\"$OPT_BUILD_JOBS\""
		sed -i "s/.*BB_NUMBER_THREADS.*/BB_NUMBER_THREADS = $replace/" $file
	else
		echo "" >> $BB_BUILD_DIR/conf/local.conf
		echo "BB_NUMBER_THREADS = \"${OPT_BUILD_JOBS}\"" >> $file
	fi
}

function parse_bblayer_config () {
	local src=$BB_CONF_DIR/$MACHINE_TYPE.bblayers
        local dst=$BB_BUILD_DIR/conf/bblayers.conf

	if [ ! -f $src ]; then
        	src=$BB_CONF_DIR/bblayers.conf
        fi

        msg "-----------------------------------------------------------------"
	msg " COPY     : $src"
	msg " TO       : $dst"
        msg "-----------------------------------------------------------------"

        cp $src $dst
	[ $? -ne 0 ] && exit 1;

	replace="\"${YOCTO_DIR//\//\\/}\""
	sed -i "s/.*BSPPATH :=.*/BSPPATH := $replace/" $dst
}

function setup_bitbake_env () {
	mkdir -p $BUILD_DIR

	# run oe-init-build-env
	source $POKY_DIR/oe-init-build-env $BB_BUILD_DIR >/dev/null 2>&1
	msg "-----------------------------------------------------------------"
	msg " bitbake environment set up command:"
	msg " $> source $POKY_DIR/oe-init-build-env $BB_BUILD_DIR"
	msg "-----------------------------------------------------------------"
}

function check_bitbake_env () {
        local mach=$MACHINE_TYPE
	local conf=$BB_BUILD_DIR/conf/local.conf

        if [ ! -f $conf ]; then
                err "Not build setup environment : '$conf' ..."
                err "$> source poky/oe-init-build-env <build dir>/<machin type>"
		exit 1;
	fi

        v="$(echo $(find $conf -type f -exec grep -w -h 'MACHINE' {} \;) | cut -d'"' -f 2)"
        v="$(echo $v | cut -d'"' -f 1)"
        if [ "$mach" == "$v" ]; then
        	msg "PARSE: Already done '$conf'"
        	return 0
        fi
        return 1
}

function print_avail_lists () {
	msg "================================================================="
	msg "Support Lists:"
	msg "================================================================="

	msg "MACHINE: <machine name>"
	msg "\t:$MACHINE_DIR"
	msg "\t:$BB_CONF_DIR"
	msg "\t----------------------------------------------------------"
	msg "\t${MACHINE_TABLE}"
	msg "\t----------------------------------------------------------"

	msg "IMAGE TYPE: <image type>"
	msg "\t:$IMAGE_DIR"
	msg "\t----------------------------------------------------------"
	msg "\t ${IMAGE_TABLE}"
	msg "\t----------------------------------------------------------"

	msg "IMAGE CONFIG: '-i'"
	msg "\t:$BB_IMAGE_DIR"
	msg "\t----------------------------------------------------------"
	msg "\t ${IMAGE_CONF_TABLE}"
	msg "\t----------------------------------------------------------"

	msg "TARGETs: '-t'"
	for i in "${!BUILD_TARGETS[@]}"; do
		msg "\t$i (${BUILD_TARGETS[$i]})"
	done
	msg "COMMANDs: '-c'"
	for i in "${!BUILD_COMMANDS[@]}"; do
		msg "\t$i (${BUILD_COMMANDS[$i]})"
	done
}

function copy_deploy_images () {
	local result deploy=$BB_BUILD_DIR/tmp/deploy/images/$MACHINE_TYPE

	if [ ! -d $deploy ]; then
		err "No directory : $deploy"
		exit 1
	fi

	result="$(echo $IMAGE_TYPE | cut -d'.' -f 1)"
	RESULT_OUT=result-$MACHINE_TYPE-${result##*-}
	result=$RESULT_DIR/$RESULT_OUT

	msg "-----------------------------------------------------------------"
	msg " DEPLOY     : $deploy"
	msg " RESULT     : $result"
	msg "-----------------------------------------------------------------"

	mkdir -p $result
	[ $? -ne 0 ] && exit 1;

	for i in "${!RESULT_TARGETS[@]}"
	do
		local file=$deploy/${RESULT_TARGETS[$i]}
		local files=$(find $file -print \
			2> >(grep -v 'No such file or directory' >&2) | sort)

		to=$result
		for n in $files; do
			name=$(basename $n)
			if [ -d "$n" ]; then
				mkdir -p $result/$name
				to=$to/$name
				continue
			fi

			if [ -f $to/$name ]; then
				ts="$(stat --printf=%y $n | cut -d. -f1)"
				td="$(stat --printf=%y $to/$name | cut -d. -f1)"
				[ "${ts}" == "${td}" ] && continue;
			fi
			cp -a $n $to/$name
		done
	done
}

function copy_sdk_images () {
	local dir sdk=$BB_BUILD_DIR/tmp/deploy/sdk

	if [ ! -d $sdk ]; then
		err "No directory : $sdk"
		exit 1
	fi

	dir="$(echo $IMAGE_TYPE | cut -d'.' -f 1)"
	RESULT_OUT=SDK-result-$MACHINE_TYPE-${dir##*-}
	dir=$RESULT_DIR/$RESULT_OUT

	mkdir -p $dir
	[ $? -ne 0 ] && exit 1;

	cp -a $sdk/* $dir/
}

function link_result_dir () {
	link=$1
	if [ -e $RESULT_DIR/$link ]; then
		rm -f $RESULT_DIR/$link
	fi

	cd $RESULT_DIR
	ln -s $RESULT_OUT $link
}

function usage () {
	echo "Usage: `basename $0` <machine name> <image type> [options]"
	echo ""
	echo "[options]"
	echo "  -l : show available lists (machine/images/targets/commands ...)"
	echo "  -t : select build target"
	echo "  -i : select image config"
	echo "  -c : build commands"
	echo "  -o : bitbake option"
	echo "  -S : sdk create"
	echo "  -f : force overwrite buid confing files (local.conf/bblayers.conf)"
	echo "  -j : determines how many tasks bitbake should run in parallel"
	echo "  -h : help"
	echo ""
	print_avail_lists
	exit 1;
}

OPT_BUILD_PARSE=false
OPT_BUILD_OPTION=""
OPT_BUILD_SDK=false
OPT_IMAGE_CONF=
OPT_BUILD_JOBS=

BB_TARGET=""
BB_BUILD_CMD=""

function parse_args () {
    	ARGS=$(getopt -o lSfht:i:c:o:j: -- "$@");
    	eval set -- "$ARGS";

    	while true; do
		case "$1" in
		-l )
			print_avail_lists; exit 0;;
		-t )
			for i in ${!BUILD_TARGETS[@]}; do
				[ $i != $2 ] && continue;
				BB_TARGET=${BUILD_TARGETS[$i]}; shift 2; break;
			done
			if [ -z $BB_TARGET ]; then
				err "Available Targets:"
				for i in "${!BUILD_TARGETS[@]}"; do
					err "\t$i\t: ${BUILD_TARGETS[$i]}"
				done
				exit 1;
			fi
			;;
		-c )
			for i in ${!BUILD_COMMANDS[@]}; do
				[ $i != $2 ] && continue;
				BB_BUILD_CMD="-c ${BUILD_COMMANDS[$i]}"; shift 2; break;
			done
			if [ -z "${BB_BUILD_CMD}" ]; then
				err "Available Targets:"
				for i in "${!BUILD_COMMANDS[@]}"; do
					err "\t$i\t: ${BUILD_COMMANDS[$i]}"
				done
				exit 1;
			fi
			;;
		-i )	OPT_IMAGE_CONF=$2; shift 2;;
		-o )	OPT_BUILD_OPTION=$2; shift 2;;
		-S )	OPT_BUILD_SDK=true; shift 1;;
		-f )	OPT_BUILD_PARSE=true; shift 1;;
		-j )	OPT_BUILD_JOBS=$2; shift 2;;
		-h )	usage;	exit 1;;
		-- ) 	break ;;
		esac
	done
}

###############################################################################
# start commands
###############################################################################
get_avail_types $MACHINE_DIR "conf" MACHINE_TABLE
get_avail_types $IMAGE_DIR "bb" IMAGE_TABLE
get_avail_types $BB_IMAGE_DIR "conf" IMAGE_CONF_TABLE

parse_args $@

check_machine_type $MACHINE_TYPE
check_image_type $IMAGE_TYPE
check_image_config $OPT_IMAGE_CONF

setup_bitbake_env
check_bitbake_env
NEED_PARSE=$?

if [ $NEED_PARSE == 1 ] || [ $OPT_BUILD_PARSE == true ]; then
	parse_machine_confing
	parse_image_config
	parse_bblayer_config
fi

parse_image_type
parse_machine_jobs

msg "-----------------------------------------------------------------"
msg " MACHINE    : $MACHINE_TYPE"
msg " IMAGE      : $IMAGE_TYPE"
msg " IMAGE CONF : $OPT_IMAGE_CONF"
msg " TARGET     : $BB_TARGET"
msg " COMMAND    : $BB_BUILD_CMD"
msg " OPTION     : $OPT_BUILD_OPTION"
msg " SDK        : $OPT_BUILD_SDK ($BB_BUILD_DIR/tmp/deploy/sdk)"
msg " BUILD DIR  : $BB_BUILD_DIR"
msg " DEPLOY DIR : $BB_BUILD_DIR/tmp/deploy/images/$MACHINE_TYPE"
msg "-----------------------------------------------------------------"

if [ $OPT_BUILD_SDK != true ]; then
	if [ ! -z $BB_TARGET ]; then
		bitbake $BB_TARGET $BB_BUILD_CMD $OPT_BUILD_OPTION
	else
		# not support buildclean for image type
		if [ "${BB_BUILD_CMD}" == "-c buildclean" ]; then
			BB_BUILD_CMD="-c cleanall"
		fi
		bitbake $IMAGE_TYPE $BB_BUILD_CMD $OPT_BUILD_OPTION
		[ $? -ne 0 ] && exit 1;
	fi

	if [ -z "${BB_BUILD_CMD}" ]; then
		copy_deploy_images
		link_result_dir "result"
	fi
else
	bitbake -c populate_sdk $IMAGE_TYPE $OPT_BUILD_OPTION
	[ $? -ne 0 ] && exit 1;
	copy_sdk_images
	link_result_dir "SDK"
fi

msg "-----------------------------------------------------------------"
msg " RESULT DIR : $RESULT_OUT"
msg "-----------------------------------------------------------------"
msg "-----------------------------------------------------------------"
msg " Sparse image to ext4 image:"
msg " $> simg2img <img>.img <img>.ext4"
msg ""
msg " Bitbake environment set up command:"
msg " $> source $POKY_DIR/oe-init-build-env $BB_BUILD_DIR"
msg "-----------------------------------------------------------------"
