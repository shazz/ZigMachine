// --------------------------------------------------------------------------
// P5 kaleidoscope, 16 px true-colour cells. Kernel $1A230, top border open.
// The init ($1A194) precalculates 128 frames x 68 rows x 14 colours, each
//   R[m[a]] | G[m[b]] | B[m[c]]   (tables $1A6AA/$1A6CA/$1A6EA)
// from one 128x128 nibble map read at three offsets that move with the frame
// p. Here a row is computed when the kernel shows it, from the same formula:
// 14 x 3 lookups a row cost less than keeping 240 KB of frames.
// Display: blocks of 2 identical lines, 26 cells = the row and its mirror;
// block b < 67 shows row b, block 67+t row 67-t: a 4-way kaleidoscope. Only
// the first N blocks show, N growing as the reveal counter runs.
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const assets = @import("assets.zig");

var phase: u32 = 0; // $1A78A
var speed: u32 = 0; // $1A78C
var frameofs: u32 = 0; // $3C67E, $770 bytes a frame
var nblocks: u32 = 0;
var reveal_ofs: u32 = 0; // $1A1E6

pub fn reset() void {
    phase = rip.P5_PHASE;
    speed = rip.P5_SPEED;
    frameofs = rip.P5_FRAMEOFS;
    nblocks = 0;
    reveal_ofs = rip.P5_REVEAL;
}

pub fn vbl() void {
    core.colour = 0;
}

/// The map as the init lays it out: 16 KB, then a copy, so offsets wrap.
inline fn at(o: u32) u16 {
    return assets.p5_map[o & 0x3FFF];
}

/// Precalc frame p, row r, column x.
fn cell(p: u32, r: u32, x: u32) u16 {
    const o = p * 128 + r * 128 + x;
    return rip.P5_RGB[at(o)] | rip.P5_RGB[16 + at(0x28 + p + o)] | rip.P5_RGB[32 + at(0x3FD0 - p + r * 128 + x)];
}

/// $1A754: the frame shown follows a sine.
fn sineFrame() void {
    phase = (phase + speed) & 0x7FF;
    const v = core.sinMul(phase >> 1, 0x1FF);
    frameofs = @as(u32, @intCast(@mod(256 + v, 128))) * 0x770;
}

pub fn m1a1c2() void {
    sineFrame();
    nblocks = @max(nblocks, reveal_ofs / 0x12C + 1);
    if (reveal_ofs != 0x9D08) reveal_ofs += 0x12C;
}

pub fn m1a22a() void {
    sineFrame();
}

pub fn m1a216() void {
    sineFrame();
    speed = 4;
}

pub fn kernel(l0: u32) void {
    const f = frameofs / 0x770;
    for (0..nblocks) |bi| {
        const b: u32 = @intCast(bi);
        const r = if (b < 67) b else 134 - b;
        var vals: [26]u16 = undefined;
        for (0..14) |x| vals[x] = cell(f, r, @intCast(x));
        for (0..12) |k| vals[14 + k] = vals[12 - k];
        for ([_]u32{ 340, 852 }) |base| {
            for (vals, 0..) |v, j| out.emit(l0, base + 1024 * b + 16 * @as(u32, @intCast(j)), v);
            out.emit(l0, base + 408 + 1024 * b, 0);
        }
    }
    core.colour = 0;
}
