// --------------------------------------------------------------------------
// The boxes of a file operation on C: (fileop.zig posts it, the shell does it). TOS's two
// passes: the shell counts, the confirm box shows the folders and items (COPY / MOVE FOLDERS /
// ITEMS, or DELETE FILE(S) for the TRASH); after OK the same box stays up and counts down live.
// A name that exists where an item goes raises NAME CONFLICT (conflict.zig); the end raises
// an alert when it went wrong. Run from deskmenu.runDialogs, so the old path and GEM 5's engine
// (which paints the dialogs inside their own clip) show the same boxes.
// --------------------------------------------------------------------------
const std = @import("std");
const gui = @import("../gui.zig");
const op = @import("../../sdk/deskop.zig");
const dt = @import("desktop.zig");
const deskdirty = @import("deskdirty.zig");
const trash_mod = @import("trash.zig");
const Desktop = dt.Desktop;

/// The confirm box open for the operation: the TRASH's for a delete, the COPY box's else.
fn box(d: *Desktop) *trash_mod.DeleteDlg {
    return if (d.fop.box.op == @intFromEnum(op.Op.delete)) &d.trash else &d.copy;
}

/// Once a drawn frame, after the dialogs: the phases the ROM answers.
pub fn run(d: *Desktop, g: *gui.Gui) void {
    const s = &d.fop;
    const b = &s.box;
    switch (b.phase) {
        op.COUNTED => if (!s.confirm) openConfirm(d),
        op.RUN => if (s.confirm) live(d),
        op.CONFLICT => if (!s.conflict.active) {
            box(d).active = false; // the conflict box stands alone; the count-down comes back after it
            s.conflict.open(b.nameSlice(), b.op == @intFromEnum(op.Op.move));
        },
        else => {},
    }
    if (b.phase != op.CONFLICT) return;
    const ans: op.Answer = switch (s.conflict.process(g)) {
        .none => return,
        .ok => .rename,
        .skip => .skip,
        .stop => .stop,
    };
    if (ans == .rename) b.setName(s.conflict.name.text());
    b.answer = @intFromEnum(ans);
    b.phase = op.ANSWER;
    deskdirty.touch(d);
}

fn openConfirm(d: *Desktop) void {
    const b = &d.fop.box;
    const mode: trash_mod.DeleteDlg.Mode = switch (b.op) {
        @intFromEnum(op.Op.move) => .move,
        @intFromEnum(op.Op.delete) => .delete,
        else => .copy,
    };
    box(d).openMode(mode, clamp(b.folders), clamp(b.files));
    d.fop.confirm = true;
}

fn live(d: *Desktop) void {
    const dlg = box(d);
    dlg.active = true;
    dlg.busy = true;
    dlg.folders = clamp(d.fop.box.folders_left);
    dlg.files = clamp(d.fop.box.files_left);
}

fn clamp(n: u32) u16 {
    return @intCast(@min(n, 0xFFFF));
}

/// The confirm box's OK: the shell starts (the box stays up, counting down).
pub fn go(d: *Desktop) void {
    d.fop.box.phase = op.RUN;
    live(d);
    deskdirty.touch(d);
}

/// The confirm box's Cancel: nothing was done, nothing to re-read.
pub fn cancel(d: *Desktop) void {
    d.fop.box.phase = op.IDLE;
    d.fop.confirm = false;
    deskdirty.touch(d);
}

/// The confirm box is the file operation's (not drive A's in-memory delete).
pub fn owns(d: *const Desktop) bool {
    return d.fop.confirm;
}

/// The end: an alert for what went wrong (the operation stopped there; what was done stays done).
pub fn report(d: *Desktop, b: *const op.Box) void {
    var buf: [40]u8 = undefined;
    const lines: [2][]const u8 = switch (b.status) {
        0 => if (b.kept == 0) return else .{ "The originals could not be", "deleted: they are kept." },
        -10 => .{ "C: could not be written:", "the disk is full or failed." },
        -13 => .{ "The disk in drive C: is", "write-protected." },
        -36 => .{ "An item with that name", "already exists." },
        -33, -34 => .{ "An item could not be found.", "The window was re-read." },
        -11, -46 => .{ "The disk cannot be read.", "Nothing more was copied." },
        else => .{ "The operation stopped:", std.fmt.bufPrint(&buf, "GEMDOS error {d}.", .{b.status}) catch "GEMDOS error." },
    };
    d.dlg.alert(lines[0], lines[1]);
}
