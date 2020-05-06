#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>
#
# $> build_yocto.sh <machine> <image> [options]
#

# Input arguments
TARGET_MACHINE=$1
TARGET_IMAGE=$2

[[ $TARGET_MACHINE == "-"* ]] && TARGET_MACHINE="";
[[ $TARGET_MACHINE == menuconfig ]] && TARGET_MACHINE="";
[[ $TARGET_IMAGE == "-"* ]] && TARGET_IMAGE="";

# build macros
MACHINE_SUPPORT=( "nxp3220" )

BSP_ROOT_DIR=$(realpath $(dirname `realpath ${0}`)/../..)
BSP_YOCTO_DIR=$BSP_ROOT_DIR/yocto

YOCTO_DISTRO=$BSP_YOCTO_DIR/poky
YOCTO_META=$BSP_YOCTO_DIR/meta-nexell/meta-nxp3220
YOCTO_MACHINE_CONFIGS=$YOCTO_META/configs/machines
YOCTO_FEATURE_CONFIGS=$YOCTO_META/configs/images
YOCTO_IMAGE_ROOTFS=$YOCTO_META/recipes-core/images
YOCTO_BUILD_DIR=$BSP_YOCTO_DIR/build

RESULT_DIR=$BSP_YOCTO_DIR/out
RESULT_IMAGE_LINK="result"
RESULT_SDK_LINK="SDK"

# Copy from deploy to result dir
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
	"u-boot-BUILD_MACHINE_NAME-1.0-r0.bin"
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

# Copy from tools to result dir
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
BB_RECIPE_ALIAS=(
	"bl1 = bl1-nxp3220"
	"bl2 = bl2-nxp3220"
	"bl32 = bl32-nxp3220"
	"uboot = virtual/bootloader"
	"kernel = virtual/kernel"
	"bootimg = nexell-bootimg"
	"dataimg = nexell-dataimg"
	"miscimg = nexell-miscimg"
	"recoveryimg = nexell-recoveryimg"
	"swuimg = nexell-swuimg"
)

declare -A BB_COMMAND_ALIAS=(
  	["clean"]="buildclean"
  	["distclean"]="cleansstate"
)

declare -A BB_LOCAL_CONF_CONFIGURE=(
	["BSP_ROOT_DIR"]="$BSP_ROOT_DIR"
	["BSP_TARGET_MACHINE"]=""
)

AVAIL_MACHINE="machine"
AVAIL_IMAGE="image"
AVAIL_FEATURE="feature"
AVAIL_MACHINE_TABLE=""
AVAIL_IMAGE_TABLE=""
AVAIL_FEATURE_TABLE=""

BUILD_CONFIG=$YOCTO_BUILD_DIR/.config

function setup_env () {
	# update global variables
	BUILD_MACHINE_NAME="$(echo $TARGET_MACHINE | cut -d'-' -f 1)"
	BUILD_TARGET_DIR=$YOCTO_BUILD_DIR/build-${TARGET_MACHINE}
	BUILD_TARGET_CONFIG=$BUILD_TARGET_DIR/.config
	TARGET_LOCAL_CONF=$BUILD_TARGET_DIR/conf/local.conf
	TARGET_LAYER_CONF=$BUILD_TARGET_DIR/conf/bblayers.conf
	RESULT_IMAGE_DIR=$RESULT_DIR/result-${TARGET_MACHINE}
	RESULT_SDK_DIR=$RESULT_DIR/SDK-result-${TARGET_MACHINE}
	RESULT_TARGET_DIR=""

	BB_LOCAL_CONF_CONFIGURE["BSP_TARGET_MACHINE"]=$TARGET_MACHINE
}

function err () { echo -e "\033[0;31m$@\033[0m"; }
function msg () { echo -e "\033[0;33m$@\033[0m"; }

function usage () {
	echo ""
	echo "Usage: `basename $0` [machine] [image] [option] / menuconfig"
	echo ""
	echo " machine"
	echo "      : Located at '$(echo $YOCTO_MACHINE_CONFIGS | sed 's|'$BSP_ROOT_DIR'/||')'"
	echo " image"
	echo "      : Located at '$(echo $YOCTO_IMAGE_ROOTFS | sed 's|'$BSP_ROOT_DIR'/||')'"
	echo "      : The image name is prefixed with 'nexell-image-', ex> 'nexell-image-<name>'"
	echo ""
	echo " option"
	echo "  -l : Show available lists and build status"
	echo "  -t : Bitbake recipe name or recipe alias to build"
	echo "  -i : Add features to image, Must be nospace each features, Depend on order ex> -i A,B,..."
	echo "  -c : Bitbake build commands"
	echo "  -o : Bitbake build option"
	echo "  -v : Enable bitbake verbose option"
	echo "  -S : Build the SDK image (-c populate_sdk)"
	echo "  -p : Copy images from deploy dir to result dir"
	echo "  -f : Force update buid conf file (local.conf, bblayers.conf)"
	echo "  -j : Determines how many tasks bitbake should run in parallel"
	echo "  -h : Help"
	echo ""
}

function parse_avail_target () {
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
		if [[ -n $(echo "$i" | awk -F".${deli}" '{print $2}') ]]; then
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

function check_avail_target () {
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
	err " Not support $feature: $name"
	err " Availiable: $table"
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
	local dst=$TARGET_LOCAL_CONF
        local src=$YOCTO_MACHINE_CONFIGS/local.conf
	local cmp=$YOCTO_MACHINE_CONFIGS/$TARGET_MACHINE.conf

	msg "---------------------------------------------------------------------------"
	msg " COPY     : $src"
	msg " TO       : $dst"
	msg "---------------------------------------------------------------------------"

	cp $src $dst
	[ $? -ne 0 ] && exit 1;

	rep="\"$BUILD_MACHINE_NAME\""
	sed -i "s/^MACHINE.*/MACHINE = $rep/" $dst
	[ $? -ne 0 ] && exit 1;

	msg "---------------------------------------------------------------------------"
	msg " PARSE    : $cmp"
	msg " TO       : $dst"
	msg "---------------------------------------------------------------------------"

	echo "" >> $dst
	echo "# PARSING: $cmp" >> $dst
	merge_conf_file $src $cmp $dst
	for i in ${!BB_LOCAL_CONF_CONFIGURE[@]}; do
		key="$i"
		rep="\"${BB_LOCAL_CONF_CONFIGURE[$i]//\//\\/}\""
		sed -i "s/^$key =.*/$key = $rep/" $dst
	done
	echo "# PARSING DONE" >> $dst
}

function parse_conf_image () {
        local dst=$TARGET_LOCAL_CONF
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

        src=$YOCTO_FEATURE_CONFIGS/sdk.conf
	[ $TARGET_SDK != true ] && return;

	msg "---------------------------------------------------------------------------"
	msg " PARSE    : $src"
	msg " TO       : $dst"
	msg "---------------------------------------------------------------------------"

	echo "" >> $dst
	echo "# PARSING: $src" >> $dst
	merge_conf_file $dst $src $dst
	echo "# PARSING DONE" >> $dst
}

function parse_conf_opts () {
	local dst=$TARGET_LOCAL_CONF
	local rep="\"$TARGET_IMAGE\""

	sed -i "s/^INITRAMFS_IMAGE.*/INITRAMFS_IMAGE = $rep/" $dst

	[[ -z $BB_JOBS ]] && return;
	if grep -q BB_NUMBER_THREADS "$dst"; then
		rep="\"$BB_JOBS\""
		sed -i "s/^BB_NUMBER_THREADS.*/BB_NUMBER_THREADS = $rep/" $dst
	else
		echo "" >> $TARGET_LOCAL_CONF
		echo "BB_NUMBER_THREADS = \"${BB_JOBS}\"" >> $dst
	fi
}

function parse_conf_bblayer () {
        local dst=$TARGET_LAYER_CONF
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

function menu_target () {
	local table=$1 feature=$2
	local result=$3 # return value
	local select
	local -a entry

	for i in ${table}; do
		stat="OFF"
		entry+=( "$i" )
		entry+=( "$feature  " )
		[[ $i == ${!result} ]] && stat="ON";
		entry+=( "$stat" )
	done

	which whiptail > /dev/null 2>&1
	if [ ! $? -eq 0 ]; then
		echo "Please install the whiptail"
		exit 1
	fi

	select=$(whiptail --title "Target $feature" \
		--radiolist "Choose a $feature" 0 50 ${#entry[@]} -- "${entry[@]}" \
		3>&1 1>&2 2>&3)
	[[ -z $select ]] && exit 1;

	eval "$result=(\"${select}\")"
}

function menu_sdk () {
	local result=$1 # return value
	local default=""

	[ ${!result} == true ] && default="--defaultno";
	if (whiptail --title "Image type" --yesno --yes-button "rootfs" --no-button "sdk" \
		$default "Build image type" 8 78); then
		eval "$result=(\"false\")"
	else
		eval "$result=(\"true\")"
	fi
}

function menu_feature () {
	local table=$1 feature=$2
	local result=$3 # return value
	local message="*** Depend on order ***\n\n"
	local entry select

	for i in ${table}; do
		[[ $i == "$(echo $TARGET_IMAGE | cut -d'-' -f 3-)" ]] && continue;
		[[ $i == *"sdk"* ]] && continue;
		entry+=" ${i}\n"
	done

	message+=${entry}
	select=$(whiptail --inputbox "$message" 0 78 "${!result}" --nocancel \
			--title "Add $feature" 3>&1 1>&2 2>&3)
	select=$(echo $select | tr " " " ")

	eval "$result=(\"${select}\")"
}

function menu_save () {
	if ! (whiptail --title "Save/Exit" --yesno "Save" 8 78); then
		exit 1;
	fi
}

function set_config_value () {
	local file=$1 machine=$2 image=$3 features=$4 sdk=$5

	echo "MACHINE = ${machine}" >> ${file};
	echo "IMAGE = ${image}" >> ${file};
	echo "FEATURES = ${features}" >> ${file};
	echo "SDK = ${sdk}" >> ${file};
}

function get_config_value () {
	local file=$1 machine=$2 image=$3 features=$4 sdk=$5

	ret=$(echo $(sed -n '/^\<MACHINE\>/p' $file) | cut -d'=' -f 2)
	eval "$machine=(\"${ret# *}\")"
	ret=$(echo $(sed -n '/^\<IMAGE\>/p' $file) | cut -d'=' -f 2)
	eval "$image=(\"${ret# *}\")"
	ret=$(echo $(sed -n '/^\<FEATURES\>/p' $file) | cut -d'=' -f 2)
	eval "$features=(\"${ret# *}\")"
	ret=$(echo $(sed -n '/^\<SDK\>/p' $file) | cut -d'=' -f 2)
	eval "$sdk=(\"${ret# *}\")"
}

function parse_build_config () {
	[[ -n $TARGET_MACHINE ]] && setup_env;

	if  [[ -z $TARGET_MACHINE ]] && [ -e $BUILD_CONFIG ] ; then
		get_config_value "$BUILD_CONFIG" TARGET_MACHINE TARGET_IMAGE TARGET_FEATURES TARGET_SDK
	elif [[ -n $TARGET_MACHINE ]] && [ -e $BUILD_TARGET_CONFIG ]; then
		get_config_value "$BUILD_TARGET_CONFIG" TARGET_MACHINE TARGET_IMAGE TARGET_FEATURES TARGET_SDK
	fi
}

function check_build_config () {
	local result=$1 # return value
	local newconfig="${TARGET_MACHINE}:${TARGET_IMAGE}:"
	local oldconfig
	local match=false

        if [ ! -f $TARGET_LOCAL_CONF ]; then
                err " Not build setup: '$TARGET_LOCAL_CONF' ..."
                err " $> source poky/oe-init-build-env <build dir>/<machin type>"
		exit 1;
	fi

	[[ -n $TARGET_FEATURES ]] && newconfig+="$TARGET_FEATURES";
	if [ $TARGET_SDK == true ];
	then newconfig+=":true";
	else newconfig+=":false";
	fi

	if [ -e $BUILD_TARGET_CONFIG ]; then
		local m i f s
		get_config_value "$BUILD_TARGET_CONFIG" m i f s
		oldconfig="${m}:${i}:${f}:${s}"
	fi

	[ -e $BUILD_CONFIG ] && rm -f $BUILD_CONFIG;
	[ -e $BUILD_TARGET_CONFIG ] && rm -f $BUILD_TARGET_CONFIG;

	set_config_value "$BUILD_CONFIG" "$TARGET_MACHINE" "$TARGET_IMAGE" "$TARGET_FEATURES" "$TARGET_SDK"
	set_config_value "$BUILD_TARGET_CONFIG" "$TARGET_MACHINE" "$TARGET_IMAGE" "$TARGET_FEATURES" "$TARGET_SDK"

	local machine=$(echo $(grep ^MACHINE $TARGET_LOCAL_CONF) | cut -d'"' -f 2 | tr -d ' ')
	if [ ${#MACHINE_SUPPORT[@]} -ne 0 ]; then
		for n in "${MACHINE_SUPPORT[@]}"; do
			if [[ $machine == $n ]]; then
				match=true
				break;
			fi
		done
	fi

	if [[ $newconfig == $oldconfig ]] && [ $match == true ]; then
		eval "$result=(\"0\")"
	else
		eval "$result=(\"1\")"
	fi
}

function show_avail_lists () {
	message="$TARGET_MACHINE $TARGET_IMAGE "
	if [[ -n $TARGET_FEATURES ]]; then
		message+="-i "
		message+=$(echo ${TARGET_FEATURES} | tr " " ",")
	fi
	[ $TARGET_SDK == true ] && message+=" -S";

	msg "=================================================================================="
	msg " MACHINE   = $TARGET_MACHINE"
	msg " IMAGE     = $TARGET_IMAGE"
	msg " FEATURES  = $TARGET_FEATURES"
	msg " SDK       = $TARGET_SDK"
	msg " Command   = $> ./tools/scripts/`basename $0` $message"
	msg "=================================================================================="

	msg " [MACHINE]  $(echo $YOCTO_MACHINE_CONFIGS | sed 's|'$BSP_ROOT_DIR'/||')"
	msg "\t---------------------------------------------------------------------------"
	msg "\t${AVAIL_MACHINE_TABLE}"
	msg "\t---------------------------------------------------------------------------"
	msg " "
	msg " [IMAGE]    $(echo $YOCTO_IMAGE_ROOTFS | sed 's|'$BSP_ROOT_DIR'/||')"
	msg "\t---------------------------------------------------------------------------"
	msg "\t ${AVAIL_IMAGE_TABLE}"
	msg "\t---------------------------------------------------------------------------"
	msg " "
	msg " [FEATURES] $(echo $YOCTO_FEATURE_CONFIGS | sed 's|'$BSP_ROOT_DIR'/||')"
	msg "            '-i feature_a,feature_b,...'"
	msg "\t---------------------------------------------------------------------------"
	msg "\t ${AVAIL_FEATURE_TABLE}"
	msg "\t---------------------------------------------------------------------------"
	msg ""
	msg " [RECIPE]   '-t recipe'"
	msg "\t- Recipe alias:"
	for i in "${!BB_RECIPE_ALIAS[@]}"; do
		msg "\t  ${BB_RECIPE_ALIAS[$i]}"
	done
	msg ""
}

function copy_result_image () {
	local deploy=$BUILD_TARGET_DIR/tmp/deploy/images/$BUILD_MACHINE_NAME
	local retdir="$(echo $TARGET_IMAGE | cut -d'.' -f 1)"

	if [ ! -d $deploy ]; then
		err " No such directory : $deploy"
		exit 1
	fi

	RESULT_TARGET_DIR=${RESULT_IMAGE_DIR}-${retdir##*-}
	msg "---------------------------------------------------------------------------"
	msg " DEPLOY     : $deploy"
	msg " RESULT     : $RESULT_TARGET_DIR"
	msg "---------------------------------------------------------------------------"

	mkdir -p $RESULT_TARGET_DIR
	[ $? -ne 0 ] && exit 1;

	cd $deploy
	for file in "${BSP_RESULT_FILES[@]}"; do
		[[ $file == *BUILD_MACHINE_NAME* ]] && file=$(echo $file | sed "s/BUILD_MACHINE_NAME/$BUILD_MACHINE_NAME/")

		local files=$(find $file -print \
			2> >(grep -v 'No such file or directory' >&2) | sort)

		for n in $files; do
			[ ! -e $n ] && continue;

			to=$RESULT_TARGET_DIR/$n
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

function copy_result_sdk () {
	local deploy=$BUILD_TARGET_DIR/tmp/deploy/sdk
	local retdir="$(echo $TARGET_IMAGE | cut -d'.' -f 1)"

	if [[ ! -d $deploy ]]; then
		err " No such directory : $deploy"
		exit 1
	fi

	RESULT_TARGET_DIR=${RESULT_SDK_DIR}-${retdir##*-}
	msg "---------------------------------------------------------------------------"
	msg " DEPLOY     : $deploy"
	msg " RESULT     : $RESULT_TARGET_DIR"
	msg "---------------------------------------------------------------------------"

	mkdir -p $RESULT_TARGET_DIR
	[ $? -ne 0 ] && exit 1;

	cp -a $deploy/* $RESULT_TARGET_DIR/
}

function copy_result_tools () {
	local retdir="$(echo $TARGET_IMAGE | cut -d'.' -f 1)"

	RESULT_TARGET_DIR=${RESULT_IMAGE_DIR}-${retdir##*-}
	mkdir -p $RESULT_TARGET_DIR
	[ $? -ne 0 ] && exit 1;

	cd $BSP_ROOT_DIR
	for file in "${BSP_TOOLS_FILES[@]}"; do
		local files=$(find $file -print \
			2> >(grep -v 'No such file or directory' >&2) | sort)

		for n in $files; do
			if [[ -d $n ]]; then
				continue
			fi

			to=$RESULT_TARGET_DIR/$(basename $n)
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
	local ret=$(basename $RESULT_TARGET_DIR)

	cd $RESULT_DIR
	[[ -e $to ]] && [[ $link ==  $ret ]] && return;

	rm -f $link;
	ln -s $ret $link
}

CMD_PARSE=false
CMD_COPY=false
BB_OPTION=""
BB_VERBOSE=""
BB_JOBS=
BB_RECIPE=""
BB_CMD=""
TARGET_SDK=false
TARGET_FEATURES=""

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
			for i in ${!BB_RECIPE_ALIAS[@]}; do
				key=$(echo ${BB_RECIPE_ALIAS[$i]} | cut -d'=' -f 1 | tr -d ' ')
				[ $key != $2 ] && continue;
				BB_RECIPE=$(echo ${BB_RECIPE_ALIAS[$i]} | cut -d'=' -f 2 | tr -d ' ')
				shift 2;
				break;
			done
			if [[ -z $BB_RECIPE ]]; then
				BB_RECIPE=$2; shift 2;
			fi
			;;
		-i )
			local arr=(${2//,/ })
			TARGET_FEATURES=$(echo "${arr[*]}" | tr ' ' ' ')
			shift 2
			;;
		-c )
			for i in ${!BB_COMMAND_ALIAS[@]}; do
				[ $i != $2 ] && continue;
				BB_CMD="-c ${BB_COMMAND_ALIAS[$i]}"; shift 2;
				break;
			done
			if [[ -z $BB_CMD ]]; then
				BB_CMD="-c $2"; shift 2;
			fi
			;;
		-o )	BB_OPTION=$2; shift 2;;
		-S )	TARGET_SDK=true; shift 1;;
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

function setup_bitbake () {
	setup_env
	mkdir -p $YOCTO_BUILD_DIR

	# run oe-init-build-env
	source $YOCTO_DISTRO/oe-init-build-env $BUILD_TARGET_DIR >/dev/null 2>&1
	msg ""
	msg " Bitbake Setup:"
	msg " $> source $YOCTO_DISTRO/oe-init-build-env $BUILD_TARGET_DIR\n"
}

function run_build ()
{
	msg " MACHINE   = $TARGET_MACHINE"
	msg " IMAGE     = $TARGET_IMAGE"
	msg " FEATURES  = $TARGET_FEATURES"
	msg " SDK       = $TARGET_SDK"
	msg " Recipe    = $BB_RECIPE"
	msg " Command   = $BB_CMD"
	msg " Option    = $BB_OPTION $BB_VERBOSE"
	msg " Image dir = $BUILD_TARGET_DIR/tmp/deploy/images/$BUILD_MACHINE_NAME"
	msg " SDK   dir = $BUILD_TARGET_DIR/tmp/deploy/sdk"

	if [ $CMD_COPY == false ]; then
		if [[ -n $BB_RECIPE ]]; then
			__TARGET=$BB_RECIPE
		else
			__TARGET=$TARGET_IMAGE
			[ $TARGET_SDK == true ] && BB_CMD="-c populate_sdk"
		fi

		msg "---------------------------------------------------------------------------"
		msg " $> bitbake $__TARGET $BB_CMD $BB_OPTION $BB_VERBOSE"
		msg "---------------------------------------------------------------------------\n"

		bitbake $__TARGET $BB_CMD $BB_OPTION $BB_VERBOSE
		[ $? -ne 0 ] && exit 1;
	fi

	if [[ -z $BB_CMD ]]; then
		if [ $TARGET_SDK == false ]; then
			copy_result_image
			copy_result_tools
			link_result_dir $RESULT_IMAGE_LINK
		else
			copy_result_sdk
			link_result_dir $RESULT_SDK_LINK
		fi
	fi

	msg "---------------------------------------------------------------------------"
	msg " Bitbake Setup:"
	msg " $> source $YOCTO_DISTRO/oe-init-build-env $BUILD_TARGET_DIR"
	msg "---------------------------------------------------------------------------\n"
}

###############################################################################
# Run build
###############################################################################

parse_avail_target $YOCTO_MACHINE_CONFIGS "conf" AVAIL_MACHINE_TABLE MACHINE_SUPPORT
parse_avail_target $YOCTO_FEATURE_CONFIGS "conf" AVAIL_FEATURE_TABLE
parse_avail_target $YOCTO_IMAGE_ROOTFS "bb" AVAIL_IMAGE_TABLE

if [[ $1 == "menuconfig" ]] || [[ -z $TARGET_MACHINE ]] || [[ -z $TARGET_IMAGE ]]; then
	parse_build_config
fi

parse_arguments $@

if [[ $1 == "menuconfig" ]]; then
	menu_target "$AVAIL_MACHINE_TABLE" "$AVAIL_MACHINE" TARGET_MACHINE
	menu_target "$AVAIL_IMAGE_TABLE" "$AVAIL_IMAGE" TARGET_IMAGE
	menu_sdk TARGET_SDK
	menu_feature "$AVAIL_FEATURE_TABLE" "$AVAIL_FEATURE" TARGET_FEATURES
	menu_save
fi

check_avail_target "$TARGET_MACHINE" "$AVAIL_MACHINE_TABLE" "$AVAIL_MACHINE"
check_avail_target "$TARGET_IMAGE" "$AVAIL_IMAGE_TABLE" "$AVAIL_IMAGE"
check_avail_target "$TARGET_FEATURES" "$AVAIL_FEATURE_TABLE" "$AVAIL_FEATURE"

setup_bitbake

check_build_config _ret_
if [ $_ret_ == 1 ] || [ $CMD_PARSE == true ]; then
	parse_conf_machine
	parse_conf_image
	parse_conf_bblayer
fi
parse_conf_opts

if [[ $1 == "menuconfig" ]]; then
	msg "---------------------------------------------------------------------------"
	msg "$( cat $BUILD_CONFIG | sed -e 's/^/ /' )"
	msg "---------------------------------------------------------------------------"
	exit 0;
fi

run_build
