# ZigMachine glass: the U-Boot script on the SD card (fpga/glass/boot/boot.cmd,
# compiled to boot.scr by fpga/tools/glass_sd.py). zeST's BOOT.BIN runs it: its
# FSBL brings up DDR, clocks and MIO, and its U-Boot's distro boot finds
# boot.scr on mmc 0. Addresses are that U-Boot's (kernel_addr_r, fdt_addr_r).
setenv bootargs console=ttyPS0,921600 earlycon rootwait

# Our bitstream replaces whatever BOOT.BIN put in the PL. Without one the
# menu cannot run (no glass block at GP0), so say so on the UART.
if fatload mmc 0 0x1000000 zigmachine.bit; then
    fpga loadb 0 0x1000000 ${filesize}
    # The HP ports' AFI widths: 64-bit reads, 32-bit writes, HP0 the CPU, HP1 the
    # video, HP2 the blitter. Only after `fpga loadb`: without the PL these registers
    # hang the ARM. HP1 writes 64-bit (0xf00, W64: the video DMA's 8-byte beats), set
    # HERE before any HP1 traffic and never 0xf01 first: a channel that carried 32-bit
    # writes and is then set 64-bit loses words 1 and 2 of every 16 bytes (the board,
    # decisions.md 2026-10-19). The rootfs glass (afi.zig) sees 0xf00 and runs W64;
    # its --fw-opt without W64 goes back to 0xf01 at run time, which is safe.
    mw.l 0xf8008000 0; mw.l 0xf8008014 0xf01
    mw.l 0xf8009000 0; mw.l 0xf8009014 0xf00
    mw.l 0xf800a000 0; mw.l 0xf800a014 0xf01
    # HP3: the sound CPU's memory (--sound-cpu), and the PCM reader's, which only reads.
    mw.l 0xf800b000 0; mw.l 0xf800b014 0xf01
else
    echo zigmachine: no zigmachine.bit on the card, the PL keeps the BOOT.BIN bitstream
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
echo zigmachine: no zImage, booting the zeST kernel with a shell, plan B
setenv bootargs ${bootargs} mem=480M init=/bin/sh
fatload mmc 0 0x8000 uImage
fatload mmc 0 0x900000 rootfs.ub
bootm 0x8000 0x900000 0x800000
