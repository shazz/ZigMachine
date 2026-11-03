// --------------------------------------------------------------------------
// grodan_kvack ZIG mode -- the original's foreground layers on the 400x280
// overscan plane: the 12 carebears, the big scroller, the vertical scrolltext
// (its six copies plus two more in the side borders) and the two small
// scrollers.  Same art (chunky.zig), same state (model.zig), same keyed CHISEL
// blits as draw.zig; only the window is the whole overscan raster, so the
// content sits at (40, 40) and the scrollers run on through the borders.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const model = @import("model.zig");
const C = @import("chunky.zig");

pub const W: i32 = zg.PHYSICAL_WIDTH; // 400
pub const H: i32 = zg.PHYSICAL_HEIGHT; // 280
/// Where the original's 320x200 picture sits in the overscan window.
pub const OX: i32 = zg.HORIZONTAL_BORDERS_WIDTH; // 40
pub const OY: i32 = zg.VERTICAL_BORDERS_HEIGHT; // 40

/// The two extra vertical-scrolltext copies, centred in the 40-px side borders.
pub const BORDER_X = [2]i32{ (OX - C.VERT_W) / 2, W - OX + (OX - C.VERT_W) / 2 };

pub var blits_last_frame: u32 = 0;

pub fn draw(st: *const model.State, fb: *zg.LogicalFB, bl: *zg.Blitter, art: *const C.Art) void {
    blits_last_frame = 0;
    for (0..12) |i| {
        const at = st.spriteAt(i);
        put(fb, bl, art.sprites[i * 16 * A.SPRITE_H ..][0 .. 16 * A.SPRITE_H], 16, at[0] + OX, at[1] + OY);
    }
    big(st, fb, bl, art);
    vert(st, fb, bl, art);
    put(fb, bl, art.small[0], @intCast(st.s3.cells.len * 8), st.s3.scroll + OX, 8 + OY);
    put(fb, bl, art.small[1], @intCast(st.s4.cells.len * 8), st.s4.scroll + OX, 32 + OY);
}

/// Keyed blit of the whole iw-wide image at window (dx, dy), clipped to 400x280.
fn put(fb: *zg.LogicalFB, bl: *zg.Blitter, img: []const u8, iw: i32, dx: i32, dy: i32) void {
    const ih: i32 = @intCast(img.len / @as(usize, @intCast(iw)));
    const x0 = @max(dx, 0);
    const y0 = @max(dy, 0);
    const x1 = @min(dx + iw, W);
    const y1 = @min(dy + ih, H);
    if (x1 <= x0 or y1 <= y0) return;
    bl.blitImage(fb, @intCast(x0), @intCast(y0), img, @intCast(iw), @intCast(x0 - dx), @intCast(y0 - dy), @intCast(x1 - x0), @intCast(y1 - y0), 0);
    blits_last_frame += 1;
}

/// draw.big() over the wider window: cell k at x = OX + (scroll + 24k) * 4.
fn big(st: *const model.State, fb: *zg.LogicalFB, bl: *zg.Blitter, art: *const C.Art) void {
    const s = &st.s1;
    // The first cell still in the window: OX + (scroll + 24k) * 4 + 96 > 0.
    const k0: usize = @intCast(@max(0, @divFloor(-34 - s.scroll, 24) + 1));
    var k: usize = k0;
    while (k < s.cells.len) : (k += 1) {
        const x = OX + (s.scroll + @as(i32, @intCast(k)) * 24) * 4;
        if (x >= W) break;
        const slot = C.BIG_SLOT[s.cells[k]];
        if (slot == 0xFF) continue;
        const size = C.BIG_W * C.BIG_H;
        put(fb, bl, art.big[@as(usize, slot) * size ..][0..size], C.BIG_W, x, 100 + OY);
    }
}

/// draw.vert(): the six original copies and the two border copies, all from
/// the same strip, now clipped to the 280 rows of the overscan window.
fn vert(st: *const model.State, fb: *zg.LogicalFB, bl: *zg.Blitter, art: *const C.Art) void {
    const base = 400 - st.s2.scroll;
    const q = @divFloor(base, 2);
    const p: usize = @intCast(base - 2 * q);
    const strip = art.vert[p];
    for (model.VERT_X) |x| put(fb, bl, strip, C.VERT_W, x + OX, q + OY);
    for (BORDER_X) |x| put(fb, bl, strip, C.VERT_W, x, q + OY);
}
