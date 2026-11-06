# No packages: the glass program is a static Zig binary, put in by post-build.sh.

# U-Boot SPL's PS7 init (DDR3, clocks, MIO), read out of zeST's FSBL by
# fpga/tools/ps7_from_bootbin.py (build_planA.sh does it). Never committed (fpga/.gitignore).
# U-Boot links board/xilinx/zynq/<DEVICE_TREE>/ps7_init_gpl.c when it exists and otherwise
# builds an SPL whose ps7_init() does NOTHING (a weak stub: no DDR), so a missing file fails here.
ZM_PS7_INIT = $(BR2_EXTERNAL_ZIGMACHINE_PATH)/../uboot/ps7_init_gpl.c
define ZM_UBOOT_PS7_INIT
	test -f $(ZM_PS7_INIT) || { echo "$(ZM_PS7_INIT) missing: run fpga/glass/boot/build_planA.sh" >&2; exit 1; }
	mkdir -p $(@D)/board/xilinx/zynq/zynq-z7lite
	cp $(ZM_PS7_INIT) $(@D)/board/xilinx/zynq/zynq-z7lite/ps7_init_gpl.c
endef
UBOOT_POST_PATCH_HOOKS += ZM_UBOOT_PS7_INIT
