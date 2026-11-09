// --------------------------------------------------------------------------
// The desktop's screen modes (docs/GEM_DESK_MODE.md §8, DEVPAC_GAP §3b): low,
// medium and, where the machine has it, the 640x480 desk. The shell switches the
// plane and calls deskSetScreen; the ROM re-binds and lands here, which moves
// everything that was laid out for the old screen onto the new one:
//   - the icons keep their cell, and one on the old bottom row (the trash) keeps
//     the bottom row;
//   - every window, its full-box restore rect and each directory's remembered
//     rect are clamped into the new work area (a window at y 300 in the desk is
//     out of reach in low res otherwise);
//   - a DESKTOP.INF read at boot (deskLoadInf) is applied, on THIS screen, so a
//     file saved in one mode loads clamped in another.
// --------------------------------------------------------------------------
const std = @import("std");
const gui = @import("../gui.zig");
const dt = @import("desktop.zig");
const icon = @import("icon.zig");
const deskinf = @import("deskinf.zig");
const inf_read = @import("deskinf_read.zig");
const desk_icons = @import("desk_icons.zig");
const deskwin = @import("deskwin.zig");
const deskdrive = @import("deskdrive.zig");
const deskdirty = @import("deskdirty.zig");
const dirmodel = @import("dirmodel.zig");
const Desktop = dt.Desktop;

pub const State = struct {
    desk_ok: bool = false, // the shell said the machine shows the desk mode (deskSetDeskAvailable)
    pending: ?inf_read.Loaded = null, // a DESKTOP.INF read at boot, applied at the next setScreen
    inf_len: u16 = 0, // the bytes of DESKTOP.INF Save Desktop last wrote into inf_buf
};

/// The screen changed (the ROM re-bound the plane): move the layout onto it.
pub fn setScreen(d: *Desktop, s: gui.Screen) void {
    const old_rows = rowsOf(d.g.screen);
    d.g.screen = s;
    deskdirty.touch(d); // every pixel moved
    for (&d.items) |*it| {
        const row = if (it.cellRow() >= old_rows - 1) rowsOf(s) - 1 else it.cellRow();
        it.place(it.cellCol(), row, s.w, s.h);
    }
    if (d.mode.pending) |*p| applyInf(d, p);
    d.mode.pending = null;
    clampWindows(d);
}

fn rowsOf(s: gui.Screen) i16 {
    return @max(1, @divTrunc(s.h - icon.GRID_Y0, icon.CELL_H));
}

/// Every window rectangle the desktop holds, into the current work area.
pub fn clampWindows(d: *Desktop) void {
    const s = d.g.screen;
    for (d.wm.wins[0..d.wm.n]) |*w| {
        w.r = if (w.full) s.workArea() else s.clampRect(w.r, w.min_w, w.min_h);
        if (w.saved.w > 0) w.saved = s.clampRect(w.saved, w.min_w, w.min_h);
    }
    for (&d.win_geom) |*r| {
        if (r.w > 0) r.* = s.clampRect(r.*, gui.MIN_W, gui.MIN_H);
    }
    // The cascade's next spot follows its own rule (deskwin.advanceCascade): back to the start.
    if (d.next_win.x + d.next_win.w > s.w or d.next_win.y + d.next_win.h > s.h) {
        d.next_win.x = desk_icons.WIN_X0;
        d.next_win.y = desk_icons.WIN_Y0;
    }
}

/// DESKTOP.INF off the boot disk: the colour now, the rest at the next setScreen
/// (the shell sets the mode the file asks for first). Returns the file's #E
/// resolution, null when it has none.
pub fn loadInf(d: *Desktop, text: []const u8) ?deskinf.Res {
    const got = inf_read.parse(text);
    if (got.bg) |c| {
        d.bg_r = c[0];
        d.bg_g = c[1];
        d.bg_b = c[2];
        d.applyBg();
    }
    d.mode.pending = got;
    deskdirty.touch(d);
    return got.res;
}

fn applyInf(d: *Desktop, p: *const inf_read.Loaded) void {
    const s = d.g.screen;
    if (p.drive) |c| d.items[desk_icons.IC_FLOPPY].place(c.col, c.row, s.w, s.h);
    if (p.trash) |c| d.items[desk_icons.IC_TRASH].place(c.col, c.row, s.w, s.h);
    for (p.wins[0..p.n_wins]) |*w| {
        // Only the drives' roots are known at boot (a folder needs its listing first): A:\ and,
        // with the card read (the shell reads C: before the mode), C:\ open where they were,
        // as TOS reopens the windows DESKTOP.INF lists.
        const r = s.clampRect(.{ .x = w.x, .y = w.y, .w = w.w, .h = w.h }, gui.MIN_W, gui.MIN_H);
        const path = w.pathSlice();
        var title: []const u8 = "A:\\"; // a literal: the window keeps the slice, the parse goes away
        if (std.mem.eql(u8, path, title)) {
            d.win_geom[0] = r;
            deskdrive.use(d, deskdrive.A);
        } else if (std.mem.eql(u8, path, "C:\\") and d.drv.c_mounted) {
            title = "C:\\";
            deskdrive.use(d, deskdrive.C);
        } else continue;
        d.view = if (w.text_view) .text else .icons;
        deskwin.addFloppyWindow(d, title, dirmodel.ROOT);
        if (d.wm.topOpen()) |id| d.wm.wins[id].r = r; // C: keeps no remembered rect (deskwin)
    }
    deskdrive.focusTop(d);
}

/// The #E code for the screen the desktop is on (Save Desktop).
pub fn resOf(s: gui.Screen) deskinf.Res {
    return switch (s.mode) {
        .low => .low,
        .medium => .medium,
        .desk => .desk,
    };
}
