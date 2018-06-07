#!/bin/bash

set -x

#COMMON_PATH="/home/deoks/developments/nexell/firmware/artik310/emul"
#COMMON_PATH2="/home/deoks/developments/nexell/firmware/artik310_emul"
#BL1_PATH=$COMMON_PATH/"bl1-artik310/out/nxp3220_bl1.bin.raw"
#BL2_PATH=$COMMON_PATH/"bl2-artik310/out/bl2-vtk.bin.raw"
#SSS_PATH=$COMMON_PATH/"bl2-artik310/tools/sss.raw"
#BL31_PATH=$COMMON_PATH2/"fake_secure_os/out/secure_os.bin.raw"
#BL32_PATH=$COMMON_PATH2/"fake_non_secure_os/out/non_secureos.bin.raw"

COMMON_PATH="/home/deoks/developments/nexell/nxp3220/result"
COMMON_PATH2="/home/deoks/developments/nexell/nxp3220/result"
BL1_PATH=$COMMON_PATH/"nxp3220_bl1.bin.raw"
BL2_PATH=$COMMON_PATH/"bl2-vtk.bin.raw"
SSS_PATH=$COMMON_PATH/"sss.raw"
BL31_PATH=$COMMON_PATH2/"bl32.bin.raw"
BL32_PATH=$COMMON_PATH2/"u-boot.bin.raw"

BLOCK_SIZE=512

function generate_gptdisk2()
{
	local bl1_path=${1}
	local bl2_path=${2}
	local sss_path=${3}
	local bl31_path=${4}
	local bl32_path=${5}

	gptdisk_name="GPT_DISK"
	gptdisk_c_name="GPT_C_DISK"

	# (2 + 32) x 128 ??
	bl1_seek="17408"

	### Calcurate the BL2 Size
	file_size=$(stat -c %s $bl2_path)
	cal_filesize=`expr 58368 + $file_size + $BLOCK_SIZE - 1`
	cal_filesize=`expr $cal_filesize / $BLOCK_SIZE`
	cal_filesize=`expr $cal_filesize \* $BLOCK_SIZE`
	bl2_seek="58368" # $bl1_seek + $cal_filesize
	bl2_filesize=$cal_filesize

	### Calcurate the SSS Size
	file_size=$(stat -c %s $sss_path)
	sss_seek=`expr $bl2_seek + $bl2_filesize`
	cal_filesize=`expr $sss_seek + $BLOCK_SIZE - 1`
	cal_filesize=`expr $cal_filesize / $BLOCK_SIZE`
	cal_filesize=`expr $cal_filesize \* $BLOCK_SIZE`
	sss_seek=$cal_filesize

	### Calcurate the BL31 Size
	file_size=$(stat -c %s $bl31_path)
	bl31_seek=`expr $sss_seek + $file_size`
	cal_filesize=`expr $bl31_seek + $BLOCK_SIZE - 1`
	cal_filesize=`expr $cal_filesize / $BLOCK_SIZE`
	cal_filesize=`expr $cal_filesize \* $BLOCK_SIZE`
	bl31_seek=$cal_filesize

	### Calcurate the BL32 Size
	file_size=$(stat -c %s $bl32_path)
	bl32_seek=`expr $bl31_seek + $file_size`
	cal_filesize=`expr $bl32_seek + $BLOCK_SIZE - 1`
	cal_filesize=`expr $cal_filesize / $BLOCK_SIZE`
	cal_filesize=`expr $cal_filesize \* $BLOCK_SIZE`
	bl32_seek=$cal_filesize

	sudo rm $gptdisk_name
	sudo rm $gptdisk_c_name
	sudo dd if=/dev/zero of=$gptdisk_name bs=512 count=4096;sync;

	# 5MB => FAT12
	# 100MB => FAT16
	# 1024MB => FAT32
	sudo chown deoks $gptdisk_name
	sudo chgrp deoks $gptdisk_name
	chmod 664 $gptdisk_name

	fdisk $gptdisk_name
	# g;n;p;m; ;2048;m;p;w

	#sudo dd if=./$gptdisk_name of=/dev/sdd bs=1 seek=0;sync

	echo "GENERATE_GPTDISK - BL1_SEEK: ${bl1_seek}, BL2_SEEK: ${bl2_seek}, BL3_SEEK: ${bl3_seek}"

	cp ./$gptdisk_name ./$gptdisk_c_name
	sudo dd if=$bl1_path of=./$gptdisk_c_name seek=$bl1_seek bs=1;sync
	sudo dd if=$bl2_path of=./$gptdisk_c_name seek=$bl2_seek bs=1;sync
	sudo dd if=$sss_path of=./$gptdisk_c_name seek=$sss_seek bs=1;sync
	sudo dd if=$bl31_path of=./$gptdisk_c_name seek=$bl31_seek bs=1;sync
	sudo dd if=$bl32_path of=./$gptdisk_c_name seek=$bl32_seek bs=1;sync

	sudo chown deoks $gptdisk_c_name
	sudo chgrp deoks $gptdisk_c_name
	chmod 664 $gptdisk_c_name

	sudo dd if=./$gptdisk_c_name of=/dev/sdd bs=1 seek=0;sync
}

function generate_gptdisk()
{
	local bl1_path=${1}
	local bl2_path=${2}
	local sss_path=${3}
	local bl31_path=${4}
	local bl32_path=${5}

	gptdisk_name="GPT_DISK"
	gptdisk_c_name="GPT_C_DISK"

	# (2 + 32) x 128 ??
	bl1_seek="17408"
	bl1_size=`expr 1024 \* 64`
	### Calcurate the BL2 Size
	bl2_seek=`expr $bl1_seek + $bl1_size`
	bl2_size=`expr 1024 \* 64`
	### Calcurate the SSS Size
	sss_seek=`expr $bl2_seek + $bl2_size`
	sss_size=`expr 1024 \* 32`
	### Calcurate the BL31 Size
	bl31_seek=`expr $sss_seek + $sss_size`
	bl31_size=`expr 1024 \* 128`
	### Calcurate the BL32 Size
	bl32_seek=`expr $bl31_seek + $bl31_size`

	sudo rm $gptdisk_name
	sudo rm $gptdisk_c_name
	sudo dd if=/dev/zero of=$gptdisk_name bs=512 count=4096;sync;

	# 5MB => FAT12
	# 100MB => FAT16
	# 1024MB => FAT32
	sudo chown deoks $gptdisk_name
	sudo chgrp deoks $gptdisk_name
	chmod 664 $gptdisk_name

	fdisk $gptdisk_name
	# g;n;p;m; ;2048;m;p;w

	#sudo dd if=./$gptdisk_name of=/dev/sdd bs=1 seek=0;sync

	echo "GENERATE_GPTDISK - BL1_SEEK: ${bl1_seek}, BL2_SEEK: ${bl2_seek}, BL3_SEEK: ${bl3_seek}"

	cp ./$gptdisk_name ./$gptdisk_c_name
	sudo dd if=$bl1_path of=./$gptdisk_c_name seek=$bl1_seek bs=1;sync
	sudo dd if=$bl2_path of=./$gptdisk_c_name seek=$bl2_seek bs=1;sync
	sudo dd if=$sss_path of=./$gptdisk_c_name seek=$sss_seek bs=1;sync
	sudo dd if=$bl31_path of=./$gptdisk_c_name seek=$bl31_seek bs=1;sync
	sudo dd if=$bl32_path of=./$gptdisk_c_name seek=$bl32_seek bs=1;sync

	sudo chown deoks $gptdisk_c_name
	sudo chgrp deoks $gptdisk_c_name
	chmod 664 $gptdisk_c_name

	sudo dd if=./$gptdisk_c_name of=/dev/sdd bs=1 seek=0;sync
}

function generate_emmcimg()
{
	local bl1_path=${1}
	local bl2_path=${2}
	local sss_path=${3}
	local bl31_path=${4}
	local bl32_path=${5}

	emmcimg_name="eMMC.img"

	bl1_seek=0

	### Calcurate the BL2 ###
	file_size=$(stat -c %s $bl1_path)
	cal_filesize=`expr $bl1_seek + $file_size + $BLOCK_SIZE - 1`
	cal_filesize=`expr $cal_filesize / $BLOCK_SIZE`
	cal_filesize=`expr $cal_filesize \* $BLOCK_SIZE`
	bl2_seek=$cal_filesize

	### Calcurate the SSS_F ###
	file_size=$(stat -c %s $bl2_path)
	cal_filesize=`expr $bl2_seek + $file_size + $BLOCK_SIZE - 1`
	cal_filesize=`expr $cal_filesize / $BLOCK_SIZE`
	cal_filesize=`expr $cal_filesize \* $BLOCK_SIZE`
	sss_seek=$cal_filesize

	### Calcurate the BL31 ###
	file_size=$(stat -c %s $sss_path)
	cal_filesize=`expr $sss_seek + $file_size + $BLOCK_SIZE - 1`
	cal_filesize=`expr $cal_filesize / $BLOCK_SIZE`
	cal_filesize=`expr $cal_filesize \* $BLOCK_SIZE`
	bl31_seek=$cal_filesize

	### Calcurate the BL32 ###
	file_size=$(stat -c %s $bl31_path)
	cal_filesize=`expr $bl31_seek + $file_size + $BLOCK_SIZE - 1`
	cal_filesize=`expr $cal_filesize / $BLOCK_SIZE`
	cal_filesize=`expr $cal_filesize \* $BLOCK_SIZE`
	bl32_seek=$cal_filesize

	echo "GENERATE_EMMCIMG - BL1_SEEK: ${bl1_seek}, BL2_SEEK: ${bl2_seek}, BL3_SEEK: ${bl3_seek}"

	sudo rm $emmcimg_name
	sudo dd if=$bl1_path of=./$emmcimg_name seek=$bl1_seek bs=1;sync
	sudo dd if=$bl2_path of=./$emmcimg_name seek=$bl2_seek bs=1;sync
	sudo dd if=$sss_path of=./$emmcimg_name seek=$sss_seek bs=1;sync
	sudo dd if=$bl31_path of=./$emmcimg_name seek=$bl31_seek bs=1;sync
	sudo dd if=$bl32_path of=./$emmcimg_name seek=$bl32_seek bs=1;sync

	sudo chown deoks $emmcimg_name
	sudo chgrp deoks $emmcimg_name
	chmod 664 $emmcimg_name
}
#####################################################################################################################################################

generate_gptdisk $BL1_PATH $BL2_PATH $SSS_PATH $BL31_PATH $BL32_PATH
#generate_emmcimg $BL1_PATH $BL2_PATH $SSS_PATH $BL31_PATH $BL32_PATH

# SDFS
#hd $DISK_NAME
#mkfs -t vfat $DISK_NAME
#hd $DISK_NAME

#sudo mount ./$DISK_NAME /mnt/;sync
#sleep 1
#sudo cp /home/deoks/developments/nexell/firmware/artik310_emul/bl1-artik310-emul/out/bl1-general.bin.raw /mnt/nxboot.img;sync
#sudo umount /mnt
