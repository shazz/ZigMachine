// --------------------------------------------------------------------------
// F3 through the shifter: the colour registers change ALONG the lines.
// The VBL code's colour writes land at fixed (line, cycle) places -- the
// generator packs the program into each line's free cycles; replayed by
// prototypes/naos_nitrowave_re/gen_layout.py with Hatari's machine variant
// ($164 / $34 / 2 nops) -- so a line can show several palettes:
//   end of VBL   all 16 from $361BE (black): above line 0, and colours 0/1
//                until line 0's own
//   header       colours 2..15 (BLOCK1) before line 0
//   every line   colour 0 at cycle 42, colour 1 at 54 (line 228: 26, 38) from
//                the table at $5F24: the checkerboards' squares and the sky
//   three blocks colours 2..15 again, across lines 80/81, 145/146, 178/179
// A write at cycle c shows from capture x c + K. Hatari's 560 captured frames
// fit every K in -140..-56 alike (dam_fit.py): -98, the middle. Lines 0..254
// show (line 255 is black); physical (x, y) is line y - 12, pixel x + 12.
//
// Each row is drawn as palette entries 16 x segment + colour; the plane's HBL
// (which also opens the borders) loads that row's segments before it shows.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const st = @import("st.zig");
const LINE = @import("dam_vbl.zig").LINE;

const PW: usize = zg.PHYSICAL_WIDTH;
const PH: usize = zg.PHYSICAL_HEIGHT;
const TOP: usize = 12;
const FIRST_PX: usize = 12;
const LINES: usize = 255;
const K: i32 = -98;
const CAPTURE_X: i32 = 8; // capture x = physical x + 8
const MAX_SEG = 15;

const Write = struct { line: u16, cycle: u16, colour: u4, value: u16 };
const BLOCK1 = [14]u16{ 0x210, 0x210, 0x776, 0x776, 0x321, 0x321, 0x432, 0x432, 0x542, 0x542, 0x654, 0x654, 0x765, 0x765 };
/// The three later blocks, (line, cycle) from gen_layout.py.
const blocks = [_]Write{
    .{ .line = 80, .cycle = 422, .colour = 2, .value = 0x643 },  .{ .line = 80, .cycle = 458, .colour = 3, .value = 0x754 },
    .{ .line = 80, .cycle = 474, .colour = 4, .value = 0x433 },  .{ .line = 80, .cycle = 490, .colour = 5, .value = 0x532 },
    .{ .line = 81, .cycle = 20, .colour = 6, .value = 0x643 },   .{ .line = 81, .cycle = 86, .colour = 7, .value = 0x754 },
    .{ .line = 81, .cycle = 102, .colour = 8, .value = 0x655 },  .{ .line = 81, .cycle = 118, .colour = 9, .value = 0x532 },
    .{ .line = 81, .cycle = 134, .colour = 10, .value = 0x643 }, .{ .line = 81, .cycle = 150, .colour = 11, .value = 0x754 },
    .{ .line = 81, .cycle = 166, .colour = 12, .value = 0x544 }, .{ .line = 81, .cycle = 182, .colour = 13, .value = 0x532 },
    .{ .line = 81, .cycle = 198, .colour = 14, .value = 0x643 }, .{ .line = 81, .cycle = 214, .colour = 15, .value = 0x754 },
    .{ .line = 145, .cycle = 414, .colour = 4, .value = 0x34 },  .{ .line = 145, .cycle = 458, .colour = 5, .value = 0x34 },
    .{ .line = 145, .cycle = 474, .colour = 6, .value = 0x34 },  .{ .line = 145, .cycle = 490, .colour = 7, .value = 0x34 },
    .{ .line = 146, .cycle = 20, .colour = 8, .value = 0x45 },   .{ .line = 146, .cycle = 86, .colour = 9, .value = 0x45 },
    .{ .line = 146, .cycle = 102, .colour = 10, .value = 0x45 }, .{ .line = 146, .cycle = 118, .colour = 11, .value = 0x45 },
    .{ .line = 146, .cycle = 134, .colour = 12, .value = 0x156 }, .{ .line = 146, .cycle = 150, .colour = 13, .value = 0x156 },
    .{ .line = 146, .cycle = 166, .colour = 14, .value = 0x156 }, .{ .line = 146, .cycle = 182, .colour = 15, .value = 0x156 },
    .{ .line = 178, .cycle = 414, .colour = 2, .value = 0x100 }, .{ .line = 178, .cycle = 458, .colour = 3, .value = 0x100 },
    .{ .line = 178, .cycle = 474, .colour = 4, .value = 0x201 }, .{ .line = 178, .cycle = 490, .colour = 5, .value = 0x201 },
    .{ .line = 179, .cycle = 20, .colour = 6, .value = 0x312 },  .{ .line = 179, .cycle = 86, .colour = 7, .value = 0x312 },
    .{ .line = 179, .cycle = 102, .colour = 8, .value = 0x423 }, .{ .line = 179, .cycle = 118, .colour = 9, .value = 0x423 },
    .{ .line = 179, .cycle = 134, .colour = 10, .value = 0x534 }, .{ .line = 179, .cycle = 150, .colour = 11, .value = 0x534 },
    .{ .line = 179, .cycle = 166, .colour = 12, .value = 0x645 }, .{ .line = 179, .cycle = 182, .colour = 13, .value = 0x645 },
    .{ .line = 179, .cycle = 198, .colour = 14, .value = 0x756 }, .{ .line = 179, .cycle = 214, .colour = 15, .value = 0x756 },
};

/// Per physical row: how many palettes it shows and their colours.
const Row = struct { segs: u8, colours: [MAX_SEG][16]u32 };
var rows: []Row = &.{};

/// The physical x a write at `cycle` shows from (negative: before the row).
fn writeX(cycle: u16) i32 {
    return @as(i32, cycle) + K - CAPTURE_X;
}

/// The frame shown from `base` into the plane, and each row's palettes.
pub fn present(r: *const st.Ram, base: u32, px: []u8) void {
    if (rows.len == 0) rows = zg.mem.mustAlloc(Row, PH);
    var pal: [16]u16 = undefined;
    pal[0] = 0;
    pal[1] = 0;
    @memcpy(pal[2..], &BLOCK1);
    var b: usize = 0;
    for (0..PH) |y| {
        const out = px[y * PW ..][0..PW];
        if (y < TOP or y >= TOP + LINES) {
            @memset(out, 0);
            rows[y].segs = 1;
            @memset(&rows[y].colours[0], st.color(0).toRGBA());
            continue;
        }
        const line: u16 = @intCast(y - TOP);
        st.lineToChunky(r.bytes(base + 160 + LINE * @as(u32, line), LINE), FIRST_PX, out);
        b = row(r, line, &pal, b, out, &rows[y]);
    }
}

/// One line: apply its writes in order, opening a palette segment at each
/// that lands inside the row.
fn row(r: *const st.Ram, line: u16, pal: *[16]u16, b0: usize, out: []u8, dst: *Row) usize {
    var ws: [2 + 16]Write = undefined;
    var n: usize = 0;
    const special = line == 228;
    ws[0] = .{ .line = line, .cycle = if (special) 26 else 42, .colour = 0, .value = r.w(0x5F24 + 4 * @as(u32, line)) };
    ws[1] = .{ .line = line, .cycle = if (special) 38 else 54, .colour = 1, .value = r.w(0x5F26 + 4 * @as(u32, line)) };
    n = 2;
    var b = b0;
    while (b < blocks.len and blocks[b].line == line) : (b += 1) {
        ws[n] = blocks[b];
        n += 1;
    }
    std.sort.insertion(Write, ws[0..n], {}, byCycle);
    var seg: u8 = 0;
    var x: usize = 0;
    var k: usize = 0;
    while (k < n and writeX(ws[k].cycle) < PW) : (k += 1) {
        const wx = writeX(ws[k].cycle);
        if (wx > 0 and seg + 1 < MAX_SEG) {
            fill(dst, seg, pal);
            for (out[x..@intCast(wx)]) |*p| p.* +%= 16 * seg;
            x = @intCast(wx);
            seg += 1;
        }
        pal[ws[k].colour] = ws[k].value;
    }
    fill(dst, seg, pal);
    for (out[x..]) |*p| p.* +%= 16 * seg;
    dst.segs = seg + 1;
    for (ws[k..n]) |w| pal[w.colour] = w.value; // past the row's last pixel
    return b;
}

fn byCycle(_: void, a: Write, b: Write) bool {
    return a.cycle < b.cycle;
}

fn fill(dst: *Row, seg: u8, pal: *const [16]u16) void {
    for (&dst.colours[seg], pal) |*c, w| c.* = st.color(w).toRGBA();
}

/// The plane's HBL: open the borders, load this row's palettes.
pub fn hbl(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    fb.flickerBorder();
    if (line >= rows.len) return;
    const rw = &rows[line];
    for (0..rw.segs) |s| {
        for (rw.colours[s], 0..) |c, i| fb.palette[16 * s + i] = c;
    }
}
