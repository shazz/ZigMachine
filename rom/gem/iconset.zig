// --------------------------------------------------------------------------
// The desktop's icon set, chosen ONCE for every screen mode (Matt, 9 Nov: "in low
// resolution, the same icons should be used as in desk mode"). Per id, the build's
// asset set (-Dgem_assets, module `gem_assets`) wins: its colour icon, else its
// mono icon, else the TOS 1.0 icon in the repo (gem_icons.zig). The old ZigGEM
// path (low, medium) and the GEM 5 engine (desk, eng/assets.zig) both draw from
// here, so the two cannot drift apart.
//
// Real TOS 4 draws an icon 1:1 in every resolution (no scaling: in ST low the
// 32 px wide icon looks twice as wide on the 2:1 pixel), and takes a colour icon's
// image only when it has one for the screen's planes or fewer (4-plane art in ST
// low, none in ST medium's 2 planes: the mono icon there). colourIn() says which.
// --------------------------------------------------------------------------
const ga = @import("gem_assets");
const gi = @import("gem_icons.zig");

pub const Icon = gi.Icon;
pub const tos1 = gi; // the built-in set (tools/gem_iconset_test.py checks the fallback against it)

/// One id's art: the 1bpp icon the old path draws (ink = data, body = mask & ~data),
/// the set's own mask (the engine's), and a colour image (bytes at palette index
/// PEN_BASE + pen, desktop/eng/looks.zig) when the set has one.
pub const Entry = struct { icon: Icon, mask: []const u8, col: ?[]const u8 = null };

pub const ID_NAMES = [_][]const u8{ "FLOPPY", "HARD", "TRASH", "FOLDER", "PROGRAM", "DOCUMENT" };

// In ID_NAMES order (desktop/eng/assets.zig Id).
pub const ENTRIES = [ID_NAMES.len]Entry{
    pick("FLOPPY", gi.FLOPPY), pick("HARD", gi.HARD),       pick("TRASH", gi.TRASH),
    pick("FOLDER", gi.FOLDER), pick("PROGRAM", gi.PROGRAM), pick("DOCUMENT", gi.DOCUMENT),
};

pub const FLOPPY = ENTRIES[0].icon;
pub const HARD = ENTRIES[1].icon;
pub const TRASH = ENTRIES[2].icon;
pub const FOLDER = ENTRIES[3].icon;
pub const PROGRAM = ENTRIES[4].icon;
pub const DOCUMENT = ENTRIES[5].icon;

/// The set has a colour icon: the old path must install the pens it indexes.
pub const has_colour = blk: {
    for (ENTRIES) |e| if (e.col != null) break :blk true;
    break :blk false;
};

/// The tallest ART (set rows, not the bitmap's h) of the set: the icon cell's baseline.
pub const TALLEST: i16 = blk: {
    @setEvalBranchQuota(200_000);
    var t: i16 = 0;
    for (ENTRIES) |e| t = @max(t, artRows(e.icon));
    break :blk t;
};

/// The entry whose icon `bmp` is (by its bitmap: the icons are constants), or null.
pub fn entryOf(bmp: Icon) ?*const Entry {
    for (&ENTRIES) |*e| if (e.icon.ink.ptr == bmp.ink.ptr) return e;
    return null;
}

/// `bmp`'s colour image when a screen of `planes` shows it (TOS 4: 4-plane art, 4+ planes).
pub fn colourIn(bmp: Icon, planes: u8) ?*const Entry {
    const e = entryOf(bmp) orelse return null;
    return if (e.col != null and planes >= 4) e else null;
}

fn pick(comptime id: []const u8, comptime builtin: Icon) Entry {
    if (find(ga.cicons, id)) |ic| return comptime convert(ic);
    if (find(ga.icons, id)) |ic| return comptime convert(ic);
    return .{ .icon = builtin, .mask = comptime orBits(builtin.ink, builtin.body) };
}

fn find(comptime list: []const ga.Icon, comptime id: []const u8) ?ga.Icon {
    inline for (list) |ic| {
        if (comptime eql(ic.id, id)) return ic;
    }
    return null;
}

fn convert(comptime ic: ga.Icon) Entry {
    @setEvalBranchQuota(100_000);
    const body = blk: {
        var out: [ic.mask.len]u8 = undefined;
        for (&out, 0..) |*b, i| b.* = ic.mask[i] & ~ic.data[i];
        const final = out;
        break :blk &final;
    };
    const icon: Icon = .{ .w = @intCast(ic.w), .h = @intCast(ic.h), .ink = ic.data, .body = body };
    return .{ .icon = icon, .mask = ic.mask, .col = ic.col };
}

fn orBits(comptime a: []const u8, comptime b: []const u8) []const u8 {
    @setEvalBranchQuota(100_000);
    var out: [a.len]u8 = undefined;
    for (&out, 0..) |*v, i| v.* = a[i] | b[i];
    const final = out;
    return &final;
}

fn artRows(comptime ic: Icon) i16 {
    const bpr = (@as(usize, ic.w) + 7) / 8;
    var y0: i16 = -1;
    var y1: i16 = -1;
    for (0..ic.h) |r| {
        for (0..bpr) |c| {
            const i = r * bpr + c;
            if (i >= ic.ink.len or i >= ic.body.len) break; // PROGRAM's rip is a row short of its h
            if (ic.ink[i] | ic.body[i] == 0) continue;
            if (y0 < 0) y0 = @intCast(r);
            y1 = @intCast(r);
        }
    }
    return if (y0 < 0) @intCast(ic.h) else y1 - y0 + 1;
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (x != y) return false;
    return true;
}
