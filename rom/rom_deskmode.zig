// --------------------------------------------------------------------------
// The desktop's screen across a program launch: Getrez (rom_app.zig deskScreenMode) for the
// program, and the mode the desktop comes back in when that program quits (deskReturnMode).
// TOS keeps the resolution in a system variable (sshiftmd) that a program load leaves alone.
//
// In the browser the ROM outlives every cart swap, so its own state answers. On the board a
// program GEM launched is a separate image whose ROM starts fresh: the firmware carries the
// mode through the glass (fpga/glass/src/map_cart.zig DESK_REZ) and hands it to this ROM at
// boot with deskSetScreenMode, before the cart's init. Table 1.18 (appended exports).
// --------------------------------------------------------------------------
const main = @import("rom_main.zig");

pub const NONE: u32 = 0xFF;
const LAST_MODE: u32 = 2; // 0 low, 1 medium, 2 the desk

/// The desktop's mode a host carried across a load (the board), NONE: none carried. Getrez
/// answers it until a desktop runs on this ROM.
pub var carried: u32 = NONE;
/// The desktop's mode when it launched the program that runs now, until a desktop is back.
var back: u32 = NONE;

/// The shell, before it binds the desktop (deskInitPlane forgets it): the mode the desktop had
/// when it launched the program that just quit, 0xFF for any other start (a boot: DESKTOP.INF).
export fn deskReturnMode() u32 {
    return back;
}

/// The host (the board's firmware, cycles/bkos.c): the desktop's mode, carried across a load
/// that started a program or brought the desktop back. Anything past the desk is ignored.
export fn deskSetScreenMode(mode: u32) void {
    if (mode > LAST_MODE) return;
    carried = mode;
    back = mode;
}

/// deskLaunchName handed the host a program: remember the mode to come back in.
pub fn launched() void {
    back = @intFromEnum(main.desk.g.screen.mode);
}

/// deskInitPlane: a desktop is up again; the next return is decided by its next launch.
pub fn deskBound() void {
    back = NONE;
}
