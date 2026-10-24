// The frame: every part draws COLOUR IDS (gids) into one physical 400x280
// buffer; present() turns each row into palette indices, handing out entries
// 1..255 PER LINE to exactly the colours that line shows, and the plane's HBL
// loads that line's entries before the line is drawn -- the per-line palette of
// a Spectrum-512 picture, and the only way main.png's 272 colours and the TCB
// cylinder's ~350 tints fit a 256-entry palette.
//
// gid 0 is COLOUR 0: the background. Its colour is a table per physical line
// (the rasters), written to entry 0 by the plane's HBL and, for the borders the
// part leaves closed, to the machine background by the global HBL -- on an ST
// the border IS colour 0, so a colour-0 raster runs edge to edge (when the
// table is one colour, the background register alone: border.zig).
const zg = @import("zigos");
const gen = @import("assets_gen.zig");
const ram = @import("ram.zig");
const border = @import("border.zig");

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;

pub const PW: usize = zg.PHYSICAL_WIDTH; // 400
pub const PH: usize = zg.PHYSICAL_HEIGHT; // 280
pub const OX: i32 = zg.HORIZONTAL_BORDERS_WIDTH; // mycanvas (0,0) = physical (40,40)
pub const OY: i32 = zg.VERTICAL_BORDERS_HEIGHT;
pub const BLACK: u32 = 0xFF00_0000;

/// top_sides: every line above the bottom border (TCB #1's fullscreen).
pub const Borders = enum { closed, bottom, all, top_sides };

/// Colour 0 per physical line: `now` is what the plane shows this frame,
/// `next` what hwClear paints the closed borders with at the START of the next
/// frame (it runs before the cart, so the table is built one frame ahead).
pub var c0_now: [PH]u32 = undefined;
pub var c0_next: [PH]u32 = undefined;
// The picture (a gid a pixel) is ram.buf.px; the entries 1..used[y] present()
// hands out are ram.buf.bank, as gids (the HBL looks the colour up: u16, not u32).
var used: [PH]u8 = undefined;
var slot: [gen.NB_COLOURS]u8 = undefined;
var stamp: [gen.NB_COLOURS]u16 = undefined;
var stamp_gen: u16 = 0;
var borders: Borders = .closed;
/// A part from the disk is on screen (st_show.zig): the plane holds its 16
/// palette indices and ram.buf.pal its colours per line, not gids.
pub var st_mode: bool = false;
/// Most entries one line needed, and pixels that found none (must stay 0).
pub var peak: u8 = 0;
pub var overflow: u32 = 0;
/// What last drew the framebuffer (0 present(), 2 st_show, 3 TCB #1's mirror): each
/// writes only what changed while it still owns the framebuffer.
pub var fb_owner: u8 = 0;
// What this plane's registers hold on the line being drawn: entry 0's colour and
// the GID of entries 1..255 (one gid, one colour: no lookup to compare). An HBL
// writes only the entries that change, as a raster coder does; reset at line 0,
// so every entry is written once per frame.
var hw0: u32 = 0;
var hw16: [16]u32 = undefined; // a part's: its 16 registers (st_mode)
var hw_gid: [255]u16 = undefined;
const NO_GID: u16 = 0xFFFF;

pub fn init(zigos: *ZigOS) void {
    ram.init();
    const fb = &zigos.lfbs[0];
    fb.setOverscanBuffer();
    fb.is_enabled = true;
    @memset(&stamp, 0);
    stamp_gen = 0;
    @memset(&used, 0);
    @memset(&c0_now, BLACK);
    @memset(&c0_next, BLACK);
    borders = .closed;
    st_mode = false;
    peak = 0;
    overflow = 0;
    fb_owner = 0;
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, planeHbl);
    border.init(zigos);
}

pub fn setBorders(b: Borders) void {
    borders = b;
}

pub fn clear() void {
    for (ram.buf.px) |*row| @memset(row, 0);
}

/// Clear physical rows [y0, y1) only: the rows the menu redraws every frame.
pub fn clearRows(y0: usize, y1: usize) void {
    for (ram.buf.px[y0..y1]) |*row| @memset(row, 0);
}

/// Plot a gid at mycanvas-ST coordinates (the 320x225 remake canvas, halved).
pub inline fn put(x: i32, y: i32, g: u16) void {
    const X = x + OX;
    const Y = y + OY;
    if (X < 0 or Y < 0 or X >= PW or Y >= PH) return;
    ram.buf.px[@intCast(Y)][@intCast(X)] = g;
}

/// Colour 0 for the mycanvas-ST row `y` in a per-line table.
pub fn setC0(table: *[PH]u32, y: i32, rgba: u32) void {
    const Y = y + OY;
    if (Y >= 0 and Y < PH) table[@intCast(Y)] = rgba;
}

/// Rows -> plane indices, handing out each line's entries.
pub fn present(fb: *LogicalFB) void {
    presentRows(fb, 0, PH, 0, PW);
}

/// present() for rows [y0, y1), columns [x0, x1) (multiples of 4). A row's indices
/// and entries depend on its gids alone, so rows left alone keep what an earlier
/// present() made of them. The caller vouches that the columns left out are gid 0
/// and index 0 in the plane already (a gid 0 takes no entry: same entries).
pub fn presentRows(fb: *LogicalFB, y0: usize, y1: usize, x0: usize, x1: usize) void {
    fb_owner = 0;
    const px = ram.buf.px;
    const bank = ram.buf.bank;
    for (y0..y1) |y| {
        stamp_gen +%= 1;
        if (stamp_gen == 0) {
            @memset(&stamp, 0);
            stamp_gen = 1;
        }
        var n: u8 = 0;
        const row = px[y][x0..x1];
        const line = &bank[y];
        // four indices a 32-bit store: a quarter of the framebuffer stores
        const out: [*]u32 = @ptrCast(@alignCast(fb.fb + (y * PW + x0)));
        for (0..row.len / 4) |q| {
            var word: u32 = 0;
            inline for (0..4) |k| word |= @as(u32, index(row[4 * q + k], line, &n)) << (8 * k);
            out[q] = word;
        }
        used[y] = n;
        peak = @max(peak, n);
    }
}

/// The plane index of gid `g` on a line, handing it entry n+1 if it has none yet.
inline fn index(g: u16, line: *[255]u16, n: *u8) u8 {
    if (g == 0) return 0;
    if (stamp[g] == stamp_gen) return slot[g];
    if (n.* == 255) {
        overflow += 1;
        return 255;
    }
    line[n.*] = g;
    n.* += 1;
    stamp[g] = stamp_gen;
    slot[g] = n.*;
    return n.*;
}

/// The plane's HBL, physical line 0..279: open the borders, load this line's colours.
fn planeHbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    const flick = switch (borders) {
        .closed => false,
        .bottom => line >= OY + zg.HEIGHT,
        .top_sides => line < OY + zg.HEIGHT,
        .all => true,
    };
    if (flick) fb.flickerBorder();
    if (line >= PH) return;
    const pal = fb.palette; // once: a store to the tables below could be one to *fb
    if (st_mode) { // a real part: its 16 colour registers, as they stand on this line
        if (line > 0 and ram.buf.same[line]) return; // the line above's colours: no change
        // what differs from the colours the registers hold (all of them on line 0)
        for (&ram.buf.pal[line], &hw16, 0..) |c, *h, i| if (line == 0 or c != h.*) {
            h.* = c;
            pal[i] = c;
        };
        return;
    }
    if (line == 0) {
        hw0 = 0;
        @memset(&hw_gid, NO_GID);
    }
    const c0 = c0_now[line];
    if (hw0 != c0) {
        hw0 = c0;
        pal[0] = c0;
    }
    const bank = &ram.buf.bank[line];
    for (0..used[line]) |k| { // entry k + 1
        const g = bank[k];
        if (hw_gid[k] == g) continue;
        hw_gid[k] = g;
        pal[k + 1] = gen.colours[g];
    }
}

/// End of the cart's frame: this frame's colour 0 becomes what the plane
/// shows; the part then fills c0_next for the next frame's borders.
pub fn flipColour0() void {
    c0_now = c0_next;
}
