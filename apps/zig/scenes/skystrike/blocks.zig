// --------------------------------------------------------------------------
// SCREEN COPY and SCREEN$: STOS's block moves. Both work on 16-pixel
// columns: every x is rounded DOWN to a multiple of 16 (the cloud bands at
// x = 10, 110, 210 land at 0, 96, 208 on the ST screen). SCREEN COPY is a
// plain copy; a SCREEN$ block pasted back is TRANSPARENT where it is colour
// 0 (measured: the clouds and the officers' mess leave the sky's colour 14
// wherever their source is 0), and goes to back too under AUTO BACK, like
// the other drawing commands.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const scr = @import("scr.zig");
const gfx = @import("gfx.zig");

fn floor16(x: i32) i32 {
    return x & ~@as(i32, 15);
}

/// SCREEN COPY src,x1,y1,x2,y2 TO dst,x,y.
pub fn copy(src: scr.Id, x1: i32, y1: i32, x2: i32, y2: i32, dst: scr.Id, dx: i32, dy: i32) void {
    const sx = floor16(x1);
    const w = floor16(x2) - sx;
    const h = y2 - y1;
    const s = scr.get(src);
    const d = scr.get(dst);
    const tx = floor16(dx);
    // A copy down the same screen goes bottom up, as a block move must.
    const up = src == dst and dy > y1;
    var k: i32 = 0;
    while (k < h) : (k += 1) {
        const j = if (up) h - 1 - k else k;
        const sy = y1 + j;
        const ty = dy + j;
        if (sy < 0 or sy > 199 or ty < 0 or ty > 199) continue;
        var i: i32 = 0;
        while (i < w) : (i += 1) {
            const a = sx + i;
            const b = tx + i;
            if (a < 0 or a > 319 or b < 0 or b > 319) continue;
            d[@intCast(ty * 320 + b)] = s[@intCast(sy * 320 + a)];
        }
    }
}

/// SCREEN COPY src TO dst: the whole picture and its palette.
pub fn copyAll(src: scr.Id, dst: scr.Id) void {
    if (src == dst) return;
    @memcpy(scr.get(dst), scr.get(src));
    scr.pal[@intFromEnum(dst)] = scr.pal[@intFromEnum(src)];
}

/// A SCREEN$ block: a rectangle of indices, at most the whole screen. Its
/// pixels come from the cart RAM arena (block()), once per cart load.
pub const Block = struct {
    w: i32 = 0,
    h: i32 = 0,
    px: []u8 = &.{},
};

pub fn block() Block {
    return .{ .px = zg.mem.mustAlloc(u8, scr.PIX) };
}

/// SCREEN$(src, x1, y1 TO x2, y2).
pub fn get(b: *Block, src: scr.Id, x1: i32, y1: i32, x2: i32, y2: i32) void {
    const sx = floor16(x1);
    b.w = @max(0, floor16(x2) - sx);
    b.h = @max(0, y2 - y1);
    // The buffer holds one screen: a larger rectangle keeps the rows that fit
    // rather than writing past it (no call in the game comes near).
    if (b.w > 0) b.h = @min(b.h, @as(i32, @intCast(b.px.len / @as(usize, @intCast(b.w)))));
    const s = scr.get(src);
    var j: i32 = 0;
    while (j < b.h) : (j += 1) {
        var i: i32 = 0;
        while (i < b.w) : (i += 1) {
            const x = sx + i;
            const y = y1 + j;
            const inside = x >= 0 and x < 320 and y >= 0 and y < 200;
            b.px[@intCast(j * b.w + i)] = if (inside) s[@intCast(y * 320 + x)] else 0;
        }
    }
}

/// SCREEN$(dst, x, y) = block.
pub fn put(b: *const Block, dst: scr.Id, x: i32, y: i32) void {
    var tb: [2][]u8 = undefined;
    const saved = scr.logic;
    scr.logic = dst;
    defer scr.logic = saved;
    for (gfx.targets(&tb)) |d| putOn(b, d, floor16(x), y);
}

fn putOn(b: *const Block, d: []u8, x: i32, y: i32) void {
    var j: i32 = 0;
    while (j < b.h) : (j += 1) {
        const ty = y + j;
        if (ty < 0 or ty > 199) continue;
        var i: i32 = 0;
        while (i < b.w) : (i += 1) {
            const tx = x + i;
            if (tx < 0 or tx > 319) continue;
            const v = b.px[@intCast(j * b.w + i)];
            if (v != 0) d[@intCast(ty * 320 + tx)] = v;
        }
    }
}

/// SCREEN$(dst, x, y) = SCREEN$(src, x1, y1 TO x2, y2), the game's usual form.
var tmp: Block = .{};
/// The game's s$ (940's sea line).
pub var aux: Block = .{};
pub fn alloc() void {
    if (tmp.px.len == 0) tmp = block();
    if (aux.px.len == 0) aux = block();
}

pub fn move(src: scr.Id, x1: i32, y1: i32, x2: i32, y2: i32, dst: scr.Id, x: i32, y: i32) void {
    get(&tmp, src, x1, y1, x2, y2);
    put(&tmp, dst, x, y);
}
