#!/bin/bash

BASEDIR=$(cd "$(dirname "$0")" && pwd)
TOPDIR=`readlink -e -n "$BASEDIR/../.."`
RESULT="$BASEDIR/../../result"	# must be set with Relative path

BL_TOOLCHAIN_PATH=`readlink -e -n "$BASEDIR/../crosstools/gcc-arm-none-eabi-6-2017-q2-update/bin/"`

# "BSP Name"
# "TOOLCHAIN PATH"
# "CROSS_COMPILE NAME"
# "Target Name" "Path" "ARCH=arm/arm64" "defconfig" "Output"
BUILD_IMAGES_VTK=(
	"vtk"
	"`readlink -e -n "$BASEDIR/../crosstools/gcc-linaro-7.2.1-2017.11-x86_64_arm-linux-gnueabihf/bin"`"
	"arm-linux-gnueabihf-"
	"bl1"  		"$TOPDIR/bl1/bl1-nxp3220" 	"arm" "" 				"bl1-nxp3220.bin.raw"
	"bl2"  		"$TOPDIR/bl2/bl2-nxp3220" 	"arm" "" 				"bl2-vtk.bin.raw"
	"bl32" 		"$TOPDIR/bl32/bl32-nxp3220" 	"arm" "" 				"bl32.bin.raw"
	"u-boot" 	"$TOPDIR/u-boot/u-boot-2017.5"	"arm" "nxp3220_vtk_defconfig" 		"u-boot.bin"
	"kernel" 	"$TOPDIR/kernel/kernel-4.14" 	"arm" "nxp3220_vtk_defconfig"		"arch/arm/boot/zImage"
	"dts" 		"$TOPDIR/kernel/kernel-4.14" 	"arm" "nxp3220-vtk.dtb"			"arch/arm/boot/dts/nxp3220-vtk.dtb"
	"br2" 	 	"$TOPDIR/rootfs/buildroot" 	""    "nxp3220_vtk_sysv_defconfig" 	"output/target"
)
BUILD_ARRAY_COLs=5

mkdir -p $RESULT

RESULT=`readlink -e -n "$BASEDIR/../../result"`
SHELL_NAME=$(basename $0)

function dmsg() {
	local dmsg=${BUILD_DEBUG:-"false"}
	if [ ${dmsg} == "true" ]; then
		echo "$@"
	fi
}

function build_bl() {
	local target=$1
	local path=$2
	local output=$path/out/$3
	local result=$4
	local command=$5
	local toolchain=$6

	if [ "$command" == "help" ]; then
		echo -e "USAGE: $target"
		echo -e "\t$SHELL_NAME $target [clean|cleanbuild]"
		exit 0;
	fi

	echo "*** BUILD: $target ***"
	dmsg "================================================================="
	dmsg "TARGET    : $target"
	dmsg "PATH      : $path"
	dmsg "OUTPUT    : $output"
	dmsg "RESULT    : $result"
	dmsg "COMMAND   : $command"
	dmsg "TOOLCHAIN : $toolchain"
	dmsg "================================================================="

	if [ "$command" ] &&
	   [ "$command" != "clean" ] &&
	   [ "$command" != "cleanbuild" ]; then
		echo "Invalid command: '$command' for '$target'"
		return
	fi

	if [ "$command" == "clean" ] ||
	   [ "$command" == "cleanbuild" ]; then
		make -C $path clean
		[ $? -ne 0 ] && exit 1;
		[ "$command" == "clean" ] && return;
	fi

	# check build path
	if [ ! -d "$path" ]; then
		echo "No such file: '$path' for '$target' ..."
		exit 1
	fi

	if [ "$toolchain" ]; then
		export PATH=$PATH:$toolchain
	fi

	make -C $path
	[ $? -ne 0 ] && exit 1;

	echo "*** COPY   : $output ***"
	echo "*** RESULT : $result/ ***"

	cp $output $result/
}

function build_linux() {
	local target=$1
	local path=$2
	local arch=$3
	local config=$4
	local output=$path/$5
	local result=$6/
	local command=$7
	local toolchain=$8
	local compile=$9
	local image
	local jobs=`grep processor /proc/cpuinfo | wc -l`

	if [ "$target" == "kernel" ]; then
		image=$(basename "$output")
	fi

	if [ "$command" == "help" ]; then
		echo -e "USAGE: $target"
		echo -e "\t$SHELL_NAME $target [distclean|clean|cleanbuild|defconfig|menuconfig]"
		exit 0;
	fi

	echo "*** BUILD: $target ***"
	dmsg "================================================================="
	dmsg "TARGET    : $target"
	dmsg "PATH      : $path"
	dmsg "ARCH      : $arch"
	dmsg "CONFIG    : $config"
	dmsg "OUTPUT    : $output"
	dmsg "IMAGE     : $image"
	dmsg "RESULT    : $result"
	dmsg "COMMAND   : $command"
	dmsg "TOOLCHAIN : $toolchain"
	dmsg "COMPILER  : $compile"
	dmsg "================================================================="

	# check support commands
	if [ "$command" ] &&
	   [ "$command" != "distclean" ] &&
	   [ "$command" != "clean" ] &&
	   [ "$command" != "cleanbuild" ] &&
	   [ "$command" != "menuconfig" ] &&
	   [ "$command" != "defconfig" ] ; then
		echo "Invalid command: '$command' for '$target' ..."
		return
	fi

	# check build path
	if [ ! -d "$path" ]; then
		echo "No such file: '$path' for '$target' ..."
		exit 1
	fi

	if [ "$toolchain" ]; then
		export PATH=$PATH:$toolchain
	fi

	if [ "$command" == "distclean" ]; then
		make -C $path distclean
		return
	fi

	if [ "$command" == "clean" ] ||
	   [ "$command" == "cleanbuild" ]; then
		make -C $path clean
		[ $? -ne 0 ] && exit 1;
		[ "$command" == "clean" ] && return;
	fi

	if [ "$command" == "defconfig" ]; then
		make -C $path ARCH=$arch CROSS_COMPILE=$compile $config
		[ $? -ne 0 ] && exit 1;
		return
	fi

 	if [ ! -f "$path/.config" ]; then
		make -C $path ARCH=$arch CROSS_COMPILE=$compile $config
		[ $? -ne 0 ] && exit 1;
	fi

	if [ "$command" == "menuconfig" ]; then
		make -C $path ARCH=$arch CROSS_COMPILE=$compile menuconfig
		return
	fi

	# build
	if [ "$target" == "u-boot" ] ||
	   [ "$target" == "kernel" ]; then
		make -C $path ARCH=$arch CROSS_COMPILE=$compile $image -j $jobs
	elif [ "$target" == "dts" ]; then
		make -C $path ARCH=$arch CROSS_COMPILE=$compile $config
	elif [ "$target" == "br2" ]; then
		make -C $path -j $jobs
	else
		echo "Not support target: $target"
		exit 1
	fi
	[ $? -ne 0 ] && exit 1;

	# copy to result
	if [ "$target" != "br2" ]; then
		cp $output $result
	else
		result=$result/rootfs
		[ -d $result ] && rm -rf $result;
		cp -a $output $result
	fi

	echo "*** COPY   : $output ***"
	echo "*** RESULT : $result ***"

	# u-boot bingen
	if [ "$target" == "u-boot" ]; then
		local BINGENDIR=$BASEDIR/../bingen
		local NSIHFILE=nsih.txt
		local BOOTKEY=bootkey
		local USERKEY=userkey
		$BINGENDIR/bingen -n $BINGENDIR/$NSIHFILE \
				  -i $output \
		 		  -b $BINGENDIR/$BOOTKEY \
		 		  -u $BINGENDIR/$USERKEY \
		 		  -k bl33 \
		 		  -l 0x43c00000 -s 0x43c00000 -t

		# copy to result
		cp $output.raw $result
		echo "*** COPY   : $output.raw ***"
		echo "*** RESULT : $result ***"
	fi

}

function build_usage() {
	local params=("${@}")	# [0]=array size, array[1]= ....#
	local arraysz=("${params[0]}")
	local images=("${params[@]:1:$arraysz}")
	local help=("${params[$arraysz + 1]}")
	local n=0

	if [ "$help" == "-h" ] ||
	   [ "$help" == "--help" ] ||
	   [ "$help" == "help" ]; then
		echo -e  "USAGE:"
		echo -e  "\tDebug Enable: 'export BUILD_DEBUG=true' ($BUILD_DEBUG)"
		echo -ne "\t$SHELL_NAME ["
		for i in "${images[@]}"
		do
			# print build targets
			if [ $(( $n % $BUILD_ARRAY_COLs )) -eq 0 ]; then
				echo -n "$i"
				if [ $n -ne `expr ${params[0]} - $BUILD_ARRAY_COLs - 1` ]; then
					echo -n "|"
				fi
			fi
			n=$((n + 1)); # parse next
		done

		#print build target's command
		echo -e "] [help|clean|cleanbuild|...]"
		exit 0;
	fi
};

function build_images() {
	local params=("${@}")	# [0]=array size, array[1]=BSP, array[2]=toolchain, array[3]=compile, array[4]=....
	local arraysz=("${params[0]}")
	local bsp=("${params[1]}")
	local toolchain=("${params[2]}")
	local compile=("${params[3]}")
	local images=("${params[@]:4:$arraysz-3}") # [0]=array size, array[1]=BSP, array[2]=toolchain
	local target=("${params[$arraysz+1]}")	# input param 3
	local command=("${params[$arraysz+2]}") # input param 4
	local result=$RESULT

	local ret=fale
	local n=0

	# command help
	build_usage "$(($arraysz - 3))" "${images[@]}" "$target"

	dmsg "Build Target : $target"
	dmsg "Build CMD    : $command"

	for i in "${images[@]}"
	do
		[ $n -eq 0 ] && _target=$i;
		[ $n -eq 1 ] && _path=$i;
		[ $n -eq 2 ] && _arch=$i;
		[ $n -eq 3 ] && _config=$i;
		[ $n -eq 4 ] && _output=$i;

		if [ $n -ne 0 ] && [ $(( $n % ($BUILD_ARRAY_COLs - 1) )) -eq 0 ]; then
			if [ "$target" ]; then
				if [ "$target" != "all" ] &&
				   [ "$target" != "$_target" ]; then
					n=0 # for next target
					continue
				fi
			fi

			if [ "$_target" == "bl1" ] ||
			   [ "$_target" == "bl2" ] ||
			   [ "$_target" == "bl32" ]; then
				build_bl "$_target" \
					 "$_path" \
					 "$_output" \
					 "$result" \
					 "$command" \
					 "$BL_TOOLCHAIN_PATH:$toolchain"
			else
				build_linux "$_target" \
					 "$_path" \
					 "$_arch" \
					 "$_config" \
					 "$_output" \
					 "$result" \
					 "$command" \
					 "$toolchain" "$compile"
			fi

			ret=true
			n=0 # for next target

			continue
		fi
		n=$((n + 1)); # parse next
	done

	if [ $ret != true ]; then
		echo "*** Invalid Target: $target ***"
	fi
}

# args 1: build images size
# args 2: build images array
# args 3: build target
# args 4: build command

build_images "${#BUILD_IMAGES_VTK[@]}" "${BUILD_IMAGES_VTK[@]}" "$1" "$2"

