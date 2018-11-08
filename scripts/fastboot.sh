#!/bin/bash
sudo fastboot flash partmap tools/scripts/partmap/partmap_emmc_nxp3220.txt
sudo fastboot flash bl1 result/bl1-nxp3220.bin.raw
sudo fastboot flash bl2 result/bl2-vtk.bin.raw
sudo fastboot flash bl32 result/bl32.bin.raw
sudo fastboot flash bootloader result/u-boot.bin.raw
# sudo fastboot flash env
sudo fastboot flash boot result/boot.img
sudo fastboot flash rootfs result/rootfs.img
sudo fastboot reboot
