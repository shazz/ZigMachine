// --------------------------------------------------------------------------
// KOS's system variables, the app's side (rom/kos/kos.zig is the ROM's): what booted, how, the
// drive, the frame counter. `rom_sdk.kos.vars()` reads the block the ROM keeps; a cart that
// never calls it links nothing. Must match rom/kos/kos.zig SysVars field for field.
// --------------------------------------------------------------------------
pub const SysVars = extern struct {
    magic: u32, // "KOSV"
    layout: u32,
    kos_version: u32, // major << 16 | minor
    boot_kind: u32, // 0 cold, 1 warm
    boot_dev: u32, // 0 the desktop, 1 drive A, 2 the cartridge slot
    ram_total: u32,
    ram_free: u32,
    frames: u32, // since the last reset
    drive_a: u32, // bit 0 a disk is in, bits 31:8 media changes since power-on
    cart_slot: u32,
};

pub const SYSVARS_MAGIC: u32 = 0x5653_4F4B;

extern fn kosSysVarsPtr() u32;

/// The ROM's block, or null from a ROM before KOS (no magic there).
pub fn vars() ?*const SysVars {
    const v: *const SysVars = @ptrFromInt(kosSysVarsPtr());
    return if (v.magic == SYSVARS_MAGIC) v else null;
}
