#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>
#
# $> build_yocto.sh <machine-board> <image> [options]
#

# Input arguments
TARGET_MACHINE=$1
TARGET_IMAGE=$2

MACHINE_SUPPORT=( "nxp3220" )
MACHINE_NAME="$(echo $TARGET_MACHINE | cut -d'-' -f 1)"

# Top path
BSP_ROOT_DIR=`readlink -e -n "$(cd "$(dirname "$0")" && pwd)/../.."`
BSP_YOCTO_DIR=$BSP_ROOT_DIR/yocto

# result path
BSP_RESULT_DIR=$BSP_YOCTO_DIR/out
BSP_RESULT_LINK=

# yocto path
YOCTO_POKY_DIR=$BSP_YOCTO_DIR/poky
YOCTO_META_DIR=$BSP_YOCTO_DIR/meta-nexell/meta-nxp3220
YOCTO_IMAGE_DIR=$YOCTO_META_DIR/recipes-core/images
YOCTO_BUILD_DIR=$BSP_YOCTO_DIR/build/build-$TARGET_MACHINE

# Configure file path for available lists
TARGET_MACHINE_DIR=$YOCTO_META_DIR/tools/configs/machines
TARGET_IMAGE_DIR=$YOCTO_META_DIR/tools/configs/images

# Parse to local.conf
declare -A LOCAL_CONF_VALUES=(
	["BSP_ROOT_DIR"]="$BSP_ROOT_DIR"
	["BSP_TARGET_MACHINE"]="$TARGET_MACHINE"
)

# Copy from yocto deploy to result dir
BSP_RESULT_FILES=(
	"bl1-nxp3220.bin.raw"
	"bl1-nxp3220.bin.enc.raw"
	"bl1-nxp3220.bin.raw.ecc"
	"bl1-nxp3220.bin.enc.raw.ecc"
	"bl2.bin.raw"
	"bl2.bin.raw.ecc"
	"bl32.bin.raw"
	"bl32.bin.enc.raw"
	"bl32.bin.raw.ecc"
	"bl32.bin.enc.raw.ecc"
	"u-boot-${MACHINE_NAME}-1.0-r0.bin"
	"u-boot.bin"
	"u-boot.bin.raw"
	"u-boot.bin.raw.ecc"
	"params_env.*"
	"boot/"
	"boot.img"
	"rootfs.img"
	"userdata.img"
	"misc/"
	"misc.img"
	"swu_image.sh"
	"swu_hash.py"
	"*sw-description*"
	"*.sh"
	"swu.private.key"
	"swu.public.key"
	"*.swu"
)

# Copy from BSP tools to result dir
BSP_TOOLS_FILES=(
	"tools/scripts/partmap_fastboot.sh"
	"tools/scripts/partmap_diskimg.sh"
	"tools/scripts/usb-down.sh"
	"tools/scripts/configs/udown.bootloader.sh"
	"tools/bin/linux-usbdownloader"
	"tools/bin/simg2dev"
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
	["miscimg"]="nexell-miscimg"
	["recoveryimg"]="nexell-recoveryimg"
	["swuimg"]="nexell-swuimg"
)

declare -A BUILD_COMMANDS=(
  	["clean"]="buildclean"
  	["distclean"]="cleansstate"
	["cleanall"]="cleanall"		# clean and remove download files
  	["menuconfig"]="menuconfig"
  	["savedefconfig"]="savedefconfig"
)

BBLOCAL_CONF_FILE=$YOCTO_BUILD_DIR/conf/local.conf
BBLAYER_CONF_FILE=$YOCTO_BUILD_DIR/conf/bblayers.conf

TARGET_AVAIL_TABLE=""
IMAGE_AVAIL_TABLE=""
IMAGE_AVAIL_TYPES=""

function usage () {
	echo ""
	echo "Usage: `basename $0` <machine>-<board> <image> [options]"
	echo ""
	echo " [machine-board]"
	echo "      : located at '$(echo $TARGET_MACHINE_DIR | sed 's|'$BSP_ROOT_DIR'/||')'"
	echo " [image]"
	echo "      : located at '$(echo $YOCTO_IMAGE_DIR | sed 's|'$BSP_ROOT_DIR'/||')'"
	echo "      : The image name is must be 'nexell-image-<image>'"
	echo ""
	echo " [options]"
	echo "  -l : show available lists (machine-board, images, recipes, commands ...)"
	echo "  -t : set build recipe"
	echo "  -i : set image type to build with <image>, ex> -i A,B,..."
	echo "  -c : build commands"
	echo "  -o : bitbake option"
	echo "  -v : set bitbake '-v' option"
	echo "  -S : build the SDK for image"
	echo "  -p : copy images from deploy dir to result dir"
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
			for n in "${avail[@]}"; do
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
	local comp=()

	if [[ -z $name ]] &&
	   [[ $msg == "image type" ]]; then
		return
	fi

	for i in ${table}; do
		for n in ${name}; do
			if [[ ${i} == ${n} ]]; then
				comp+=($i)
			fi
		done
	done

	arr=($name)
	if [ ${#comp[@]} -ne 0 ] &&
	   [ ${#arr[@]} == ${#comp[@]} ]; then
		return
	fi

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
	local dst=$BBLOCAL_CONF_FILE
        local src=$TARGET_MACHINE_DIR/local.conf
	local target=$TARGET_MACHINE_DIR/$TARGET_MACHINE.conf

	msg "---------------------------------------------------------------------------"
	msg " COPY     : $src"
	msg " TO       : $dst"
	msg "---------------------------------------------------------------------------"

	cp $src $dst
	[ $? -ne 0 ] && exit 1;

	replace="\"$MACHINE_NAME\""
	sed -i "s/^MACHINE.*/MACHINE = $replace/" $dst
	[ $? -ne 0 ] && exit 1;

	msg "---------------------------------------------------------------------------"
	msg " PARSE    : $target"
	msg " TO       : $dst"
	msg "---------------------------------------------------------------------------"

	echo "" >> $dst
	echo "# PARSING: $target" >> $dst
	merge_conf_file $src $target $dst

	for i in ${!LOCAL_CONF_VALUES[@]}; do
		prefix="$i"
		replace="\"${LOCAL_CONF_VALUES[$i]//\//\\/}\""
		sed -i "s/^$prefix =.*/$prefix = $replace/" $dst
	done
	echo "# PARSING DONE" >> $dst
}

function parse_conf_image () {
        local dst=$BBLOCAL_CONF_FILE
	local src=( $TARGET_IMAGE_DIR/${TARGET_IMAGE##*-}.conf )
	local type=$OPT_IMAGE_TYPE

	for i in $type; do
		src+=( $TARGET_IMAGE_DIR/$i.conf )
	done

	for i in "${src[@]}"; do
		[ ! -f $i ] && continue;
		msg "---------------------------------------------------------------------------"
		msg " PARSE    : $i"
		msg " TO       : $dst"
		msg "---------------------------------------------------------------------------"

		echo "" >> $dst
		echo "# PARSING: $i" >> $dst
		merge_conf_file $dst $i $dst
		echo "# PARSING DONE" >> $dst
        done
}

function parse_conf_sdk () {
	local dst=$BBLOCAL_CONF_FILE
        local src=$TARGET_IMAGE_DIR/sdk.conf

	if [ $OPT_BUILD_SDK != true ]; then
		return
	fi

	msg "---------------------------------------------------------------------------"
	msg " PARSE    : $src"
	msg " TO       : $dst"
	msg "---------------------------------------------------------------------------"

	echo "" >> $dst
	echo "# PARSING: $src" >> $dst
	merge_conf_file $dst $src $dst
	echo "# PARSING DONE" >> $dst
}

function parse_conf_ramfs () {
	local dst=$BBLOCAL_CONF_FILE
	local replace="\"$TARGET_IMAGE\""

	sed -i "s/^INITRAMFS_IMAGE.*/INITRAMFS_IMAGE = $replace/" $dst
}

function parse_conf_tasks () {
	if [ -z $OPT_BUILD_TASKS ]; then
		return
	fi

	local file=$BBLOCAL_CONF_FILE
	if grep -q BB_NUMBER_THREADS "$file"; then
		replace="\"$OPT_BUILD_TASKS\""
		sed -i "s/^BB_NUMBER_THREADS.*/BB_NUMBER_THREADS = $replace/" $file
	else
		echo "" >> $BBLOCAL_CONF_FILE
		echo "BB_NUMBER_THREADS = \"${OPT_BUILD_TASKS}\"" >> $file
	fi
}

function parse_conf_bblayer () {
        local dst=$BBLAYER_CONF_FILE
	local src=$TARGET_MACHINE_DIR/bblayers.conf

	msg "---------------------------------------------------------------------------"
	msg " COPY     : $src"
	msg " TO       : $dst"
	msg "---------------------------------------------------------------------------"

        cp $src $dst
	[ $? -ne 0 ] && exit 1;

	local replace="\"${BSP_YOCTO_DIR//\//\\/}\""
	sed -i "s/^BSPPATH :=.*/BSPPATH := $replace/" $dst
}

function setup_bitbake_env () {
	mkdir -p $(dirname $YOCTO_BUILD_DIR)

	# run oe-init-build-env
	source $YOCTO_POKY_DIR/oe-init-build-env $YOCTO_BUILD_DIR >/dev/null 2>&1
	msg "---------------------------------------------------------------------------"
	msg " bitbake environment set up command:"
	msg " $> source $YOCTO_POKY_DIR/oe-init-build-env $YOCTO_BUILD_DIR"
	msg "---------------------------------------------------------------------------"
}

function check_bitbake_env () {
        local mach="$(echo $TARGET_MACHINE | cut -d'-' -f 1)"
	local conf=$BBLOCAL_CONF_FILE
	local file=$YOCTO_BUILD_DIR/.build_image_type
	local new=${TARGET_MACHINE}_${TARGET_IMAGE} old=""

        if [ ! -f $conf ]; then
                err "Not build setup environment : '$conf' ..."
                err "$> source poky/oe-init-build-env <build dir>/<machin type>"
		exit 1;
	fi

	if [[ ! -z $OPT_IMAGE_TYPE ]]; then
		for i in $OPT_IMAGE_TYPE; do
			new="$new"_"$i"
		done
	fi

	if [ $OPT_BUILD_SDK == true ]; then
		new="${new}_SDK"
	fi

	if [ -e $file ]; then
		old="$(cat $file)"
	fi

	local vmach="$(echo $(echo $(find $conf -type f -exec grep -w -h 'MACHINE' {} \;) | \
		cut -d'"' -f 2) | cut -d'"' -f 1)"

        if [[ $mach == $vmach ]]; then
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
	msg "\t: '$(echo $TARGET_MACHINE_DIR | sed 's|'$BSP_ROOT_DIR'/||')'"
	msg "\t---------------------------------------------------------------------------"
	msg "\t${TARGET_AVAIL_TABLE}"
	msg "\t---------------------------------------------------------------------------"

	msg "IMAGE: nexell-image-<image>"
	msg "\t: '$(echo $YOCTO_IMAGE_DIR | sed 's|'$BSP_ROOT_DIR'/||')'"
	msg "\t---------------------------------------------------------------------------"
	msg "\t ${IMAGE_AVAIL_TABLE}"
	msg "\t---------------------------------------------------------------------------"

	msg "IMAGE-TYPE: -i <image>,<image>,..."
	msg "\t: '$(echo $TARGET_IMAGE_DIR | sed 's|'$BSP_ROOT_DIR'/||')'"
	msg "\t---------------------------------------------------------------------------"
	msg "\t ${IMAGE_AVAIL_TYPES}"
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
	local deploy=$YOCTO_BUILD_DIR/tmp/deploy/images/$MACHINE_NAME
	local result

	if [ ! -d $deploy ]; then
		err "No directory : $deploy"
		exit 1
	fi

	result="$(echo $TARGET_IMAGE | cut -d'.' -f 1)"
	BSP_RESULT_LINK=result-$TARGET_MACHINE-${result##*-}
	result=$BSP_RESULT_DIR/$BSP_RESULT_LINK

	msg "---------------------------------------------------------------------------"
	msg " DEPLOY     : $deploy"
	msg " RESULT     : $result"
	msg "---------------------------------------------------------------------------"

	mkdir -p $result
	[ $? -ne 0 ] && exit 1;

	cd $deploy

	for file in "${BSP_RESULT_FILES[@]}"; do
		local files=$(find $file -print \
			2> >(grep -v 'No such file or directory' >&2) | sort)

		for n in $files; do
			[ ! -e $n ] && continue;

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
	local dir sdk=$YOCTO_BUILD_DIR/tmp/deploy/sdk

	if [[ ! -d $sdk ]]; then
		err "No directory : $sdk"
		exit 1
	fi

	dir="$(echo $TARGET_IMAGE | cut -d'.' -f 1)"
	BSP_RESULT_LINK=SDK-result-$TARGET_MACHINE-${dir##*-}
	dir=$BSP_RESULT_DIR/$BSP_RESULT_LINK

	mkdir -p $dir
	[ $? -ne 0 ] && exit 1;

	cp -a $sdk/* $dir/
}

function copy_tools_files () {
	local result="$(echo $TARGET_IMAGE | cut -d'.' -f 1)"

	BSP_RESULT_LINK=result-$TARGET_MACHINE-${result##*-}
	result=$BSP_RESULT_DIR/$BSP_RESULT_LINK

	mkdir -p $result
	[ $? -ne 0 ] && exit 1;

	cd $BSP_ROOT_DIR

	for file in "${BSP_TOOLS_FILES[@]}"; do
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
	if [[ -e $BSP_RESULT_DIR/$link ]] ||
	   [[ -h $BSP_RESULT_DIR/$link ]]; then
		rm -f $BSP_RESULT_DIR/$link
	fi

	cd $BSP_RESULT_DIR
	ln -s $BSP_RESULT_LINK $link
}

OPT_BUILD_PARSE=false
OPT_BUILD_OPTION=""
OPT_BUILD_VERBOSE=""
OPT_BUILD_SDK=false
OPT_BUILD_COPY=false
OPT_IMAGE_TYPE=
OPT_BUILD_TASKS=

BB_TARGET_RECIPE=""
BB_BUILD_CMD=""

function parse_args () {
	ARGS=$(getopt -o lSfhpt:i:c:o:j:v -- "$@");
    	eval set -- "$ARGS";

    	while true; do
		case "$1" in
		-l )
			print_avail_lists; exit 0;;
		-t )
			for i in ${!BUILD_RECIPES[@]}; do
				[ $i != $2 ] && continue;
				BB_TARGET_RECIPE=${BUILD_RECIPES[$i]}; shift 2; break;
			done
			if [ -z $BB_TARGET_RECIPE ]; then
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
			if [ -z "$BB_BUILD_CMD" ]; then
				err "Available Targets:"
				for i in "${!BUILD_COMMANDS[@]}"; do
					err "\t$i\t: ${BUILD_COMMANDS[$i]}"
				done
				exit 1;
			fi
			;;
		-i )	OPT_IMAGE_TYPE="";
			local arr=(${2//,/ })
			for i in "${arr[@]}"; do
				OPT_IMAGE_TYPE="$OPT_IMAGE_TYPE $i"
			done
			shift 2;;
		-o )	OPT_BUILD_OPTION=$2; shift 2;;
		-S )	OPT_BUILD_SDK=true; shift 1;;
		-f )	OPT_BUILD_PARSE=true; shift 1;;
		-p )	OPT_BUILD_COPY=true; shift 1;;
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
get_avail_types $TARGET_MACHINE_DIR "conf" TARGET_AVAIL_TABLE MACHINE_SUPPORT
get_avail_types $YOCTO_IMAGE_DIR "bb" IMAGE_AVAIL_TABLE
get_avail_types $TARGET_IMAGE_DIR "conf" IMAGE_AVAIL_TYPES

# parsing input arguments
parse_args $@

check_avail_type "$TARGET_MACHINE" "$TARGET_AVAIL_TABLE" "target"
check_avail_type "$TARGET_IMAGE" "$IMAGE_AVAIL_TABLE" "image"
check_avail_type "$OPT_IMAGE_TYPE" "$IMAGE_AVAIL_TYPES" "image type"

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
msg " TARGET     : $TARGET_MACHINE"
msg " IMAGE      : $TARGET_IMAGE + $OPT_IMAGE_TYPE"
msg " RECIPE     : $BB_TARGET_RECIPE"
msg " COMMAND    : $BB_BUILD_CMD"
msg " OPTION     : $OPT_BUILD_OPTION $OPT_BUILD_VERBOSE"
msg " SDK        : $OPT_BUILD_SDK"
msg " BUILD DIR  : $YOCTO_BUILD_DIR"
msg " DEPLOY DIR : $YOCTO_BUILD_DIR/tmp/deploy/images/$MACHINE_NAME"
msg " SDK DIR    : $YOCTO_BUILD_DIR/tmp/deploy/sdk"
msg "---------------------------------------------------------------------------"

if [ $OPT_BUILD_SDK != true ]; then
	if [ $OPT_BUILD_COPY == false ]; then
		if [ ! -z $BB_TARGET_RECIPE ]; then
			bitbake $BB_TARGET_RECIPE $BB_BUILD_CMD $OPT_BUILD_OPTION $OPT_BUILD_VERBOSE
		else
			# not support buildclean for image type
			if [ "$BB_BUILD_CMD" == "-c buildclean" ]; then
				BB_BUILD_CMD="-c cleanall"
			fi

			bitbake $TARGET_IMAGE $BB_BUILD_CMD $OPT_BUILD_OPTION $OPT_BUILD_VERBOSE
			[ $? -ne 0 ] && exit 1;
		fi
	fi

	if [ -z "$BB_BUILD_CMD" ]; then
		copy_deploy_images
		copy_tools_files
		link_result_dir "result"
	fi
else
	bitbake -c populate_sdk $TARGET_IMAGE $OPT_BUILD_OPTION $OPT_BUILD_VERBOSE
	[ $? -ne 0 ] && exit 1;
	copy_sdk_images
	link_result_dir "SDK"
fi

msg "---------------------------------------------------------------------------"
msg " RESULT DIR : $BSP_RESULT_DIR/$BSP_RESULT_LINK"
msg "---------------------------------------------------------------------------"
msg " Bitbake environment set up command:"
msg " $> source $YOCTO_POKY_DIR/oe-init-build-env $YOCTO_BUILD_DIR"
msg "---------------------------------------------------------------------------"
