// Native proof for the WAB part's precomputed flight (zig test, build.sh NATIVE_TESTS):
//   1. the comptime table is exactly what the same f64 maths gives at run time;
//   2. on every entry the integer blit (wab_turn.zig, no float) draws exactly what the
//      f64 blit it replaced drew (the reference below is that blit, kept verbatim but
//      writing into a plain buffer): the same texel on every pixel of every span,
//      the convex early-out included. Two synthetic textures whose bytes together
//      name the texel index make "the same pixels" mean "the same texels".
const std = @import("std");
const wt = @import("wab_table.zig");
const turn = @import("wab_turn.zig");

const LOGO = turn.LOGO;
const W = 400;
const H = 280;

// --- the f64 blit of wab_blit.zig before the table (the reference model) -----
const TILE = wt.TILE;
const HALF_TILE = wt.HALF_TILE;
const FRAC = 24;
const ONE: f64 = 16777216.0;
const FRAC_MASK: u32 = (1 << FRAC) - 1;
const EPS: u32 = 1 << 6;

fn texelF64(fl: wt.Flight, tx: f64, ty: f64, px: i32, py: i32) ?usize {
    const qy = 2 * (@as(f64, @floatFromInt(py)) - wt.ORIGIN_Y) + 1 - fl.cy;
    const qx = 2 * (@as(f64, @floatFromInt(px)) - wt.ORIGIN_X) + 1 - fl.cx;
    const u = fl.cs * qx + fl.sn * qy + HALF_TILE;
    const v = -fl.sn * qx + fl.cs * qy + HALF_TILE;
    if (u <= -1 or u >= TILE + 1 or v <= -1 or v >= TILE + 1) return null;
    const sx = @floor((tx * TILE + u) / 2);
    const sy = @floor((ty * TILE + v) / 2);
    if (sx < 0 or sx >= LOGO or sy < 0 or sy >= LOGO) return null;
    return @as(usize, @intFromFloat(sy)) * LOGO + @as(usize, @intFromFloat(sx));
}

fn nearInt(q: i32) bool {
    const frac: u32 = @as(u32, @bitCast(q)) & FRAC_MASK;
    return ((frac +% EPS) & FRAC_MASK) < 2 * EPS;
}

fn q24(x: f64) i32 {
    return @intFromFloat(@round(x * ONE));
}

fn refBlit(fb: []u8, fl: wt.Flight, i: usize, raw: []const u8) void {
    const tx: f64 = @floatFromInt(i % 8);
    const ty: f64 = @floatFromInt(i / 8);
    if (fl.x0 >= fl.x1 or fl.y0 >= fl.y1) return;
    const qx0 = 2 * (@as(f64, @floatFromInt(fl.x0)) - wt.ORIGIN_X) + 1 - fl.cx;
    const qy0 = 2 * (@as(f64, @floatFromInt(fl.y0)) - wt.ORIGIN_Y) + 1 - fl.cy;
    var u_row = q24(fl.cs * qx0 + fl.sn * qy0 + HALF_TILE);
    var v_row = q24(-fl.sn * qx0 + fl.cs * qy0 + HALF_TILE);
    const du_x = q24(2 * fl.cs);
    const dv_x = q24(-2 * fl.sn);
    const du_y = q24(2 * fl.sn);
    const dv_y = q24(2 * fl.cs);
    var py = fl.y0;
    while (py < fl.y1) : (py += 1) {
        var u = u_row;
        var v = v_row;
        var px = fl.x0;
        var inside = false;
        while (px < fl.x1) : (px += 1) {
            const t = if (nearInt(u) or nearInt(v)) texelF64(fl, tx, ty, px, py) else turn.texel(@intFromFloat(tx), @intFromFloat(ty), u, v);
            u += du_x;
            v += dv_x;
            const at = t orelse {
                if (inside) break;
                continue;
            };
            inside = true;
            fb[@as(usize, @intCast(py)) * W + @as(usize, @intCast(px))] = raw[at];
        }
        u_row += du_y;
        v_row += dv_y;
    }
}

test "the comptime table is the f64 setup, recomputed at run time" {
    const tiles = wt.tiles();
    var n: usize = 0;
    for (0..wt.ENDVBL) |f| {
        try std.testing.expectEqual(n, wt.FIRST[f]);
        for (0..wt.NT) |i| if (wt.setup(tiles[i], i, @intCast(f))) |e| {
            try std.testing.expectEqual(e, wt.ENTRIES[n]);
            n += 1;
        };
    }
    try std.testing.expectEqual(n, wt.ENTRIES.len);
    try std.testing.expectEqual(n, wt.FIRST[wt.ENDVBL]);
}

test "the integer blit draws the f64 blit's texels on every entry" {
    var lo: [LOGO * LOGO]u8 = undefined;
    var hi: [LOGO * LOGO]u8 = undefined;
    for (0..LOGO * LOGO) |k| {
        lo[k] = @intCast(k % 255 + 1); // never 0: every texel the tile reaches is drawn
        hi[k] = @intCast(k / 255 + 1);
    }
    const a = try std.testing.allocator.alloc(u8, W * H);
    defer std.testing.allocator.free(a);
    const b = try std.testing.allocator.alloc(u8, W * H);
    defer std.testing.allocator.free(b);
    const tiles = wt.tiles();
    var near: usize = 0; // pixels where the reference took its f64 fallback
    for (wt.ENTRIES, 0..) |e, k| {
        const fl = wt.flight(tiles[e.tile], e.tile, frameOf(k)).?;
        for ([2][]const u8{ &lo, &hi }) |raw| {
            @memset(a, 0);
            @memset(b, 0);
            refBlit(a, fl, e.tile, raw);
            turn.blit(b.ptr, W, e, raw, null);
            try std.testing.expectEqualSlices(u8, a, b);
        }
        near += nearCount(e);
    }
    std.debug.print("wab_table: {d} entries ({d} B), {d} pixels near an integer, all equal\n", .{ wt.ENTRIES.len, @sizeOf(@TypeOf(wt.ENTRIES)), near });
}

fn frameOf(k: usize) u32 {
    var f: u32 = 0;
    while (wt.FIRST[f + 1] <= k) f += 1;
    return f;
}

fn nearCount(e: wt.Entry) usize {
    var n: usize = 0;
    var u_row = e.u0;
    var v_row = e.v0;
    for (0..e.h) |_| {
        var u = u_row;
        var v = v_row;
        for (0..e.w) |_| {
            if (nearInt(u) or nearInt(v)) n += 1;
            u += e.du;
            v += e.dv;
        }
        u_row -= e.dv;
        v_row += e.du;
    }
    return n;
}
