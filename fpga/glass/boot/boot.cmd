# ZigMachine glass: the U-Boot script on the SD card (fpga/glass/boot/boot.cmd,
# compiled to boot.scr by fpga/tools/glass_sd.py). zeST's BOOT.BIN runs it: its
# FSBL brings up DDR, clocks and MIO, and its U-Boot's distro boot finds
# boot.scr on mmc 0. Addresses are that U-Boot's (kernel_addr_r, fdt_addr_r).
setenv bootargs console=ttyPS0,921600 earlycon rootwait

# Our bitstream replaces whatever BOOT.BIN put in the PL. Without one the
# menu cannot run (no glass block at GP0), so say so on the UART.
if fatload mmc 0 0x1000000 zigmachine.bit; then
    fpga loadb 0 0x1000000 ${filesize}
else
    echo "zigmachine: no zigmachine.bit on the card, the PL keeps BOOT.BIN's bitstream"
fi

# Plan A: our own Linux (Buildroot, fpga/glass/boot/buildroot): it starts the
# glass menu itself, and its device tree keeps the cart window from Linux.
if fatload mmc 0 0x2000000 zImage; then
    fatload mmc 0 0x1f00000 zigmachine.dtb
    fatload mmc 0 0x4000000 rootfs.cpio.uboot
    bootz 0x2000000 0x4000000 0x1f00000
fi

# Plan B, the stopgap: zeST's own kernel and rootfs (same board, USB HID,
# /dev/mem), its device tree as BOOT.BIN leaves it at 0x800000, a shell on the
# UART instead of zeST, and mem=480M so Linux never touches the top 32 MiB
# (the cart window). Then: mount /dev/mmcblk0p1 /mnt && /mnt/glass run /mnt/zigmachine
echo "zigmachine: no zImage, booting zeST's kernel with a shell (plan B)"
setenv bootargs ${bootargs} mem=480M init=/bin/sh
fatload mmc 0 0x8000 uImage
fatload mmc 0 0x900000 rootfs.ub
bootm 0x8000 0x900000 0x800000
