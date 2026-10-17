// Tests for effects/tilemap.zig: blitTile (now blit.blit) against the original
// per-pixel clipped loop, for every tile of a sheet at positions clipped on
// each edge of a strided plane.
const std = @import("std");
const tm = @import("tilemap.zig");

const FakeFB = struct { fb: [*]u8, fb_w: u16, fb_h: u16, stride: u16 };

fn oldBlitTile(sheet: *const tm.TileSheet, fb: *FakeFB, tile: u16, dx: i16, dy: i16, key: u8) void {
    const tw: i16 = @intCast(sheet.tw);
    const th: i16 = @intCast(sheet.th);
    const pw: i16 = @intCast(fb.fb_w);
    const ph: i16 = @intCast(fb.fb_h);
    const scol: usize = @as(usize, tile % sheet.cols) * sheet.tw;
    const srow: usize = @as(usize, tile / sheet.cols) * sheet.th;
    var ty: i16 = 0;
    while (ty < th) : (ty += 1) {
        const py = dy + ty;
        if (py < 0 or py >= ph) continue;
        const drow = @as(usize, @intCast(py)) * fb.stride;
        const srow_off = (srow + @as(usize, @intCast(ty))) * sheet.sheet_w + scol;
        var tx: i16 = 0;
        while (tx < tw) : (tx += 1) {
            const px = dx + tx;
            if (px < 0 or px >= pw) continue;
            const idx = sheet.raw[srow_off + @as(usize, @intCast(tx))];
            if (idx == key) continue;
            fb.fb[drow + @as(usize, @intCast(px))] = idx;
        }
    }
}

test "blitTile draws exactly what the per-pixel loop drew" {
    var prng = std.Random.DefaultPrng.init(5);
    const rng = prng.random();
    var raw: [3 * 10 * 2 * 9]u8 = undefined; // 3 cols x 2 rows of 10x9 tiles
    for (&raw) |*p| p.* = if (rng.uintLessThan(u8, 3) == 0) 0 else rng.int(u8);
    const sheet = tm.TileSheet{ .raw = &raw, .sheet_w = 30, .tw = 10, .th = 9, .cols = 3 };
    var a: [52 * 20]u8 = undefined;
    var b: [52 * 20]u8 = undefined;
    var fa = FakeFB{ .fb = &a, .fb_w = 48, .fb_h = 20, .stride = 52 };
    var fbb = FakeFB{ .fb = &b, .fb_w = 48, .fb_h = 20, .stride = 52 };
    var dy: i16 = -10;
    while (dy <= 21) : (dy += 3) {
        var dx: i16 = -11;
        while (dx <= 49) : (dx += 1) {
            for (0..6) |tile| {
                rng.bytes(&a);
                b = a;
                oldBlitTile(&sheet, &fa, @intCast(tile), dx, dy, 0);
                tm.blitTile(&sheet, &fbb, @intCast(tile), dx, dy, 0);
                try std.testing.expectEqualSlices(u8, &a, &b);
            }
        }
    }
}
