# Third-party files on the KESTREL card

The card in `card/` carries boot files that are not ZigMachine's own work. Their licences and
where their sources are:

| File on the card | What | Licence | Source |
|---|---|---|---|
| `BOOT.BIN` | zeST release 20260518's prebuilt boot image for the Z7-Lite 7010 (`boards/z7lite_7010/boot.bin`): Xilinx FSBL with zeST's PS7 setup (DDR3, clocks, MIO) + U-Boot 2025.01. Unmodified. | GPL-3.0 (zeST; text in `licenses/zeST-LICENSE`) | https://codeberg.org/zerkman/zest, the release tarball https://zest.sector1.fr/download/zeST-20260518.tar.xz (sha256 bdc1081ba9b57a56b94ebf51dac7c59e2cadc0c8a9af922a1936408c2bfacc60) |
| `zImage` | Linux 6.19.14, `multi_v7_defconfig` + `fpga/glass/boot/buildroot/linux.fragment` | GPL-2.0 | https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.19.14.tar.xz |
| `zigmachine.dtb` | its device tree, from `fpga/glass/boot/zigmachine-z7lite.dts` (in `zigmachine/`) | GPL-2.0 (with the kernel's dtsi) | as above, and `zigmachine/fpga/glass/boot/` |
| `rootfs.cpio.uboot` | Buildroot 2026.02.3 initramfs: busybox, musl, dropbear, avahi and their libraries, plus ZigMachine's `glass` and `S99glass` | each package its own (busybox GPL-2.0, musl MIT, dropbear MIT, avahi LGPL-2.1, ...) | https://buildroot.org/downloads/buildroot-2026.02.3.tar.xz with `zigmachine/fpga/glass/boot/buildroot` (`make legal-info` lists every package and licence) |

Everything else on the card (`zigmachine.bit`, `boot.scr`, `KESTREL/`, `CARTS/`) is built from the
`zigmachine/` tree of this release: the bitstream from `zigmachine/fpga/`, the system image and the
carts from `zigmachine/fpga/cycles` and `zigmachine/docs/`. The demo ports on the shelf credit their
original authors in their own sources (`zigmachine/apps/`).
