// --------------------------------------------------------------------------
// The asset set the engine draws with: fonts, the arrow, the desktop's icons, the
// 16 VDI pens. Built in: the TOS 1.0 set in the repo (gem_icons.zig, ZigOS's 8x8
// and 6x6 fonts, deskarrow.zig's ARROW). With a build's -Dgem_assets the module
// `gem_assets` (tools/gem_assets_conv.py, local only) supplies what it has, and
// whatever it lacks falls back to the built-in piece, one id at a time.
// --------------------------------------------------------------------------
const ga = @import("gem_assets");
const icons = @import("../../gem_icons.zig");
const deskarrow = @import("../deskarrow.zig");
const canvas = @import("../../engine/canvas.zig");
const Font = canvas.Font;

pub const Id = enum(u3) { floppy, hard, trash, folder, program, document };
const ID_NAMES = [_][]const u8{ "FLOPPY", "HARD", "TRASH", "FOLDER", "PROGRAM", "DOCUMENT" };

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
    pens: [16][3]u8, // the VDI pens 0..15 in hardware order (assets' palette_16)
};

/// The set this ROM was built with; `sys8` / `small6` are ZigOS's raw fonts (a byte a pixel).
pub fn load(sys8: []const u8, small6: []const u8) Set {
    var s: Set = .{
        .present = ga.present,
        .sys = .{ .w = 8, .h = 8, .data = sys8, .packed_rows = false },
        .small = .{ .w = 6, .h = 6, .data = small6, .packed_rows = false },
        .tall = null,
        .arrow = .{ .mask = deskarrow.MASK, .data = deskarrow.DATA, .hx = 0, .hy = 0 },
        .icons = BUILTIN,
        .pens = VDI_PENS,
    };
    if (ga.font_8x8) |f| s.sys = .{ .w = f.w, .h = f.h, .data = f.data };
    if (ga.font_6x6) |f| s.small = .{ .w = f.w, .h = f.h, .data = f.data };
    if (ga.font_8x16) |f| s.tall = .{ .w = f.w, .h = f.h, .data = f.data };
    if (ga.arrow) |m| s.arrow = .{ .mask = m.mask, .data = m.data, .hx = m.hx, .hy = m.hy };
    if (ga.palette) |p| s.pens = p;
    for (ID_NAMES, 0..) |name, i| {
        if (find(ga.icons, name)) |a| s.icons[i] = a;
        if (find(ga.cicons, name)) |a| s.icons[i] = a; // a colour icon wins over the mono one
    }
    return s;
}

fn find(list: []const ga.Icon, id: []const u8) ?Art {
    for (list) |ic| {
        if (!eql(ic.id, id)) continue;
        return .{ .w = ic.w, .h = ic.h, .bpr = @intCast((@as(usize, @intCast(ic.w)) + 7) / 8), .mask = ic.mask, .data = ic.data, .col = ic.col };
    }
    return null;
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (x != y) return false;
    return true;
}

// The TOS 1.0 icons in the repo: ink = data, ink | body = mask.
const BUILTIN = [6]Art{ art(icons.FLOPPY), art(icons.HARD), art(icons.TRASH), art(icons.FOLDER), art(icons.PROGRAM), art(icons.DOCUMENT) };

fn art(comptime ic: icons.Icon) Art {
    const m = comptime blk: {
        var out: [ic.ink.len]u8 = undefined;
        for (&out, 0..) |*b, i| b.* = ic.ink[i] | ic.body[i];
        break :blk out;
    };
    return .{ .w = ic.w, .h = ic.h, .bpr = @intCast((@as(usize, ic.w) + 7) / 8), .mask = &m, .data = ic.ink };
}

/// The standard 16 VDI colours in hardware order (white, red, green, yellow, blue, magenta,
/// cyan, light grey, dark grey, then the dark versions, black last).
pub const VDI_PENS = [16][3]u8{
    .{ 255, 255, 255 }, .{ 255, 0, 0 },   .{ 0, 255, 0 },   .{ 255, 255, 0 },
    .{ 0, 0, 255 },     .{ 255, 0, 255 }, .{ 0, 255, 255 }, .{ 187, 187, 187 },
    .{ 136, 136, 136 }, .{ 170, 0, 0 },   .{ 0, 170, 0 },   .{ 170, 170, 0 },
    .{ 0, 0, 170 },     .{ 170, 0, 170 }, .{ 0, 170, 170 }, .{ 0, 0, 0 },
};
