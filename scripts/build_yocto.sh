#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>
#
# $> build_yocto.sh <machine> <image> [options]
#

# Input arguments
TARGET_MACHINE=$1
TARGET_IMAGE=$2

# build macros
MACHINE_SUPPORT=( "nxp3220" )
MACHINE_NAME=${MACHINE_SUPPORT}

BSP_ROOT_DIR=`readlink -e -n "$(cd "$(dirname "$0")" && pwd)/../.."`
BSP_YOCTO_DIR=$BSP_ROOT_DIR/yocto

YOCTO_DISTRO=$BSP_YOCTO_DIR/poky
YOCTO_MACHINE=$BSP_YOCTO_DIR/meta-nexell/meta-nxp3220
YOCTO_BUILD=$BSP_YOCTO_DIR/build
YOCTO_BUILD_TARGET=$YOCTO_BUILD/build-${TARGET_MACHINE}
YOCTO_MACHINE_CONFIGS=$YOCTO_MACHINE/configs/machines
YOCTO_FEATURE_CONFIGS=$YOCTO_MACHINE/configs/images
YOCTO_IMAGE_ROOTFS=$YOCTO_MACHINE/recipes-core/images

BUILD_CONFIG=$YOCTO_BUILD/.config
BUILD_TARGET_CONFIG=$YOCTO_BUILD_TARGET/.build_config
RESULT_TOP=$BSP_YOCTO_DIR/out
RESULT_IMAGE_DIR=$RESULT_TOP/result-${TARGET_MACHINE}
RESULT_IMAGE_LINK="result"
RESULT_SDK_DIR=$RESULT_TOP/SDK-result-${TARGET_MACHINE}
RESULT_SDK_LINK="SDK"

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
	"secure-bootkey.pem.pub.hash.txt"
)

# Copy from BSP tools to result dir
BSP_TOOLS_FILES=(
	"tools/scripts/partmap_fastboot.sh"
	"tools/scripts/partmap_diskimg.sh"
	"tools/scripts/usb-down.sh"
	"tools/scripts/configs/udown.bootloader.sh"
	"tools/scripts/configs/udown.bootloader-secure.sh"
	"tools/bin/linux-usbdownloader"
	"tools/bin/simg2dev"
	"tools/files/partmap_*.txt"
	"tools/files/secure-bl1-enckey.txt"
	"tools/files/secure-bl32-enckey.txt"
	"tools/files/secure-bl32-ivector.txt"
	"tools/files/secure-bootkey.pem"
	"tools/files/secure-userkey.pem"
	"tools/files/secure-jtag-hash.txt"
	"tools/files/secure-bootkey.pem.pub.hash.txt"
	"tools/files/efuse_cfg-aes_enb.txt"
	"tools/files/efuse_cfg-verify_enb-hash0.txt"
	"tools/files/efuse_cfg-sjtag_enb.txt"
)

# Recipe alias
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
)

declare -A TARGET_LOCAL_CONF_VARIABLE=(
	["BSP_ROOT_DIR"]="$BSP_ROOT_DIR"
	["BSP_TARGET_MACHINE"]="$TARGET_MACHINE"
)

TARGET_BBLOCAL_CONF=$YOCTO_BUILD_TARGET/conf/local.conf
TARGET_BBLAYER_CONF=$YOCTO_BUILD_TARGET/conf/bblayers.conf

AVAIL_MACHINE="machine"
AVAIL_IMAGE="image"
AVAIL_FEATURE="feature"
AVAIL_MACHINE_TABLE=""
AVAIL_IMAGE_TABLE=""
AVAIL_FEATURE_TABLE=""

RESULT_DIR=""

function usage () {
	echo ""
	echo "Usage: `basename $0` [machine] [image] [option]"
	echo ""
	echo " machine"
	echo "      : Located at '$(echo $YOCTO_MACHINE_CONFIGS | sed 's|'$BSP_ROOT_DIR'/||')'"
	echo " image"
	echo "      : Located at '$(echo $YOCTO_IMAGE_ROOTFS | sed 's|'$BSP_ROOT_DIR'/||')'"
	echo "      : The image name is prefixed with 'nexell-image-', ex> 'nexell-image-<name>'"
	echo ""
	echo " option"
	echo "  -l : Show available lists (machine, images, recipes, commands ...)"
	echo "  -t : Recipe name to build"
	echo "  -i : Add features to image ex> -i A,B,..."
	echo "  -c : Bitbake build commands"
	echo "  -o : Bitbake option"
	echo "  -v : Enable bitbake '-v' option"
	echo "  -S : Build the SDK"
	echo "  -p : Copy images from deploy dir to result dir"
	echo "  -f : Force overwrite buid conf files to 'local.conf' and 'bblayers.conf'"
	echo "  -j : Determines how many tasks bitbake should run in parallel"
	echo "  -h : Help"
	echo ""
}

function err() {
	echo  -e "\033[0;31m $@\033[0m"
}

function msg() {
	echo  -e "\033[0;33m $@\033[0m"
}

function parse_avail_table () {
	local dir=$1 deli=$2
	local table=$3	# parse table
	local val
	[[ $4 ]] && declare -n avail=$4;

	[ ! -d $dir ] && return;

	cd $dir
	local value=$(find ./ -print \
		2> >(grep -v 'No such file or directory' >&2) | \
		grep -w ".*\.${deli}" | sort)

	for i in $value; do
		i="$(echo "$i" | cut -d'/' -f2)"
		if [ ! -z $(echo "$i" | awk -F".${deli}" '{print $2}') ]; then
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

		val="${val} $(echo "$i" | awk -F".${deli}" '{print $1}')"
		eval "$table=(\"${val}\")"
	done
}

function check_avail_type () {
	local name=$1 table=$2 feature=$3
	local comp=()

	if [[ -z $name ]] && [[ $feature == "$AVAIL_FEATURE" ]]; then
		return
	fi

	for i in ${table}; do
		for n in ${name}; do
			[[ ${i} == ${n} ]] && comp+=($i);
		done
	done

	arr=($name)
	[ ${#comp[@]} -ne 0 ] && [ ${#arr[@]} == ${#comp[@]} ] && return;

	err ""
	err "Not support $feature: $name"
	err "Availiable: $table"
	err ""

	show_avail_lists
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

			ti=${i%=*} ti=${ti%% *}
			tn=${n%=*} tn=${tn%% *}

			# replace
                        if [[ $ti == $tn ]]; then
				i=$(echo "$i" | sed -e "s/[[:space:]]\+/ /g")
				n=$(echo "$n" | sed -e "s/[[:space:]]\+/ /g")
				sed -i -e "s|$n|$i|" $dst
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
	local dst=$TARGET_BBLOCAL_CONF
	local src=$YOCTO_MACHINE_CONFIGS/$TARGET_MACHINE.conf
        local conf=$YOCTO_MACHINE_CONFIGS/local.conf

	msg "---------------------------------------------------------------------------"
	msg " COPY     : $conf"
	msg " TO       : $dst"
	msg "---------------------------------------------------------------------------"

	cp $conf $dst
	[ $? -ne 0 ] && exit 1;

	rep="\"$MACHINE_NAME\""
	sed -i "s/^MACHINE.*/MACHINE = $rep/" $dst
	[ $? -ne 0 ] && exit 1;

	msg "---------------------------------------------------------------------------"
	msg " PARSE    : $src"
	msg " TO       : $dst"
	msg "---------------------------------------------------------------------------"

	echo "" >> $dst
	echo "# PARSING: $src" >> $dst
	merge_conf_file $conf $src $dst
	for i in ${!TARGET_LOCAL_CONF_VARIABLE[@]}; do
		key="$i"
		rep="\"${TARGET_LOCAL_CONF_VARIABLE[$i]//\//\\/}\""
		sed -i "s/^$key =.*/$key = $rep/" $dst
	done
	echo "# PARSING DONE" >> $dst
}

function parse_conf_image () {
        local dst=$TARGET_BBLOCAL_CONF
	local src=( $YOCTO_FEATURE_CONFIGS/${TARGET_IMAGE##*-}.conf )

	for i in $TARGET_FEATURES; do
		src+=( $YOCTO_FEATURE_CONFIGS/$i.conf )
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
	local dst=$TARGET_BBLOCAL_CONF
        local src=$YOCTO_FEATURE_CONFIGS/sdk.conf

	[ $BB_SDK != true ] && return;

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
	local dst=$TARGET_BBLOCAL_CONF
	local rep="\"$TARGET_IMAGE\""

	sed -i "s/^INITRAMFS_IMAGE.*/INITRAMFS_IMAGE = $rep/" $dst
}

function parse_conf_jobs () {
	[ -z $BB_JOBS ] && return;

	local conf=$TARGET_BBLOCAL_CONF
	if grep -q BB_NUMBER_THREADS "$conf"; then
		rep="\"$BB_JOBS\""
		sed -i "s/^BB_NUMBER_THREADS.*/BB_NUMBER_THREADS = $rep/" $conf
	else
		echo "" >> $TARGET_BBLOCAL_CONF
		echo "BB_NUMBER_THREADS = \"${BB_JOBS}\"" >> $conf
	fi
}

function parse_conf_bblayer () {
        local dst=$TARGET_BBLAYER_CONF
	local src=$YOCTO_MACHINE_CONFIGS/bblayers.conf

	msg "---------------------------------------------------------------------------"
	msg " COPY     : $src"
	msg " TO       : $dst"
	msg "---------------------------------------------------------------------------"

        cp $src $dst
	[ $? -ne 0 ] && exit 1;

	local rep="\"${BSP_YOCTO_DIR//\//\\/}\""
	sed -i "s/^BSPPATH :=.*/BSPPATH := $rep/" $dst
}

function setup_build_env () {
	mkdir -p $(dirname $YOCTO_BUILD_TARGET)

	# run oe-init-build-env
	source $YOCTO_DISTRO/oe-init-build-env $YOCTO_BUILD_TARGET >/dev/null 2>&1
	msg "---------------------------------------------------------------------------"
	msg " Bitbake Evironment Setup:"
	msg " $> source $YOCTO_DISTRO/oe-init-build-env $YOCTO_BUILD_TARGET"
	msg "---------------------------------------------------------------------------"
}

function check_build_config () {
	local result=$1 # return value
        local mach="$(echo $TARGET_MACHINE | cut -d'-' -f 1)"
	local config=${TARGET_MACHINE}+${TARGET_IMAGE}
	local previous

        if [ ! -f $TARGET_BBLOCAL_CONF ]; then
                err "Not build setup environment : '$TARGET_BBLOCAL_CONF' ..."
                err "$> source poky/oe-init-build-env <build dir>/<machin type>"
		exit 1;
	fi

	if [[ ! -z $TARGET_FEATURES ]]; then
		for i in $TARGET_FEATURES; do
			config=${config}+${i}
		done
	fi

	[ $BB_SDK == true ] && config=${config}+SDK;
	[ -e $BUILD_TARGET_CONFIG ] && previous="$(cat $BUILD_TARGET_CONFIG)";

	local machine="$(echo $(echo $(find $TARGET_BBLOCAL_CONF -type f -exec grep -w -h 'MACHINE' {} \;) | \
			cut -d'"' -f 2) | cut -d'"' -f 1)"

        if [[ $mach == $machine ]]; then
		if [[ $previous != $config ]]; then
			[ -e $BUILD_CONFIG ] && rm $BUILD_CONFIG;
			[ -e $BUILD_TARGET_CONFIG ] && rm $BUILD_TARGET_CONFIG;
			echo $config >> $BUILD_CONFIG;
			echo $config >> $BUILD_TARGET_CONFIG;
			eval "$result=(\"1\")"; return
        	fi
		eval "$result=(\"0\")"; return
        fi

	echo $config >> $BUILD_CONFIG;
	echo $config >> $BUILD_TARGET_CONFIG;

	eval "$result=(\"1\")"
}

function show_avail_lists () {
	local config
	[ -e $BUILD_CONFIG ] && config="$(cat $BUILD_CONFIG)";
	msg "=================================================================================="
	msg "Config - $config "
	msg "=================================================================================="

	msg "[Machine]"
	msg "\t- $(echo $YOCTO_MACHINE_CONFIGS | sed 's|'$BSP_ROOT_DIR'/||')"
	msg "\t---------------------------------------------------------------------------"
	msg "\t${AVAIL_MACHINE_TABLE}"
	msg "\t---------------------------------------------------------------------------"

	msg "[Image]"
	msg "\t- $(echo $YOCTO_IMAGE_ROOTFS | sed 's|'$BSP_ROOT_DIR'/||')"
	msg "\t---------------------------------------------------------------------------"
	msg "\t ${AVAIL_IMAGE_TABLE}"
	msg "\t---------------------------------------------------------------------------"

	msg "[Features] option: '-i a,b,...'"
	msg "\t- $(echo $YOCTO_FEATURE_CONFIGS | sed 's|'$BSP_ROOT_DIR'/||')"
	msg "\t---------------------------------------------------------------------------"
	msg "\t ${AVAIL_FEATURE_TABLE}"
	msg "\t---------------------------------------------------------------------------"

	msg ""
	msg "[Recipe] option: '-t'"
	for i in "${!BUILD_RECIPES[@]}"; do
		msg "\t$i (${BUILD_RECIPES[$i]})"
	done
	msg "\t... Else Recipe name"
	msg ""
}

function copy_deploy_image () {
	local deploy=$YOCTO_BUILD_TARGET/tmp/deploy/images/$MACHINE_NAME
	local retdir="$(echo $TARGET_IMAGE | cut -d'.' -f 1)"

	if [ ! -d $deploy ]; then
		err "No directory : $deploy"
		exit 1
	fi

	RESULT_DIR=${RESULT_IMAGE_DIR}-${retdir##*-}

	msg "---------------------------------------------------------------------------"
	msg " DEPLOY     : $deploy"
	msg " RESULT     : $RESULT_DIR"
	msg "---------------------------------------------------------------------------"

	mkdir -p $RESULT_DIR
	[ $? -ne 0 ] && exit 1;

	cd $deploy
	for file in "${BSP_RESULT_FILES[@]}"; do
		local files=$(find $file -print \
			2> >(grep -v 'No such file or directory' >&2) | sort)

		for n in $files; do
			[ ! -e $n ] && continue;

			to=$RESULT_DIR/$n
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

function copy_deploy_sdk () {
	local deploy=$YOCTO_BUILD_TARGET/tmp/deploy/sdk
	local retdir="$(echo $TARGET_IMAGE | cut -d'.' -f 1)"

	if [[ ! -d $deploy ]]; then
		err "No directory : $deploy"
		exit 1
	fi

	RESULT_DIR=${RESULT_SDK_DIR}-${retdir##*-}
	mkdir -p $RESULT_DIR
	[ $? -ne 0 ] && exit 1;

	cp -a $deploy/* $RESULT_DIR/
}

function copy_tools_files () {
	local retdir="$(echo $TARGET_IMAGE | cut -d'.' -f 1)"

	RESULT_DIR=${RESULT_IMAGE_DIR}-${retdir##*-}
	mkdir -p $RESULT_DIR
	[ $? -ne 0 ] && exit 1;

	cd $BSP_ROOT_DIR
	for file in "${BSP_TOOLS_FILES[@]}"; do
		local files=$(find $file -print \
			2> >(grep -v 'No such file or directory' >&2) | sort)

		for n in $files; do
			if [[ -d $n ]]; then
				continue
			fi

			to=$RESULT_DIR/$(basename $n)
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
	local link=$1
	local ret=$(basename $RESULT_DIR)

	cd $RESULT_TOP
	[[ -e $to ]] && [[ $link ==  $ret ]] && return;

	rm -f $link;
	ln -s $ret $link
}

CMD_PARSE=false
CMD_COPY=false
BB_OPTION=""
BB_VERBOSE=""
BB_SDK=false
BB_JOBS=
BB_RECIPE=""
BB_CMD=""
TARGET_FEATURES=

function parse_arguments () {
	ARGS=$(getopt -o lSfhpt:i:c:o:j:v -- "$@");
    	eval set -- "$ARGS";

    	while true; do
		case "$1" in
		-l )
			show_avail_lists
			exit 0
			;;
		-t )
			for i in ${!BUILD_RECIPES[@]}; do
				[ $i != $2 ] && continue;
				BB_RECIPE=${BUILD_RECIPES[$i]}; shift 2;
				break;
			done
			if [ -z $BB_RECIPE ]; then
				BB_RECIPE=$2; shift 2;
			fi
			;;
		-i )
			TARGET_FEATURES=""
			local arr=(${2//,/ })
			for i in "${arr[@]}"; do
				TARGET_FEATURES="$TARGET_FEATURES $i"
			done
			shift 2
			;;
		-c )
			for i in ${!BUILD_COMMANDS[@]}; do
				[ $i != $2 ] && continue;
				BB_CMD="-c ${BUILD_COMMANDS[$i]}"; shift 2;
				break;
			done
			if [ -z $BB_CMD ]; then
				BB_CMD="-c $2"; shift 2;
			fi
			;;
		-o )	BB_OPTION=$2; shift 2;;
		-S )	BB_SDK=true; shift 1;;
		-f )	CMD_PARSE=true;	shift 1;;
		-p )	CMD_COPY=true; shift 1;;
		-j )	BB_JOBS=$2; shift 2;;
		-v )	BB_VERBOSE="-v"; shift 1;;
		-h )	usage
			show_avail_lists
			exit 1
			;;
		-- )
			break ;;
		esac
	done
}

###############################################################################
# Run build commands
###############################################################################
parse_avail_table $YOCTO_MACHINE_CONFIGS "conf" AVAIL_MACHINE_TABLE MACHINE_SUPPORT
parse_avail_table $YOCTO_FEATURE_CONFIGS "conf" AVAIL_FEATURE_TABLE
parse_avail_table $YOCTO_IMAGE_ROOTFS "bb" AVAIL_IMAGE_TABLE

parse_arguments $@

check_avail_type "$TARGET_MACHINE" "$AVAIL_MACHINE_TABLE" "$AVAIL_MACHINE"
check_avail_type "$TARGET_IMAGE" "$AVAIL_IMAGE_TABLE" "$AVAIL_IMAGE"
check_avail_type "$TARGET_FEATURES" "$AVAIL_FEATURE_TABLE" "$AVAIL_FEATURE"

setup_build_env

check_build_config _reconfig_
if [ $_reconfig_ == 1 ] || [ $CMD_PARSE == true ]; then
	parse_conf_machine
	parse_conf_image
	parse_conf_sdk
	parse_conf_bblayer
fi

parse_conf_ramfs
parse_conf_jobs

msg "---------------------------------------------------------------------------"
msg " TARGET     : $TARGET_MACHINE"
msg " IMAGE      : $TARGET_IMAGE + $TARGET_FEATURES"
msg " RECIPE     : $BB_RECIPE"
msg " COMMAND    : $BB_CMD"
msg " OPTION     : $BB_OPTION $BB_VERBOSE"
msg " SDK        : $BB_SDK"
msg " BUILD DIR  : $YOCTO_BUILD_TARGET"
msg " DEPLOY DIR : $YOCTO_BUILD_TARGET/tmp/deploy/images/$MACHINE_NAME"
msg " SDK DIR    : $YOCTO_BUILD_TARGET/tmp/deploy/sdk"
msg "---------------------------------------------------------------------------"

# Build and copy result images
if [ $BB_SDK != true ]; then
	if [ $CMD_COPY == false ]; then
		if [[ ! -z $BB_RECIPE ]]; then
			bitbake $BB_RECIPE $BB_CMD $BB_OPTION $BB_VERBOSE
		else
			bitbake $TARGET_IMAGE $BB_CMD $BB_OPTION $BB_VERBOSE
			[ $? -ne 0 ] && exit 1;
		fi
	fi

	if [[ -z $BB_CMD ]]; then
		copy_deploy_image
		copy_tools_files
		link_result_dir $RESULT_IMAGE_LINK
	fi
else
	if [ $CMD_COPY == false ]; then
		bitbake -c populate_sdk $TARGET_IMAGE $BB_OPTION $BB_VERBOSE
		[ $? -ne 0 ] && exit 1;
	fi

	copy_deploy_sdk
	link_result_dir $RESULT_SDK_LINK
fi

msg "---------------------------------------------------------------------------"
msg " RESULT DIR : $RESULT_DIR"
msg "---------------------------------------------------------------------------"
msg " Bitbake Environment Setup:"
msg " $> source $YOCTO_DISTRO/oe-init-build-env $YOCTO_BUILD_TARGET"
msg "---------------------------------------------------------------------------"
