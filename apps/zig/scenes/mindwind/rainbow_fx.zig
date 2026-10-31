// --------------------------------------------------------------------------
// Part C: the three interference images (rainbow_gen.zig) on the 180 field
// lines, image row k on line 14 + k, animated by PALETTE CYCLING only: each
// VBL the hook $4818 rotates the 16 STE colours at $2F934 one step and writes
// the new colour 0 into every field line. Nothing moves in the bitmap.
//   reveal $476C: rows 90..90 to 0..179, one more each way a frame ($47B6)
//   full   $47FC: all 180 rows (the reversed half)
// The palette words are rotated in place in the demo's data; here in a copy.
// --------------------------------------------------------------------------
const data = @import("data.zig");
const lines = @import("lines.zig");
const vram = @import("vram.zig");
const gen = @import("rainbow_gen.zig");

const FIRST: usize = 14;
pub const N: usize = 180;

pub var pal: [16]u16 = undefined;
var lo: i16 = 0; // $47F8
var hi: i16 = 0; // $47FA
var image: usize = 0;

pub fn init() void {
    pal = data.palette(data.pal_rainbow);
}

/// $4526-$4542 / $460E-$4634: the field's lines on the empty rows of an image-sized buffer.
pub fn empty() void {
    lines.fill(FIRST, N, vram.blank, 0);
}

pub fn startReveal(k: usize) void {
    image = k;
    lo = 0x5a;
    hi = 0x5a;
}

/// One frame of $476C's loop; true when it has finished (and drawn all rows).
pub fn reveal() bool {
    if (lo < 0) {
        lo = 0;
        hi = N - 1;
        rows();
        return true;
    }
    rows();
    hi += 1;
    lo -= 1;
    return false;
}

pub fn full(k: usize) void {
    image = k;
    lo = 0;
    hi = N - 1;
    rows();
}

fn rows() void {
    if (hi < lo) return;
    var r: usize = @intCast(lo);
    while (r <= @as(usize, @intCast(hi))) : (r += 1) {
        lines.table[FIRST + r].src = vram.rainbow[image] + @as(u32, @intCast(r)) * gen.W;
    }
}

/// The VBL hook $4818: rotate, then colour 0 on the field lines.
pub fn cycle() void {
    const first = pal[0];
    for (0..15) |i| pal[i] = pal[i + 1];
    pal[15] = first;
    lines.setColour(FIRST, N, pal[0]);
}
