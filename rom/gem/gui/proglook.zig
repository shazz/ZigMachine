// --------------------------------------------------------------------------
// The look a PROGRAM's objects are drawn in by the GEM 5 engine (form_alert, and
// what the program API draws with objc_draw): the asset set this ROM was built
// with (desktop/eng/assets.zig: the TOS 1.0 set in the repo, or a local
// -Dgem_assets set) and the engine's two looks (desktop/eng/looks.zig).
//
// TOS 4's 3D rules follow the desktop's engine switch (deskSetEngine, system
// table 1.16): 2 is 3D, else flat. Without a desktop the boot default is the
// build's (-Dgem_engine with a local set: 3D). So a board ROM built with Matt's
// set draws a program's alerts as TOS 4 does, and the gate can ask for the 3D
// rules with the built-in art (deskSetEngine(2)) without any local asset.
// --------------------------------------------------------------------------
const zsrc = @import("zigos");
const assets = @import("../desktop/eng/assets.zig");
const looks = @import("../desktop/eng/looks.zig");
const L = @import("../engine/look.zig");
const canvas = @import("../engine/canvas.zig");
const Gui = @import("core.zig").Gui;

var set: assets.Set = undefined;
var loaded = false;
/// The 3D rules for programs (set by rom_main.zig from the desktop's engine mode).
pub var three_d: bool = @import("gem_opts").engine_default and @import("gem_assets").present;
/// The harness's mutants for a program's objects: deskSetEngine's bits 24.. (8..12 are engine.zig's,
/// 13..18 deskbreak.zig's).
pub var breaks: u32 = 0;
pub const BREAK_NODRIVE: u32 = 1 << 25; // the ITEM SELECTOR's drive buttons do nothing (gemtest_fsel_check --break drive)
pub const BREAK_NOICON: u32 = 1 << 24; // form_alert's icon art is lost (gemtest_alert_check --break icon)

/// The set, loaded once from the context's ZigOS fonts (the ROM's own: every context's).
pub fn setOf(g: *const Gui) *const assets.Set {
    if (!loaded) {
        set = assets.load(g.os.system_font, g.os.system_font_6);
        loaded = true;
    }
    return &set;
}

pub fn look(g: *const Gui) L.Look {
    return looks.look(setOf(g), three_d);
}

/// A canvas over the context's plane: its screen, clipped as the Gui is (GEM 5's MUTED and
/// a dialog's own box on the desk), big fills through the plane's CHISEL fill.
pub fn canvasOf(g: *Gui) canvas.Canvas {
    const h: i16 = @intCast(@min(@as(i32, g.screen.h), @as(i32, @intCast(g.fb.fb_h))));
    var cv = canvas.Canvas.init(g.fb.fb, g.fb.stride, g.screen.w, h);
    if (g.clip) |c| cv.setClip(.{ .x = c.x, .y = c.y, .w = c.w, .h = c.h });
    cv.fill_fn = fillPlane;
    cv.fill_ctx = @ptrCast(g.fb);
    return cv;
}

fn fillPlane(ctx: *anyopaque, at: [*]u8, stride: u32, w: u32, h: u32, v: u8) void {
    const fb: *zsrc.LogicalFB = @ptrCast(@alignCast(ctx));
    const off = @intFromPtr(at) - @intFromPtr(fb.fb);
    fb.fillRect(@intCast(off % stride), @intCast(off / stride), w, h, v);
}
