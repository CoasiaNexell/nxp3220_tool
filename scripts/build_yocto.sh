#!/bin/bash

ROOT_DIR=`readlink -e -n "$(cd "$(dirname "$0")" && pwd)/../.."`

MACHINE_TYPE=$1
IMAGE_TYPE=$2

# path
YOCTO_DIR=$ROOT_DIR/yocto
POKY_DIR=$ROOT_DIR/yocto/poky
BUILD_DIR=$ROOT_DIR/yocto/build
META_DIR=$YOCTO_DIR/meta-nexell/meta-nxp3220
RESULT_DIR=$ROOT_DIR/yocto/out

# related machine
MACHINE_DIR=$META_DIR/conf/machine
IMAGE_DIR=$META_DIR/recipes-core/images
EXT_CONF_DIR=$META_DIR/tools/configs
EXT_IMAGE_DIR=$META_DIR/tools/images
BB_BUILD_DIR=$BUILD_DIR/build-$MACHINE_TYPE

IMAGE_PREFIX=nexell-image
IMAGE_CONF=
RESULT_OUT=
BUILD_JOBS=

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

function get_avail_type () {
	local dir=$1 sep=$2 table=$3 val
	[ ! -d $dir ] && return;

	cd $dir
	local value=$(find ./ -print \
		2> >(grep -v 'No such file or directory' >&2) | \
		grep ".*\.${sep}" | sort)

	for i in $value; do
		if [ ! -z "$(echo "$i" | cut -d'.' -f4)" ]; then
			continue
		fi
		val="${val} $(echo "$(echo "$i" | cut -d'/' -f2)" | cut -d'.' -f1)"
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
	local s=$1 f=$2 t=$3
         while read i;
        do
                eq=false
                while read n;
                do
                        v0="$(echo "$(echo $i | cut -d'=' -f 1)" | cut -d' ' -f 1)"
                        if [ "$v0" == "BBMASK" ]; then
                        	continue
                        fi

                        v1="$(echo "$(echo $n | cut -d'=' -f 1)" | cut -d' ' -f 1)"
                        if [ "$v0" == "$v1" ] && [ ! -z "$n" ] &&
			   [ "$v0" != "#" ]; then
                                sed -i "s/$n/$i/" $t
                                eq=true
                                break;
                        fi
                done < $s
                [ $eq == false ] && echo "$i" >> $t;
        done < $f
}

# overwrite to build_<machine>/conf/local.conf
function parse_machine_confing () {
        local cfg=$EXT_CONF_DIR/$MACHINE_TYPE.conf
	local src=$EXT_CONF_DIR/local.conf dst=$BB_BUILD_DIR/conf/local.conf

        cp $src $dst
	[ $? -ne 0 ] && exit 1;

	if [ ! -f $cfg ]; then
		replace="\"$MACHINE_TYPE\""
		sed -i "s/.*MACHINE.*/MACHINE = $replace/" $dst
		return
	fi

        msg "-----------------------------------------------------------------"
	msg " PARSE    : $src"
	msg " PATCH    : $cfg"
	msg " TO       : $dst"
        msg "-----------------------------------------------------------------"

	merge_conf_file $src $cfg $dst

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
	local type=$IMAGE_TYPE conf=$IMAGE_CONF

	type="$(echo $type | cut -d'.' -f 1)"
	type=${type##*-}

	for i in $EXT_IMAGE_DIR/$type.conf $EXT_IMAGE_DIR/$conf.conf
	do
		[ ! -f $i ] && continue;
        	msg "-----------------------------------------------------------------"
		msg " PARSE    : $i"
		msg " TO       : $dst"
        	msg "-----------------------------------------------------------------"
		merge_conf_file $dst $i $dst
        done
}

function parse_ramfs_image () {
	local dst=$BB_BUILD_DIR/conf/local.conf
	replace="\"$IMAGE_TYPE\""
	sed -i "s/.*INITRAMFS_IMAGE.*/INITRAMFS_IMAGE = $replace/" $dst
}

function parse_machine_jobs () {
	if [ -z $BUILD_JOBS ]; then
		return
	fi

	local file=$BB_BUILD_DIR/conf/local.conf
	if grep -q BB_NUMBER_THREADS "$file"; then
		replace="\"$BUILD_JOBS\""
		sed -i "s/.*BB_NUMBER_THREADS.*/BB_NUMBER_THREADS = $replace/" $file
	else
		echo "" >> $BB_BUILD_DIR/conf/local.conf
		echo "BB_NUMBER_THREADS = \"${BUILD_JOBS}\"" >> $file
	fi
}

function parse_bblayer_config () {
	local src=$EXT_CONF_DIR/$MACHINE_TYPE.bblayers
        local dst=$BB_BUILD_DIR/conf/bblayers.conf

	if [ ! -f $src ]; then
        	src=$EXT_CONF_DIR/bblayers.conf
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
	msg "\t:$EXT_CONF_DIR"
	msg "\t----------------------------------------------------------"
	msg "\t${MACHINE_TABLE}"
	msg "\t----------------------------------------------------------"

	msg "IMAGE TYPE: <image type>"
	msg "\t:$IMAGE_DIR"
	msg "\t----------------------------------------------------------"
	msg "\t ${IMAGE_TABLE}"
	msg "\t----------------------------------------------------------"

	msg "IMAGE CONFIG: '-i'"
	msg "\t:$EXT_IMAGE_DIR"
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

BB_PARSE=false
BB_TARGET=""
BB_CMD=""
BB_OPT=""
BB_SDK=false

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
				BB_CMD="-c ${BUILD_COMMANDS[$i]}"; shift 2; break;
			done
			if [ -z $BB_CMD ]; then
				err "Available Targets:"
				for i in "${!BUILD_COMMANDS[@]}"; do
					err "\t$i\t: ${BUILD_COMMANDS[$i]}"
				done
				exit 1;
			fi
			;;
		-i )	IMAGE_CONF=$2; shift 2;;
		-o )	BB_OPT=$2; shift 2;;
		-S )	BB_SDK=true; shift 1;;
		-f )	BB_PARSE=true; shift 1;;
		-j )	BUILD_JOBS=$2; shift 2;;
		-h )	usage;	exit 1;;
		-- ) 	break ;;
		esac
	done
}

get_avail_type $MACHINE_DIR "conf" MACHINE_TABLE
get_avail_type $IMAGE_DIR "bb" IMAGE_TABLE
get_avail_type $EXT_IMAGE_DIR "conf" IMAGE_CONF_TABLE

parse_args $@

check_machine_type $MACHINE_TYPE
check_image_type $IMAGE_TYPE
check_image_config $IMAGE_CONF

setup_bitbake_env
check_bitbake_env
NEED_PARSE=$?

if [ $NEED_PARSE == 1 ] || [ $BB_PARSE == true ]; then
	parse_machine_confing
	parse_image_config
	parse_bblayer_config
fi

parse_ramfs_image
parse_machine_jobs

msg "-----------------------------------------------------------------"
msg " MACHINE    : $MACHINE_TYPE"
msg " IMAGE      : $IMAGE_TYPE"
msg " IMAGE CONF : $IMAGE_CONF"
msg " TARGET     : $BB_TARGET"
msg " COMMAND    : $BB_CMD"
msg " OPTION     : $BB_OPT"
msg " SDK        : $BB_SDK ($BB_BUILD_DIR/tmp/deploy/sdk)"
msg " BUILD DIR  : $BB_BUILD_DIR"
msg " DEPLOY DIR : $BB_BUILD_DIR/tmp/deploy/images/$MACHINE_TYPE"
msg "-----------------------------------------------------------------"

if [ $BB_SDK != true ]; then
	if [ ! -z $BB_TARGET ]; then
		bitbake $BB_TARGET $BB_CMD $BB_OPT
	else
		bitbake $IMAGE_TYPE $BB_CMD $BB_OPT
	fi
	copy_deploy_images
	link_result_dir "result"
else
	bitbake -c populate_sdk $IMAGE_TYPE $BB_OPT
	copy_sdk_images
	link_result_dir "SDK"
fi

msg "-----------------------------------------------------------------"
msg " RESULT DIR : $RESULT_OUT"
msg "-----------------------------------------------------------------"
msg "-----------------------------------------------------------------"
msg " bitbake environment set up command:"
msg " $> source $POKY_DIR/oe-init-build-env $BB_BUILD_DIR"
msg "-----------------------------------------------------------------"
