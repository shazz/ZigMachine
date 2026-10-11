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
