// --------------------------------------------------------------------------
// RACER: the front end's screens on the plane (M5 step 4), drawn after the frame's HUD and its
// benchmark report (so no view CRC ever sees them):
//   - the title over the attract flyby (title.zig's logo, the prompt, the credit);
//   - the track select, the options and the results (seldraw.zig, optdraw.zig, resdraw.zig) on a MENU frame: no 3D pipeline
//     under them, the view rows filled with the sky's palette entry (the copper's per-line gradient of
//     the track on show: a gradient background for one @memset a row), so they run 60 fps on any track.
// Text is the plane's own printText on the panels' colour. Works on any Demo (front.zig's fields).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const front = @import("front.zig");
const menu = @import("menu.zig");
const palette = @import("palette.zig");
const present = @import("present.zig");
const resdraw = @import("resdraw.zig");
const seldraw = @import("seldraw.zig");
const title = @import("title.zig");
const xf = @import("xform.zig");

pub fn px(fb: *zg.LogicalFB) menu.Px {
    return .{ .px = fb.fb[0 .. @as(usize, fb.stride) * menu.H], .stride = fb.stride };
}

/// Text at (x, y) in `ink` on the panels' colour.
pub fn text(os: *zg.ZigOS, fb: *zg.LogicalFB, s: []const u8, x: i32, y: i32, ink: u8) void {
    os.printText(fb, s, @intCast(x), @intCast(y), ink, menu.PANEL);
}

/// A menu frame (select, results): the sky gradient, the HUD and the logs as every frame, then the screen.
pub fn menuFrame(d: anytype, os: *zg.ZigOS, fb: *zg.LogicalFB) void {
    os.blitSync(); // WHY: the page may still have CHISEL spans queued from the last 3D frame drawn into it
    const p = px(fb);
    p.rect(0, xf.Y0, menu.W, xf.Y1 - xf.Y0, palette.SKY);
    present.finish(d, os, fb, .{});
    overlay(d, os, fb);
}

/// The front end's screen on this frame's page, if one is up (after present.finish).
pub fn overlay(d: anytype, os: *zg.ZigOS, fb: *zg.LogicalFB) void {
    const st = front.screen(d) orelse return;
    if (st != .title and !front.menu(d)) return;
    os.blitSync(); // WHY: the fill's AFFINE spans are CHISEL ops: the panels must land after them
    const p = px(fb);
    switch (st) {
        .title => drawTitle(d, os, fb, p),
        .select => seldraw.draw(d, os, fb, p),
        .results => resdraw.draw(d, os, fb, p),
        .options => @import("optdraw.zig").draw(d, os, fb, p),
        .garage => @import("garagedraw.zig").draw(d, os, fb, p),
        else => {},
    }
}

fn drawTitle(d: anytype, os: *zg.ZigOS, fb: *zg.LogicalFB, p: menu.Px) void {
    const l = title.draw(p, os.system_font, d.front.frames);
    if (l.prompt) text(os, fb, title.PROMPT, title.PROMPT_XY[0], title.PROMPT_XY[1], menu.HILITE);
    if (l.credit) text(os, fb, title.CREDIT, title.CREDIT_XY[0], title.CREDIT_XY[1], palette.INK);
}
