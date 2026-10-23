// --------------------------------------------------------------------------
// grodan_kvack -- the frame on CHISEL: model.zig's compose() as blits.
//
// Same layers, same order, same clipping as compose() (bgGreen, bgPink, 12
// sprites, big, vertical, small x2), each one a keyed (key 0) blit of the art
// chunky.zig expanded once.  A frame is one fill + ~25 blits (~0.35 Mc of
// CHISEL) instead of ~130,000 CPU mask tests and ~17,000 byte stores.
// model.compose() stays as the reference the harness's pixel model mirrors.
//
// Every blit is clipped HERE to the 320x200 plane (source offset + size), so
// nothing depends on how CHISEL clips a rectangle that leaves the plane, and a
// source rectangle never runs past its image.  No blit reads the plane it
// writes (all sources are cart RAM).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const model = @import("model.zig");
const C = @import("chunky.zig");

const W: i32 = model.W;
const H: i32 = model.H;

pub var blits_last_frame: u32 = 0;

pub fn frame(st: *const model.State, fb: *zg.LogicalFB, bl: *zg.Blitter, art: *const C.Art) void {
    blits_last_frame = 0;
    bl.fill(fb, 0, 0, @intCast(W), @intCast(H), A.BLACK);
    tile(fb, bl, art.green, st.moveX, st.moveY);
    tile(fb, bl, art.pink, st.X, st.Y);
    for (0..12) |i| {
        const at = st.spriteAt(i);
        put(fb, bl, art.sprites[i * 16 * A.SPRITE_H ..][0 .. 16 * A.SPRITE_H], 16, at[0], at[1]);
    }
    big(st, fb, bl, art);
    vert(st, fb, bl, art);
    small(fb, bl, art.small[0], &st.s3, 8);
    small(fb, bl, art.small[1], &st.s4, 32);
}

/// Keyed blit of the whole iw-wide image `img` with its top-left at (dx, dy),
/// clipped to the plane.
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

/// model.tile(): the 320x199 mask at (ox/2 + 320*xx, oy/2 + 200*yy).
fn tile(fb: *zg.LogicalFB, bl: *zg.Blitter, img: []const u8, ox: i32, oy: i32) void {
    const x_off = @divFloor(ox, 2);
    const y_off = @divFloor(oy, 2);
    var yy: i32 = 0;
    while (yy < 2) : (yy += 1) {
        var xx: i32 = 0;
        while (xx < 3) : (xx += 1) put(fb, bl, img, A.BG_W, x_off + W * xx, y_off + 200 * yy);
    }
}

/// drawBig(): cell k at x = (scroll + 24k) * 4, rows 100..198.
fn big(st: *const model.State, fb: *zg.LogicalFB, bl: *zg.Blitter, art: *const C.Art) void {
    const s = &st.s1;
    // The first cell still on screen: (scroll + 24k) * 4 + 96 > 0.
    const k0: usize = @intCast(@max(0, @divFloor(-24 - s.scroll, 24) + 1));
    var k: usize = k0;
    while (k < s.cells.len) : (k += 1) {
        const xgo = (s.scroll + @as(i32, @intCast(k)) * 24) * 4;
        if (xgo + 96 <= 0) continue;
        if (xgo >= W) break;
        const slot = C.BIG_SLOT[s.cells[k]];
        if (slot == 0xFF) continue;
        const size = C.BIG_W * C.BIG_H;
        put(fb, bl, art.big[@as(usize, slot) * size ..][0..size], C.BIG_W, xgo, 100);
    }
}

/// drawVert(): base = 400 - scroll = 2q + p puts strip p's row j at y = q + j.
fn vert(st: *const model.State, fb: *zg.LogicalFB, bl: *zg.Blitter, art: *const C.Art) void {
    const base = 400 - st.s2.scroll;
    const q = @divFloor(base, 2);
    const p: usize = @intCast(base - 2 * q);
    const strip = art.vert[p];
    for (model.VERT_X) |x| put(fb, bl, strip, C.VERT_W, x, q);
}

/// drawSmall(): cell k at x = scroll + 8k, rows y0..y0+7.
fn small(fb: *zg.LogicalFB, bl: *zg.Blitter, strip: []const u8, s: *const model.Scroll, y0: i32) void {
    put(fb, bl, strip, @intCast(s.cells.len * 8), s.scroll, y0);
}
