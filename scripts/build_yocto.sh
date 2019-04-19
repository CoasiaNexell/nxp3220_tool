#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>
#
# $> build_yocto.sh <machine-board> <image> [options]
#

BSP_ROOT_DIR=`readlink -e -n "$(cd "$(dirname "$0")" && pwd)/../.."`
BSP_YOCTO_DIR=$BSP_ROOT_DIR/yocto

# Input arguments
TARGET_NAME=$1
IMAGE_NAME=$2
MACHINE_NAME=${TARGET_NAME%-*}

# Set path
POKY_DIR=$BSP_YOCTO_DIR/poky
META_DIR=$BSP_YOCTO_DIR/meta-nexell/meta-nxp3220
IMAGE_DIR=$META_DIR/recipes-core/images
BUILD_DIR=$BSP_YOCTO_DIR/build/build-$TARGET_NAME
RESULT_DIR=$BSP_YOCTO_DIR/out
RESULT_OUT=

MACHINE_SUPPORT=( "nxp3220" )

# Configure file path for available lists
TARGET_CONF_DIR=$META_DIR/tools/configs/machines
IMAGE_CONF_DIR=$META_DIR/tools/configs/images

# Parse to local.conf
declare -A LOCAL_CONF_VALUES=(
	["BSP_ROOT_DIR"]="$BSP_ROOT_DIR"
)

# Copy from deploy to result dir
RESULT_FILES=(
	"bl1-nxp3220.bin.raw"
	"bl1-nxp3220.bin.enc.raw"
	"bl2.bin.raw"
	"bl32.bin.raw"
	"bl32.bin.enc.raw"
	"u-boot-${MACHINE_NAME}-1.0-r0.bin"
	"u-boot.bin"
	"u-boot.bin.raw"
	"params_env.*"
	"boot/"
	"boot.img"
	"rootfs.img"
	"userdata.img"
)

# Copy from BSP tools to result dir
TOOLS_FILES=(
	"tools/scripts/partmap_fastboot.sh"
	"tools/scripts/partmap_diskimg.sh"
	"tools/scripts/usb-down.sh"
	"tools/scripts/configs/udown.bootloader.sh"
	"tools/bin/linux-usbdownloader"
	"tools/files/partmap_*.txt"
)

declare -A BUILD_RECIPES=(
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
	["cleanall"]="cleanall"		# clean and remove download files
  	["menuconfig"]="menuconfig"
  	["savedefconfig"]="savedefconfig"
)

# Fixed
BB_LOCAL_CONF=$BUILD_DIR/conf/local.conf
BB_BBLAYER_CONF=$BUILD_DIR/conf/bblayers.conf

TARGET_AVAIL_TABLE=""
IMAGE_AVAIL_TABLE=""
IMAGE_TYPE_TABLE=""

function usage () {
	echo ""
	echo "Usage: `basename $0` <machine>-<board> <image> [options]"
	echo ""
	echo " [machine-board]"
	echo "      : located at '$(echo $TARGET_CONF_DIR | sed 's|'$BSP_ROOT_DIR'/||')'"
	echo " [image]"
	echo "      : located at '$(echo $IMAGE_DIR | sed 's|'$BSP_ROOT_DIR'/||')'"
	echo "      : The image must be 'nexell-image-<image>'"
	echo ""
	echo " [options]"
	echo "  -l : show available lists (machine-board, images, recipes, commands ...)"
	echo "  -t : select build recipe"
	echo "  -i : select image type to merge with <image>"
	echo "  -c : build commands"
	echo "  -o : bitbake option"
	echo "  -v : set bitbake '-v' option"
	echo "  -S : build SDK for image"
	echo "  -f : force overwrite buid confing files ('local.conf' and 'bblayers.conf')"
	echo "  -j : determines how many tasks bitbake should run in parallel"
	echo "  -h : help"
	echo ""
	print_avail_lists
	exit 1;
}

function err() {
	echo  -e "\033[0;31m $@\033[0m"
}

function msg() {
	echo  -e "\033[0;33m $@\033[0m"
}

function get_avail_types () {
	local dir=$1 sep=$2 table=$3 val # store the value
	[[ $4 ]] && declare -n avail=$4;

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

		if [ $i == *local.conf* ] || [ $i == *bblayers.conf* ]; then
			continue
		fi

		local match=false
		if [ ${#avail[@]} -ne 0 ]; then
			for n in "${avail[@]}"
			do
				if [[ $i == *$n* ]]; then
					match=true
					break;
				fi
			done
		else
			match=true
		fi

		[ $match != true ] && continue;

		val="${val} $(echo "$i" | awk -F".${sep}" '{print $1}')"
		eval "$table=(\"${val}\")"
	done
}

function check_avail_type () {
	local name=$1 table=$2 msg=$3

	if [[ $msg != "target" ]] && [[ $msg != "image" ]]; then
		[ -z $name ] && return;
	fi

	for i in ${table}; do
		if [[ ${i} == ${name} ]]; then
			return
		fi
	done

	err "Not support $msg: $name"
	err "Availiable: $table"
	usage
	exit 1;
}

function merge_conf_file () {
	local src=$1 cmp=$2 dst=$3

	while IFS='' read i;
        do
                merge=true
                while IFS='' read n;
                do
			[[ -z $i ]] && break;
			[[ $i == *BBMASK* ]] || [[ $i == *_append* ]] && break;
			[[ $i == *+=* ]] && break;
			[[ ${i:0:1} = "#" ]] && break;

			[[ -z $n ]] && continue;
			[[ $n == *BBMASK* ]] || [[ $n == *_append* ]] && continue;
			[[ $n == *+=* ]] && continue;
			[[ ${n:0:1} = "#" ]] && continue;

			ti=${i%=*} ti=${ti% *}
			tn=${n%=*} tn=${tn% *}

			# replace
                        if [[ $ti == $tn ]]; then
				i=$(echo "$i" | sed -e "s/[[:space:]]\+/ /g")
				n=$(echo "$n" | sed -e "s/[[:space:]]\+/ /g")
                                sed -i "s/$n/$i/" $dst
                                merge=false
                                break;
                        fi
                done < $src

		# merge
                if [ $merge == true ] && [[ ${i:0:1} != "#" ]]; then
			i=$(echo "$i" | sed -e "s/[[:space:]]\+/ /g")
                	echo "$i" >> $dst;
                fi
	done < $cmp
}

function parse_conf_machine () {
	local conf=$BB_LOCAL_CONF
        local base=$TARGET_CONF_DIR/local.conf
	local target=$TARGET_CONF_DIR/$TARGET_NAME.conf

	msg "---------------------------------------------------------------------------"
	msg " COPY     : $base"
	msg " TO       : $conf"
	msg "---------------------------------------------------------------------------"

	cp $base $conf
	[ $? -ne 0 ] && exit 1;

	replace="\"$MACHINE_NAME\""
	sed -i "s/.*MACHINE.*/MACHINE = $replace/" $conf
	[ $? -ne 0 ] && exit 1;

	msg "---------------------------------------------------------------------------"
	msg " PARSE    : $target"
	msg " TO       : $conf"
	msg "---------------------------------------------------------------------------"

	echo "" >> $conf
	echo "# PARSING: $target" >> $conf
	merge_conf_file $base $target $conf

	for i in ${!LOCAL_CONF_VALUES[@]}
	do
		prefix="$i"
		replace="\"${LOCAL_CONF_VALUES[$i]//\//\\/}\""
		sed -i "s/.*$prefix =.*/$prefix = $replace/" $conf
	done
	echo "# PARSING DONE" >> $conf
}

function parse_conf_image () {
        local conf=$BB_LOCAL_CONF
	local base=${IMAGE_NAME##*-} type=$OPT_IMAGE_TYPE

	for i in $IMAGE_CONF_DIR/$base.conf $IMAGE_CONF_DIR/$type.conf
	do
		[ ! -f $i ] && continue;
		msg "---------------------------------------------------------------------------"
		msg " PARSE    : $i"
		msg " TO       : $conf"
		msg "---------------------------------------------------------------------------"

		echo "" >> $conf
		echo "# PARSING: $i" >> $conf
		merge_conf_file $conf $i $conf
		echo "# PARSING DONE" >> $conf
        done
}

function parse_conf_sdk () {
        local base=$IMAGE_CONF_DIR/sdk.conf
	local conf=$BB_LOCAL_CONF

	if [ $OPT_BUILD_SDK != true ]; then
		return
	fi

	msg "---------------------------------------------------------------------------"
	msg " PARSE    : $base"
	msg " TO       : $conf"
	msg "---------------------------------------------------------------------------"

	echo "" >> $conf
	echo "# PARSING: $base" >> $conf
	merge_conf_file $conf $base $conf
	echo "# PARSING DONE" >> $conf
}

function parse_conf_ramfs () {
	local conf=$BB_LOCAL_CONF
	local replace="\"$IMAGE_NAME\""

	sed -i "s/.*INITRAMFS_IMAGE.*/INITRAMFS_IMAGE = $replace/" $conf
}

function parse_conf_tasks () {
	if [ -z $OPT_BUILD_TASKS ]; then
		return
	fi

	local file=$BB_LOCAL_CONF
	if grep -q BB_NUMBER_THREADS "$file"; then
		replace="\"$OPT_BUILD_TASKS\""
		sed -i "s/.*BB_NUMBER_THREADS.*/BB_NUMBER_THREADS = $replace/" $file
	else
		echo "" >> $BB_LOCAL_CONF
		echo "BB_NUMBER_THREADS = \"${OPT_BUILD_TASKS}\"" >> $file
	fi
}

function parse_conf_bblayer () {
	local base=$TARGET_CONF_DIR/bblayers.conf
        local conf=$BB_BBLAYER_CONF

	msg "---------------------------------------------------------------------------"
	msg " COPY     : $base"
	msg " TO       : $conf"
	msg "---------------------------------------------------------------------------"

        cp $base $conf
	[ $? -ne 0 ] && exit 1;

	local replace="\"${BSP_YOCTO_DIR//\//\\/}\""
	sed -i "s/.*BSPPATH :=.*/BSPPATH := $replace/" $conf
}

function setup_bitbake_env () {
	mkdir -p $(dirname $BUILD_DIR)

	# run oe-init-build-env
	source $POKY_DIR/oe-init-build-env $BUILD_DIR >/dev/null 2>&1
	msg "---------------------------------------------------------------------------"
	msg " bitbake environment set up command:"
	msg " $> source $POKY_DIR/oe-init-build-env $BUILD_DIR"
	msg "---------------------------------------------------------------------------"
}

function check_bitbake_env () {
        local mach=$TARGET_NAME
	local conf=$BB_LOCAL_CONF
	local file=$BUILD_DIR/.build_image_type
	local old="" new=""

        if [ ! -f $conf ]; then
                err "Not build setup environment : '$conf' ..."
                err "$> source poky/oe-init-build-env <build dir>/<machin type>"
		exit 1;
	fi

	if [ -z "$OPT_IMAGE_TYPE" ]; then
		new="${TARGET_NAME}_${IMAGE_NAME}"
	else
		new=${TARGET_NAME}_${IMAGE_NAME}_${OPT_IMAGE_TYPE}
	fi

	if [ $OPT_BUILD_SDK == true ]; then
		new="${new}_SDK"
	fi

	if [ -e $file ]; then
		old="$(cat $file)"
	fi

        v="$(echo $(find $conf -type f -exec grep -w -h 'MACHINE' {} \;) | cut -d'"' -f 2)"
        v="$(echo $v | cut -d'"' -f 1)-${mach##*-}"

        if [[ $mach == $v ]]; then
		msg "PARSE: Already '$(echo $conf | sed 's|'$BSP_ROOT_DIR'/||')'"
		if [[ $old != $new ]]; then
			[ -e $file ] && rm $file;
			echo $new >> $file;
			msg "PARSE: New image '$new'"
			return 1
        	fi
        	return 0
        fi

	echo $new >> $file;
	return 1
}

function print_avail_lists () {
	msg "=================================================================================="
	msg "Support:"
	msg "=================================================================================="

	msg "TARGET: <machine-board>"
	msg "\t: '$(echo $TARGET_CONF_DIR | sed 's|'$BSP_ROOT_DIR'/||')'"
	msg "\t---------------------------------------------------------------------------"
	msg "\t${TARGET_AVAIL_TABLE}"
	msg "\t---------------------------------------------------------------------------"

	msg "IMAGE: nexell-image-<image>"
	msg "\t: '$(echo $IMAGE_DIR | sed 's|'$BSP_ROOT_DIR'/||')'"
	msg "\t---------------------------------------------------------------------------"
	msg "\t ${IMAGE_AVAIL_TABLE}"
	msg "\t---------------------------------------------------------------------------"

	msg "IMAGE-TYPE: -i <image>"
	msg "\t: '$(echo $IMAGE_CONF_DIR | sed 's|'$BSP_ROOT_DIR'/||')'"
	msg "\t---------------------------------------------------------------------------"
	msg "\t ${IMAGE_TYPE_TABLE}"
	msg "\t---------------------------------------------------------------------------"

	msg ""
	msg "RECIPE: '-t'"
	for i in "${!BUILD_RECIPES[@]}"; do
		msg "\t$i (${BUILD_RECIPES[$i]})"
	done
	msg ""
	msg "COMMAND: '-c'"
	for i in "${!BUILD_COMMANDS[@]}"; do
		msg "\t$i (${BUILD_COMMANDS[$i]})"
	done
	msg ""
}

function copy_deploy_images () {
	local deploy=$BUILD_DIR/tmp/deploy/images/$MACHINE_NAME
	local result

	if [ ! -d $deploy ]; then
		err "No directory : $deploy"
		exit 1
	fi

	result="$(echo $IMAGE_NAME | cut -d'.' -f 1)"
	RESULT_OUT=result-$TARGET_NAME-${result##*-}
	result=$RESULT_DIR/$RESULT_OUT

	msg "---------------------------------------------------------------------------"
	msg " DEPLOY     : $deploy"
	msg " RESULT     : $result"
	msg "---------------------------------------------------------------------------"

	mkdir -p $result
	[ $? -ne 0 ] && exit 1;

	cd $deploy

	for file in "${RESULT_FILES[@]}"
	do
		local files=$(find $file -print \
			2> >(grep -v 'No such file or directory' >&2) | sort)

		for n in $files; do
			to=$result/$n

			if [[ -d $n ]]; then
				mkdir -p $to
				continue
			fi

			if [ -f $to ]; then
				ts="$(stat --printf=%y $n | cut -d. -f1)"
				td="$(stat --printf=%y $to | cut -d. -f1)"
				[ "${ts}" == "${td}" ] && continue;
			fi
			cp -a $n $to
		done
	done
}

function copy_sdk_images () {
	local dir sdk=$BUILD_DIR/tmp/deploy/sdk

	if [[ ! -d $sdk ]]; then
		err "No directory : $sdk"
		exit 1
	fi

	dir="$(echo $IMAGE_NAME | cut -d'.' -f 1)"
	RESULT_OUT=SDK-result-$TARGET_NAME-${dir##*-}
	dir=$RESULT_DIR/$RESULT_OUT

	mkdir -p $dir
	[ $? -ne 0 ] && exit 1;

	cp -a $sdk/* $dir/
}

function copy_tools_files () {
	local result="$(echo $IMAGE_NAME | cut -d'.' -f 1)"

	RESULT_OUT=result-$TARGET_NAME-${result##*-}
	result=$RESULT_DIR/$RESULT_OUT

	msg "---------------------------------------------------------------------------"
	msg " TOOLS      : $deploy"
	msg " RESULT     : $result"
	msg "---------------------------------------------------------------------------"

	mkdir -p $result
	[ $? -ne 0 ] && exit 1;

	cd $BSP_ROOT_DIR

	for file in "${TOOLS_FILES[@]}"
	do
		local files=$(find $file -print \
			2> >(grep -v 'No such file or directory' >&2) | sort)

		for n in $files; do
			if [[ -d $n ]]; then
				continue
			fi

			to=$result/$(basename $n)
			if [ -f $to ]; then
				ts="$(stat --printf=%y $n | cut -d. -f1)"
				td="$(stat --printf=%y $to | cut -d. -f1)"
				[ "${ts}" == "${td}" ] && continue;
			fi
			cp -a $n $to
		done
	done
}

function link_result_dir () {
	link=$1
	if [[ -e $RESULT_DIR/$link ]] ||
	   [[ -h $RESULT_DIR/$link ]]; then
		rm -f $RESULT_DIR/$link
	fi

	cd $RESULT_DIR
	ln -s $RESULT_OUT $link
}

OPT_BUILD_PARSE=false
OPT_BUILD_OPTION=""
OPT_BUILD_VERBOSE=""
OPT_BUILD_SDK=false
OPT_IMAGE_TYPE=
OPT_BUILD_TASKS=

BB_RECIPE=""
BB_BUILD_CMD=""

function parse_args () {
	ARGS=$(getopt -o lSfht:i:c:o:j:v -- "$@");
    	eval set -- "$ARGS";

    	while true; do
		case "$1" in
		-l )
			print_avail_lists; exit 0;;
		-t )
			for i in ${!BUILD_RECIPES[@]}; do
				[ $i != $2 ] && continue;
				BB_RECIPE=${BUILD_RECIPES[$i]}; shift 2; break;
			done
			if [ -z $BB_RECIPE ]; then
				err "Available Targets:"
				for i in "${!BUILD_RECIPES[@]}"; do
					err "\t$i\t: ${BUILD_RECIPES[$i]}"
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
		-i )	OPT_IMAGE_TYPE=$2; shift 2;;
		-o )	OPT_BUILD_OPTION=$2; shift 2;;
		-S )	OPT_BUILD_SDK=true; shift 1;;
		-f )	OPT_BUILD_PARSE=true; shift 1;;
		-j )	OPT_BUILD_TASKS=$2; shift 2;;
		-v )	OPT_BUILD_VERBOSE="-v"; shift 1;;
		-h )	usage;	exit 1;;
		-- ) 	break ;;
		esac
	done
}

###############################################################################
# start shell commands
###############################################################################
get_avail_types $TARGET_CONF_DIR "conf" TARGET_AVAIL_TABLE MACHINE_SUPPORT 
get_avail_types $IMAGE_DIR "bb" IMAGE_AVAIL_TABLE
get_avail_types $IMAGE_CONF_DIR "conf" IMAGE_TYPE_TABLE

# parsing input arguments
parse_args $@

check_avail_type "$TARGET_NAME" "$TARGET_AVAIL_TABLE" "target"
check_avail_type "$IMAGE_NAME" "$IMAGE_AVAIL_TABLE" "image"
check_avail_type "$OPT_IMAGE_TYPE" "$IMAGE_TYPE_TABLE" "image type"

setup_bitbake_env
check_bitbake_env
NEED_PARSE=$?

if [ $NEED_PARSE == 1 ] || [ $OPT_BUILD_PARSE == true ]; then
	parse_conf_machine
	parse_conf_image
	parse_conf_sdk
	parse_conf_bblayer
fi

parse_conf_ramfs
parse_conf_tasks

msg "---------------------------------------------------------------------------"
msg " TARGET     : $TARGET_NAME"
msg " IMAGE      : $IMAGE_NAME + $OPT_IMAGE_TYPE"
msg " RECIPE     : $BB_RECIPE"
msg " COMMAND    : $BB_BUILD_CMD"
msg " OPTION     : $OPT_BUILD_OPTION $OPT_BUILD_VERBOSE"
msg " SDK        : $OPT_BUILD_SDK"
msg " BUILD DIR  : $BUILD_DIR"
msg " DEPLOY DIR : $BUILD_DIR/tmp/deploy/images/$MACHINE_NAME"
msg " SDK DIR    : $BUILD_DIR/tmp/deploy/sdk"
msg "---------------------------------------------------------------------------"

if [ $OPT_BUILD_SDK != true ]; then
	if [ ! -z $BB_RECIPE ]; then
		bitbake $BB_RECIPE $BB_BUILD_CMD $OPT_BUILD_OPTION $OPT_BUILD_VERBOSE
	else
		# not support buildclean for image type
		if [ "${BB_BUILD_CMD}" == "-c buildclean" ]; then
			BB_BUILD_CMD="-c cleanall"
		fi
		bitbake $IMAGE_NAME $BB_BUILD_CMD $OPT_BUILD_OPTION $OPT_BUILD_VERBOSE
		[ $? -ne 0 ] && exit 1;
	fi

	if [ -z "${BB_BUILD_CMD}" ]; then
		copy_deploy_images
		copy_tools_files
		link_result_dir "result"
	fi
else
	bitbake -c populate_sdk $IMAGE_NAME $OPT_BUILD_OPTION $OPT_BUILD_VERBOSE
	[ $? -ne 0 ] && exit 1;
	copy_sdk_images
	link_result_dir "SDK"
fi

msg "---------------------------------------------------------------------------"
msg " RESULT DIR : $RESULT_DIR/$RESULT_OUT"
msg "---------------------------------------------------------------------------"
msg " Bitbake environment set up command:"
msg " $> source $POKY_DIR/oe-init-build-env $BUILD_DIR"
msg "---------------------------------------------------------------------------"
