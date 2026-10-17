// What ZWINDOW (the glass) and ZIGGY's firmware say to each other beyond map.zig's
// registers, for a program launched off a data disk (docs/FPGA_GLASS.md, "Programs
// off a data disk"). All of it is software over what the PL already has: a value of
// REG_CART_STATE the firmware writes, words in the cart window's top 4 KiB, and a
// second descriptor magic. No register, no RTL. Exported like map.zig
// (tools/glass_export.zig) to gen/glass_cart.{py,h}.

// --- REG_CART_STATE: the cart asks for a cart swap ----------------------------
// Bits 31:8 = the request, as pollCartRequest() returned it (docs/sealed-loader.js
// swapCart): REQ_RUN_PROGRAM runs the FAT file named in the request block as the next
// cart, the disk staying in; REQ_BACK_TO_OS brings GEM back over the same disk.
pub const CART_REQUEST: u32 = 4;
pub const REQ_RUN_PROGRAM: u32 = 3;
pub const REQ_BACK_TO_OS: u32 = 4;

// --- the request block, at window end - CART_REQ_FROM_TOP (CPU 0x41FF_FD00) --------
// Four words, CART_REQ_MAGIC, the request, the name's bytes, ~(magic ^ request ^
// bytes), then the name: the FAT name the request matched (host/zmd_dir.h), at most
// CART_REQ_NAME_MAX bytes. Written by the firmware BEFORE it sets CART_REQUEST; the
// glass takes it only when the check holds.
pub const CART_REQ_FROM_TOP: u32 = 0x300;
pub const CART_REQ_MAGIC: u32 = 0x5152_4D5A; // "ZMRQ"
pub const CART_REQ_HEAD_WORDS: u32 = 4;
pub const CART_REQ_NAME_MAX: u32 = 48;

// --- the disk descriptor's other magic -----------------------------------------
// map.zig's DISK_MAGIC: the cart was booted for this disk (GEM over a data disk
// hands it the listing). DISK_MAGIC_PROGRAM: the cart is a program GEM launched off
// it (the browser's diskDirSet is already true then: no listing).
pub const DISK_MAGIC_PROGRAM: u32 = 0x5044_4D5A; // "ZMDP"

// --- the system image and lean carts (decisions.md 2026-10-15) ------------------
// A lean cart image is linked at window offset CART_IMG_AT and starts with its header:
// CART_HDR_MAGIC, the system-table version it needs at CART_HDR_VERSION_AT (major << 16 |
// minor), and the CPU address its .bss ends at CART_HDR_BSS_END_AT (the disk goes after
// it). The system image (firmware + machine + ROM + BARD) sits at 0 and must end by
// CART_IMG_AT. On the SD card the system is zigmachine/system.rv32: a SYS_HEAD_WORDS-word
// header (SYS_MAGIC, version, image bytes, ~(magic ^ version ^ bytes)) before the image,
// ZX0-packed. fpga/cycles/sys_abi.txt is the table's layout and version.
pub const CART_IMG_AT: u32 = 0x0030_0000;
pub const CART_HDR_MAGIC: u32 = 0x4143_4D5A; // "ZMCA"
pub const CART_HDR_VERSION_AT: u32 = 4;
pub const CART_HDR_BSS_END_AT: u32 = 16;
pub const SYS_MAGIC: u32 = 0x5953_4D5A; // "ZMSY"
pub const SYS_HEAD_WORDS: u32 = 4;
// REG_CART_STATE TRAPPED codes (map.zig TRAP_WARM_LOST's family): the cart needs another
// table version than the system has; nothing that is a cart sits at CART_IMG_AT.
pub const TRAP_CART_ABI: u32 = 0xFF_FF02;
pub const TRAP_NO_CART: u32 = 0xFF_FF03;
