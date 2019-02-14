#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>

BSP_ROOT_DIR=`readlink -e -n "$(cd "$(dirname "$0")" && pwd)/../.."`

MACHINE_NAME=$1
IMAGE_NAME=$2

# BSP path
BSP_YOCTO_DIR=$BSP_ROOT_DIR/yocto
BSP_POKY_DIR=$BSP_ROOT_DIR/yocto/poky
BSP_BUILD_DIR=$BSP_ROOT_DIR/yocto/build
BSP_META_DIR=$BSP_YOCTO_DIR/meta-nexell/meta-nxp3220
BSP_RESULT_DIR=$BSP_ROOT_DIR/yocto/out
BSP_RESULT_OUT=

# related machine
BB_MACHINE_DIR=$BSP_META_DIR/conf/machine
BB_IMAGE_DIR=$BSP_META_DIR/recipes-core/images

# related build
BB_BUILD_DIR=$BSP_BUILD_DIR/build-$MACHINE_NAME
BB_LOCAL_CONF=$BB_BUILD_DIR/conf/local.conf
BB_BBLAYER_CONF=$BB_BUILD_DIR/conf/bblayers.conf
BB_STATUS_FILE=$BSP_ROOT_DIR/.build_image_type

# related config
TOOL_MACH_DIR=$BSP_META_DIR/tools/configs/machines
TOOL_IMAGE_DIR=$BSP_META_DIR/tools/configs/images
TOOL_LOCAL_CONF=$TOOL_MACH_DIR/local.conf
TOOL_IMAGE_SDK=$TOOL_IMAGE_DIR/sdk.conf

RESULT_TARGETS=(
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

TOOLS_FILES=(
	"tools/scripts/partmap_fastboot.sh"
	"tools/files/partmap_emmc.txt"
	"tools/scripts/usb-down.sh"
	"tools/bin/linux-usbdownloader"
	"tools/scripts/configs/udown.bootloader.sh"
)

declare -A BB_LOCAL_CONF_VALUES=(
	["BSP_ROOT_DIR"]="$BSP_ROOT_DIR"
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
  	["cleanall"]="cleanall"		# clean download files
  	["menuconfig"]="menuconfig"
  	["savedefconfig"]="savedefconfig"
)

function err() {
	echo  -e "\033[0;31m $@\033[0m"
}

function msg() {
	echo  -e "\033[0;33m $@\033[0m"
}

MACHINE_NAME_TABLE=""
IMAGE_NAME_TABLE=""
IMAGE_TYPE_TABLE=""

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

function check_avail_type () {
	local name=$1 table=$2 msg=$3

	if [ "$msg" != "machine" ] && [ "$msg" != "image" ]; then
		[ -z $name ] && return;
	fi

	for i in ${table}; do
		if [ "${i}" == "${name}" ]; then
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

function parse_conf_machine () {
        local cmp=$TOOL_MACH_DIR/$MACHINE_NAME.conf
	local src=$TOOL_LOCAL_CONF dst=$BB_LOCAL_CONF

        cp $src $dst
	[ $? -ne 0 ] && exit 1;

	if [ ! -f $cmp ]; then
		replace="\"$MACHINE_NAME\""
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
	for i in ${!BB_LOCAL_CONF_VALUES[@]}
	do
		prefix="$i"
		replace="\"${BB_LOCAL_CONF_VALUES[$i]//\//\\/}\""
		sed -i "s/.*$prefix =.*/$prefix = $replace/" $dst
	done
}

function parse_conf_image () {
        local dst=$BB_LOCAL_CONF
	local type=${IMAGE_NAME##*-} conf=$OPT_IMAGE_TYPE

	for i in $TOOL_IMAGE_DIR/$type.conf $TOOL_IMAGE_DIR/$conf.conf
	do
		[ ! -f $i ] && continue;
        	msg "-----------------------------------------------------------------"
		msg " PARSE    : $i"
		msg " TO       : $dst"
        	msg "-----------------------------------------------------------------"

		merge_conf_file $dst $i $dst
        done
}

function parse_conf_sdk () {
        local cmp=$TOOL_IMAGE_SDK
	local dst=$BB_LOCAL_CONF

	if [ $OPT_BUILD_SDK != true ]; then
		return
	fi

	msg "-----------------------------------------------------------------"
	msg " PARSE    : $cmp"
	msg " TO       : $dst"
	msg "-----------------------------------------------------------------"

	merge_conf_file $dst $cmp $dst
}

function parse_conf_ramfs () {
	local dst=$BB_LOCAL_CONF
	replace="\"$IMAGE_NAME\""
	sed -i "s/.*INITRAMFS_IMAGE.*/INITRAMFS_IMAGE = $replace/" $dst
}

function parse_conf_jobs () {
	if [ -z $OPT_BUILD_JOBS ]; then
		return
	fi

	local file=$BB_LOCAL_CONF
	if grep -q BB_NUMBER_THREADS "$file"; then
		replace="\"$OPT_BUILD_JOBS\""
		sed -i "s/.*BB_NUMBER_THREADS.*/BB_NUMBER_THREADS = $replace/" $file
	else
		echo "" >> $BB_LOCAL_CONF
		echo "BB_NUMBER_THREADS = \"${OPT_BUILD_JOBS}\"" >> $file
	fi
}

function parse_conf_bblayer () {
	local src=$TOOL_MACH_DIR/$MACHINE_NAME.bblayers
        local dst=$BB_BBLAYER_CONF

	if [ ! -f $src ]; then
		src=$TOOL_MACH_DIR/bblayers.conf
        fi

        msg "-----------------------------------------------------------------"
	msg " COPY     : $src"
	msg " TO       : $dst"
        msg "-----------------------------------------------------------------"

        cp $src $dst
	[ $? -ne 0 ] && exit 1;

	replace="\"${BSP_YOCTO_DIR//\//\\/}\""
	sed -i "s/.*BSPPATH :=.*/BSPPATH := $replace/" $dst
}

function setup_bitbake_env () {
	mkdir -p $BSP_BUILD_DIR

	# run oe-init-build-env
	source $BSP_POKY_DIR/oe-init-build-env $BB_BUILD_DIR >/dev/null 2>&1
	msg "-----------------------------------------------------------------"
	msg " bitbake environment set up command:"
	msg " $> source $BSP_POKY_DIR/oe-init-build-env $BB_BUILD_DIR"
	msg "-----------------------------------------------------------------"
}

function check_bitbake_env () {
        local mach=$MACHINE_NAME
	local conf=$BB_LOCAL_CONF
	local old_image="" new_image=""

        if [ ! -f $conf ]; then
                err "Not build setup environment : '$conf' ..."
                err "$> source poky/oe-init-build-env <build dir>/<machin type>"
		exit 1;
	fi

	if [ -z "$OPT_IMAGE_TYPE" ]; then
		new_image="${MACHINE_NAME}_${IMAGE_NAME}"
	else
		new_image=${MACHINE_NAME}_${IMAGE_NAME}_${OPT_IMAGE_TYPE}
	fi

	if [ $OPT_BUILD_SDK == true ]; then
		new_image="${new_image}_SDK"
	fi

	if [ -e $BB_STATUS_FILE ]; then
		old_image="$(cat $BB_STATUS_FILE)"
	fi

        v="$(echo $(find $conf -type f -exec grep -w -h 'MACHINE' {} \;) | cut -d'"' -f 2)"
        v="$(echo $v | cut -d'"' -f 1)"
        if [ "$mach" == "$v" ]; then
        	msg "PARSE: Already done '$conf'"

        	if [ "$old_image" != "$new_image" ]; then
			[ -e $BB_STATUS_FILE ] && rm $BB_STATUS_FILE;
			echo $new_image >> $BB_STATUS_FILE;
			msg "PARSE: New image '$new_image'"
			return 1
        	fi
        	return 0
        fi

	echo $new_image >> $BB_STATUS_FILE;
	return 1
}

function print_avail_lists () {
	msg "================================================================="
	msg "Support Lists:"
	msg "================================================================="

	msg "MACHINE NAME: <machine name>"
	msg "\t:$BB_MACHINE_DIR"
	msg "\t:$TOOL_MACH_DIR"
	msg "\t----------------------------------------------------------"
	msg "\t${MACHINE_NAME_TABLE}"
	msg "\t----------------------------------------------------------"

	msg "IMAGE NAME: nexell-image-<image type>"
	msg "\t:$BB_IMAGE_DIR"
	msg "\t----------------------------------------------------------"
	msg "\t ${IMAGE_NAME_TABLE}"
	msg "\t----------------------------------------------------------"

	msg "IMAGE TYPE: '-i'"
	msg "\t:$TOOL_IMAGE_DIR"
	msg "\t----------------------------------------------------------"
	msg "\t ${IMAGE_TYPE_TABLE}"
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
	local result deploy=$BB_BUILD_DIR/tmp/deploy/images/$MACHINE_NAME

	if [ ! -d $deploy ]; then
		err "No directory : $deploy"
		exit 1
	fi

	result="$(echo $IMAGE_NAME | cut -d'.' -f 1)"
	BSP_RESULT_OUT=result-$MACHINE_NAME-${result##*-}
	result=$BSP_RESULT_DIR/$BSP_RESULT_OUT

	msg "-----------------------------------------------------------------"
	msg " DEPLOY     : $deploy"
	msg " RESULT     : $result"
	msg "-----------------------------------------------------------------"

	mkdir -p $result
	[ $? -ne 0 ] && exit 1;

	cd $deploy

	for file in "${RESULT_TARGETS[@]}"
	do
		local files=$(find $file -print \
			2> >(grep -v 'No such file or directory' >&2) | sort)

		for n in $files; do
			to=$result/$n

			if [ -d "$n" ]; then
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
	local dir sdk=$BB_BUILD_DIR/tmp/deploy/sdk

	if [ ! -d $sdk ]; then
		err "No directory : $sdk"
		exit 1
	fi

	dir="$(echo $IMAGE_NAME | cut -d'.' -f 1)"
	BSP_RESULT_OUT=SDK-result-$MACHINE_NAME-${dir##*-}
	dir=$BSP_RESULT_DIR/$BSP_RESULT_OUT

	mkdir -p $dir
	[ $? -ne 0 ] && exit 1;

	cp -a $sdk/* $dir/
}

function copy_tools_files () {
	local result="$(echo $IMAGE_NAME | cut -d'.' -f 1)"

	BSP_RESULT_OUT=result-$MACHINE_NAME-${result##*-}
	result=$BSP_RESULT_DIR/$BSP_RESULT_OUT

	msg "-----------------------------------------------------------------"
	msg " TOOLS      : $deploy"
	msg " RESULT     : $result"
	msg "-----------------------------------------------------------------"

	mkdir -p $result
	[ $? -ne 0 ] && exit 1;

	cd $BSP_ROOT_DIR

	for file in "${TOOLS_FILES[@]}"
	do
		local files=$(find $file -print \
			2> >(grep -v 'No such file or directory' >&2) | sort)

		for n in $files; do
			if [ -d "$n" ]; then
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
	if [ -e "$BSP_RESULT_DIR/$link" ] ||
	   [ -h "$BSP_RESULT_DIR/$link" ]; then
		rm -f $BSP_RESULT_DIR/$link
	fi

	cd $BSP_RESULT_DIR
	ln -s $BSP_RESULT_OUT $link
}

function usage () {
	echo "Usage: `basename $0` <machine name> <image name> [options]"
	echo ""
	echo "[machine name]"
	echo "      : located at $BB_MACHINE_DIR"
	echo "[image name]"
	echo "      : image name is 'nexell-image-<image type>'"
	echo "      : located at $BB_IMAGE_DIR"
	echo ""
	echo "[options]"
	echo "  -l : show available lists (machine, images, targets, commands ...)"
	echo "  -t : select build target"
	echo "  -i : select image type"
	echo "  -c : build commands"
	echo "  -o : bitbake option"
	echo "  -S : build SDK for image"
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
OPT_IMAGE_TYPE=
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
		-i )	OPT_IMAGE_TYPE=$2; shift 2;;
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
# start shell commands
###############################################################################
get_avail_types $BB_MACHINE_DIR "conf" MACHINE_NAME_TABLE
get_avail_types $BB_IMAGE_DIR "bb" IMAGE_NAME_TABLE
get_avail_types $TOOL_IMAGE_DIR "conf" IMAGE_TYPE_TABLE

# parsing input arguments
parse_args $@

check_avail_type "$MACHINE_NAME" "$MACHINE_NAME_TABLE" "machine"
check_avail_type "$IMAGE_NAME" "$IMAGE_NAME_TABLE" "image"
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
parse_conf_jobs

msg "-----------------------------------------------------------------"
msg " MACHINE    : $MACHINE_NAME"
msg " IMAGE      : $IMAGE_NAME + $OPT_IMAGE_TYPE"
msg " TARGET     : $BB_TARGET"
msg " COMMAND    : $BB_BUILD_CMD"
msg " OPTION     : $OPT_BUILD_OPTION"
msg " SDK        : $OPT_BUILD_SDK"
msg " BUILD DIR  : $BB_BUILD_DIR"
msg " DEPLOY DIR : $BB_BUILD_DIR/tmp/deploy/images/$MACHINE_NAME"
msg " SDK DIR    : $BB_BUILD_DIR/tmp/deploy/sdk"
msg "-----------------------------------------------------------------"

if [ $OPT_BUILD_SDK != true ]; then
	if [ ! -z $BB_TARGET ]; then
		bitbake $BB_TARGET $BB_BUILD_CMD $OPT_BUILD_OPTION
	else
		# not support buildclean for image type
		if [ "${BB_BUILD_CMD}" == "-c buildclean" ]; then
			BB_BUILD_CMD="-c cleanall"
		fi
		bitbake $IMAGE_NAME $BB_BUILD_CMD $OPT_BUILD_OPTION
		[ $? -ne 0 ] && exit 1;
	fi

	if [ -z "${BB_BUILD_CMD}" ]; then
		copy_deploy_images
		copy_tools_files
		link_result_dir "result"
	fi
else
	bitbake -c populate_sdk $IMAGE_NAME $OPT_BUILD_OPTION
	[ $? -ne 0 ] && exit 1;
	copy_sdk_images
	link_result_dir "SDK"
fi

msg "-----------------------------------------------------------------"
msg " RESULT DIR : $BSP_RESULT_OUT"
msg "-----------------------------------------------------------------"
msg "-----------------------------------------------------------------"
msg " Sparse image to ext4 image:"
msg " $> simg2img <img>.img <img>.ext4"
msg ""
msg " Bitbake environment set up command:"
msg " $> source $BSP_POKY_DIR/oe-init-build-env $BB_BUILD_DIR"
msg "-----------------------------------------------------------------"
