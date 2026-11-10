// --------------------------------------------------------------------------
// NOTEPAD's frame, the parts beside the text: a dialog's answer, and the window's
// title and the Edit menu kept in step with the document (set only on a change).
// --------------------------------------------------------------------------
const std = @import("std");
const rom = @import("rom_sdk");
const aes = rom.aes;
const flow = @import("flow.zig");
const menu = @import("menu.zig");
const screen = @import("screen.zig");
const App = @import("../notepad.zig").App;

/// A frame with a dialog up: its answer, once it has one.
pub fn modal(self: *App) void {
    const m = self.modal;
    const r: rom.Result = switch (m) {
        .info, .ask_save => self.dialog.process(self.g),
        .fsel_open, .fsel_save => self.fsel.process(self.g),
        .find => switch (self.find.process(self.g, screen.width(self.mode), screen.height(self.mode))) {
            .none => .none,
            .find => .ok,
            .cancel => .cancel,
        },
        .none => .none,
    };
    if (r == .none) return;
    if (r == .relist) return flow.relist(self); // the selector went to another folder: still up
    self.repaint = true; // what the box covered: the next frame paints it all again
    if (m == .find) {
        self.modal = .none;
        if (r == .ok and !self.doc.find(self.find.text()) and aes.formAlert(self.dialog, 1, "[1][Text not found.][ OK ]"))
            self.modal = .info;
        return;
    }
    flow.answered(self, m, r);
}

/// The title (and "*" when modified) and the Edit menu's items, set only when they change.
pub fn chrome(self: *App) void {
    var t: u32 = @intFromBool(self.doc.modified);
    for (self.title()) |c| t = t *% 31 +% c;
    if (t != self.shown_title) {
        self.shown_title = t;
        var buf: [24]u8 = undefined;
        const star: []const u8 = if (self.doc.modified) " *" else "";
        self.view.win.title(std.fmt.bufPrint(&buf, " {s}{s} ", .{ self.title(), star }) catch "");
        self.view.win.draw();
        self.view.all();
    }
    const e: u8 = @as(u8, @intFromBool(self.doc.hasSel())) | @as(u8, @intFromBool(self.doc.clip_len > 0)) << 1;
    if (e != self.shown_edit) {
        self.shown_edit = e;
        menu.enable(self.bar, self.doc.hasSel(), self.doc.clip_len > 0);
    }
}
