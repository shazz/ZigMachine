// --------------------------------------------------------------------------
// The asset set the engine draws with: fonts, the arrow, the desktop's icons, the
// 16 VDI pens. Built in: the TOS 1.0 set in the repo (gem_icons.zig, ZigOS's 8x8
// and 6x6 fonts, deskarrow.zig's ARROW). With a build's -Dgem_assets the module
// `gem_assets` (tools/gem_assets_conv.py, local only) supplies what it has, and
// whatever it lacks falls back to the built-in piece, one id at a time. The icons
// are chosen in ../../iconset.zig, which every screen mode draws from.
// --------------------------------------------------------------------------
const std = @import("std");
const ga = @import("gem_assets");
const alert_art = @import("../../gui/alert_art.zig");
const iconset = @import("../../iconset.zig");
const deskarrow = @import("../deskarrow.zig");
const canvas = @import("../../engine/canvas.zig");
const Font = canvas.Font;

pub const Id = enum(u3) { floppy, hard, trash, folder, program, document };

/// An icon's art: 1 bpp mask and data (rows of bpr bytes), an optional chunky image.
pub const Art = struct { w: i16, h: i16, bpr: i16, mask: []const u8, data: []const u8, col: ?[]const u8 = null };
pub const Mouse = struct { mask: [16]u16, data: [16]u16, hx: i8, hy: i8 };

pub const Set = struct {
    present: bool, // a local set was compiled in (the TOS 4 look's default)
    sys: Font,
    small: Font,
    tall: ?Font, // the 8x16 system font, when the set has one
    arrow: Mouse,
    icons: [6]Art,
    alerts: [3]Art, // form_alert's icons 1 NOTE, 2 QUES, 3 STOP (1 bpp, drawn as BITBLKs: `data` only)
    pens: [16][3]u8, // the VDI pens 0..15 in hardware order (assets' palette_16)
};

const ALERT_IDS = [3][]const u8{ "NOTE", "QUES", "STOP" };

// The set's alert image `k`, else our own (gui/alert_art.zig).
fn alertArt(k: usize) Art {
    for (ga.images) |im| if (std.mem.eql(u8, im.id, ALERT_IDS[k])) {
        return .{ .w = im.w, .h = im.h, .bpr = @intCast((@as(usize, @intCast(im.w)) + 7) / 8), .mask = im.data, .data = im.data };
    };
    const b = alert_art.of(@intCast(k + 1)).?;
    return .{ .w = alert_art.W, .h = alert_art.H, .bpr = alert_art.BPR, .mask = b, .data = b };
}

/// The set this ROM was built with; `sys8` / `small6` are ZigOS's raw fonts (a byte a pixel).
pub fn load(sys8: []const u8, small6: []const u8) Set {
    var s: Set = .{
        .present = ga.present,
        .sys = .{ .w = 8, .h = 8, .data = sys8, .packed_rows = false },
        .small = .{ .w = 6, .h = 6, .data = small6, .packed_rows = false },
        .tall = null,
        .arrow = .{ .mask = deskarrow.MASK, .data = deskarrow.DATA, .hx = 0, .hy = 0 },
        .icons = ICONS,
        .alerts = .{ alertArt(0), alertArt(1), alertArt(2) },
        .pens = pens(),
    };
    if (ga.font_8x8) |f| s.sys = .{ .w = f.w, .h = f.h, .data = f.data };
    if (ga.font_6x6) |f| s.small = .{ .w = f.w, .h = f.h, .data = f.data };
    if (ga.font_8x16) |f| s.tall = .{ .w = f.w, .h = f.h, .data = f.data };
    if (ga.arrow) |m| s.arrow = .{ .mask = m.mask, .data = m.data, .hx = m.hx, .hy = m.hy };
    return s;
}

/// The VDI pens: the set's palette, else the standard 16.
pub fn pens() [16][3]u8 {
    return ga.palette orelse VDI_PENS;
}

// The icons, per Id: iconset.zig's choice, the one the old path (low, medium) draws too.
const ICONS = blk: {
    var out: [6]Art = undefined;
    for (&out, iconset.ENTRIES) |*a, e| {
        a.* = .{ .w = @intCast(e.icon.w), .h = @intCast(e.icon.h), .bpr = @intCast((@as(usize, e.icon.w) + 7) / 8), .mask = e.mask, .data = e.icon.ink, .col = e.col };
    }
    break :blk out;
};

/// The standard 16 VDI colours in hardware order (white, red, green, yellow, blue, magenta,
/// cyan, light grey, dark grey, then the dark versions, black last).
pub const VDI_PENS = [16][3]u8{
    .{ 255, 255, 255 }, .{ 255, 0, 0 },   .{ 0, 255, 0 },   .{ 255, 255, 0 },
    .{ 0, 0, 255 },     .{ 255, 0, 255 }, .{ 0, 255, 255 }, .{ 187, 187, 187 },
    .{ 136, 136, 136 }, .{ 170, 0, 0 },   .{ 0, 170, 0 },   .{ 170, 170, 0 },
    .{ 0, 0, 170 },     .{ 170, 0, 170 }, .{ 0, 170, 170 }, .{ 0, 0, 0 },
};
