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
// the border IS colour 0, so a colour-0 raster runs edge to edge.
const zg = @import("zigos");
const gen = @import("assets_gen.zig");
const ram = @import("ram.zig");

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;

pub const PW: usize = zg.PHYSICAL_WIDTH; // 400
pub const PH: usize = zg.PHYSICAL_HEIGHT; // 280
pub const OX: i32 = zg.HORIZONTAL_BORDERS_WIDTH; // mycanvas (0,0) = physical (40,40)
pub const OY: i32 = zg.VERTICAL_BORDERS_HEIGHT;
pub const BLACK: u32 = 0xFF00_0000;

pub const Borders = enum { closed, bottom, all };

/// Colour 0 per physical line: `now` is what the plane shows this frame,
/// `next` what hwClear paints the closed borders with at the START of the next
/// frame (it runs before the cart, so the table is built one frame ahead).
pub var c0_now: [PH]u32 = undefined;
pub var c0_next: [PH]u32 = undefined;
// The picture (a gid a physical pixel) is ram.buf.px; the per-line entries
// 1..used[y] that present() hands out are ram.buf.bank, as gids: the HBL looks
// the colour up, so the 280x255 table is u16, not u32.
var used: [PH]u8 = undefined;
var slot: [gen.NB_COLOURS]u8 = undefined;
var stamp: [gen.NB_COLOURS]u16 = undefined;
var stamp_gen: u16 = 0;
var borders: Borders = .closed;
/// Most entries one line needed, and pixels that found none (must stay 0).
pub var peak: u8 = 0;
pub var overflow: u32 = 0;

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
    peak = 0;
    overflow = 0;
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, planeHbl);
    zigos.setHBLHandler(borderHbl);
}

pub fn setBorders(b: Borders) void {
    borders = b;
}

pub fn clear() void {
    for (ram.buf.px) |*row| @memset(row, 0);
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
    const px = ram.buf.px;
    const bank = ram.buf.bank;
    for (0..PH) |y| {
        stamp_gen +%= 1;
        if (stamp_gen == 0) {
            @memset(&stamp, 0);
            stamp_gen = 1;
        }
        var n: u8 = 0;
        const out = fb.fb[y * PW ..][0..PW];
        for (px[y], out) |g, *o| {
            if (g == 0) {
                o.* = 0;
            } else if (stamp[g] == stamp_gen) {
                o.* = slot[g];
            } else if (n == 255) {
                overflow += 1;
                o.* = 255;
            } else {
                bank[y][n] = g;
                n += 1;
                stamp[g] = stamp_gen;
                slot[g] = n;
                o.* = n;
            }
        }
        used[y] = n;
        peak = @max(peak, n);
    }
}

/// The plane's HBL, physical line 0..279: open the part's borders, load colour
/// 0 and this line's entries.
fn planeHbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    const flick = switch (borders) {
        .closed => false,
        .bottom => line >= OY + zg.HEIGHT,
        .all => true,
    };
    if (flick) fb.flickerBorder();
    if (line >= PH) return;
    fb.palette[0] = c0_now[line];
    for (ram.buf.bank[line][0..used[line]], 1..) |g, i| fb.palette[i] = gen.colours[g];
}

/// Global HBL, physical line: a closed border shows colour 0.
fn borderHbl(zigos: *ZigOS, line: u16) void {
    zigos.setBackgroundColor(Color.fromRGBA(c0_next[@min(line, PH - 1)]));
}

/// End of the cart's frame: this frame's colour 0 becomes what the plane
/// shows; the part then fills c0_next for the next frame's borders.
pub fn flipColour0() void {
    c0_now = c0_next;
}
