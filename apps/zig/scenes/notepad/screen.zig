// --------------------------------------------------------------------------
// NOTEPAD's screen: plane 0 in the desktop's resolution. The plane is taken once,
// as the desktop's shell takes it (gem_desktop.zig allocPlane): the desk's 640x480
// buffer where the machine has the desk mode (low and medium use its first rows),
// else the medium buffer. A program cannot read the desktop's mode off the machine
// (every cart swap resets RESOLUTION), so it asks the ROM (aes.screenMode, Getrez).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hw = @import("hardware");
const rom = @import("rom_sdk");
const aes = rom.aes;
const Mode = aes.ScreenMode;
const Rect = rom.Rect;

/// The buffer for every mode. True when it is the desk's (the desk mode is available).
pub fn allocPlane(fb: *zg.LogicalFB) bool {
    fb.is_enabled = true;
    if (hw.hwDeskAvailable() != 0) {
        if (fb.setDeskPlane()) |_| {
            fb.leaveDesk();
            return true;
        } else |_| {}
    }
    fb.setMediumPlane();
    return false;
}

/// The desktop's mode, the desk only where the machine has it; MEDIUM when no desktop ran.
pub fn boot(desktop: ?Mode, desk_ok: bool) Mode {
    const m = desktop orelse return .medium;
    return if (m == .desk and !desk_ok) .medium else m;
}

pub fn apply(fb: *zg.LogicalFB, m: Mode) void {
    if (m != .desk and fb.isDesk()) fb.leaveDesk();
    switch (m) {
        .low => fb.setResLow(),
        .medium => fb.setResMedium(),
        .desk => fb.setDeskPlane() catch fb.setResMedium(),
    }
}

/// Another mode at run time (the digits): the one it could enter.
pub fn switchTo(fb: *zg.LogicalFB, m: Mode, desk_ok: bool) Mode {
    const to: Mode = if (m == .desk and !desk_ok) .medium else m;
    apply(fb, to);
    return to;
}

pub fn width(m: Mode) i16 {
    return if (m == .low) 320 else 640;
}
pub fn height(m: Mode) i16 {
    return if (m == .desk) 480 else 200;
}

/// The window's first box: the work area below the menu bar, a cell in, room for its shadow.
pub fn windowRect(m: Mode) Rect {
    const top: i16 = 11 + 8; // the bar is 11 rows (8x8 font), then a cell
    return .{ .x = 8, .y = top, .w = width(m) - 18, .h = height(m) - top - 10 };
}

/// The desktop's green under the window (everything below the menu bar).
pub fn desk(g: rom.Gui, m: Mode) void {
    g.rect(.{ .x = 0, .y = 11, .w = width(m), .h = height(m) - 11 }, rom.DESK);
}
