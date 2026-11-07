// --------------------------------------------------------------------------
// The desktop's two drives (KOS, docs/KOS_FAT.md F5): A: the disk in the drive, C: the SD card,
// each its own directory model (drives[0], drives[1]). Every directory window remembers its
// drive (drv.win); `d.dir` is the model of the drive in FOCUS, which follows the top directory
// window, so the code that reads `d.dir` (dirview, desksel, deskops) is unchanged. A change of
// focus drops the file/folder selection: its indices are the other model's.
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");
const dt = @import("desktop.zig");
const deskwin = @import("deskwin.zig");
const Desktop = dt.Desktop;

pub const A: u1 = 0;
pub const C: u1 = 1;

pub const State = struct {
    cur: u1 = A, // the drive in focus: d.dir is drives[cur]
    c_mounted: bool = false, // the shell read the SD card: C:'s icon shows
    win: [gui.MAX_WIN]u1 = [_]u1{A} ** gui.MAX_WIN, // each directory window's drive
};

/// A cart's unit (the drive ABI's: 0 drive A, 2 C:) as a drive, or null.
pub fn ofUnit(unit: u32) ?u1 {
    return switch (unit) {
        0 => A,
        2 => C,
        else => null,
    };
}

/// Both models empty, drive A in focus (init: the hosts fill them).
pub fn reset(d: *Desktop) void {
    for (&d.drives) |*m| {
        m.n_disk = 0;
        m.n_folders = 0;
        m.new_seq = 0;
    }
    d.drives[C].letter = 'C'; // its folders' window titles read C:\...
    d.drv = .{};
    use(d, A);
}

/// Put drive `drv` in focus, the selection kept (the caller owns it).
pub fn use(d: *Desktop, drv: u1) void {
    d.drv.cur = drv;
    d.dir = &d.drives[drv];
}

/// Focus the top directory window's drive (A: with none open); a change drops the selection.
pub fn focusTop(d: *Desktop) void {
    const drv: u1 = if (deskwin.topFloppy(d)) |w| d.drv.win[w.id] else A;
    if (drv != d.drv.cur) {
        d.sel_file = -1;
        d.sel_folder = -1;
        d.sel_files = 0;
        d.sel_folders = 0;
    }
    use(d, drv);
}
