// --------------------------------------------------------------------------
// TCB2 SUPERSCROLLER line palette: one HBL a line, writing as few colour
// registers as the line needs, as a raster coder would.
//
// drawFrame (compose.zig) leaves a Desc per ST row. A FAST row is a paired
// layer row (layers.zig): its entries are fixed, so the handler writes only
// the keys new on this line (F[w][key]), every key where the band starts (the
// line above was another band or a slow row), and the ink keys, whose colour
// follows the raster that scrolls under the letters. A SLOW row (the two
// where the copies overlap) was drawn per pixel, and its colours replay from
// the LinePalette exactly as linepal.hbl would. A register already holding the
// colour is never rewritten: on the board every palette store is a bus write,
// and more than 16 in one handler stall the compositor's snoop queue.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const L = @import("layers.zig");
const M = @import("motion.zig");
const compose = @import("compose.zig");

pub const Desc = packed struct(u32) {
    slow: bool = true,
    mode: L.Mode = .same,
    full: bool = false, // first line of a band: write every key
    ink: bool = false, // in the scroll canvas: the ink keys follow the raster
    r: u8 = 0, // image row
    w: u4 = 0, // Chrome's tap weight
    scroll_row: u8 = 0, // scroll-canvas row / 2 for rasterAt
    _: u8 = 0,
};

pub const Ctx = struct {
    desc: [A.H]Desc,
    tables: *const L.Tables,
    pal: *const compose.Palette,
    img: *const A.Images,
    motion: *const M.Motion,
};

var active: ?*const Ctx = null;

pub fn install(ctx: *const Ctx, fb: *zg.LogicalFB) void {
    active = ctx;
    fb.setFrameBufferHBLHandler(0, hbl);
}

fn hbl(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    const c = active orelse return;
    const row: usize = if (fb.hblLinesArePhysical()) @as(usize, line) -% zg.VERTICAL_BORDERS_HEIGHT else line;
    if (row >= A.H) return;
    const d = c.desc[row];
    if (d.slow) return slowRow(fb, c.pal, row);
    const rk = &c.tables.rows[@intFromEnum(d.mode)][d.r];
    const f = &c.tables.f[d.w];
    const n: usize = if (d.full) rk.n_all else rk.n_new;
    for (rk.ni_entry[0..n], rk.ni_key[0..n]) |e, k| set(fb, e, f[k]);
    if (!d.ink) return;
    const raster = compose.rasterAt(c.img, c.motion, 2 * @as(i32, d.scroll_row));
    for (rk.ink_entry[0..rk.n_ink], rk.ink_key[0..rk.n_ink]) |e, k| set(fb, e, compose.inkColour(c.img, d.w, raster, k));
}

fn slowRow(fb: *zg.LogicalFB, pal: *const compose.Palette, row: usize) void {
    for (pal.colours[row][0..pal.used[row]], 0..) |colour, i| set(fb, compose.Palette.FIRST + @as(u8, @intCast(i)), colour);
}

inline fn set(fb: *zg.LogicalFB, e: u8, colour: u32) void {
    if (fb.palette[e] != colour) fb.palette[e] = colour;
}
