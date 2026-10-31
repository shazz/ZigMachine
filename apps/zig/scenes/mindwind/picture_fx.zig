// --------------------------------------------------------------------------
// Part B: Sh3's 320x200 picture in full overscan. Its 320-px rows are read 416
// px at a time, so a line runs on into the next row: the picture WRAPS, as on
// the STE, for free.
//   wobble $A774: picture row i on line 4 + i, starting x px in; x comes from
//          a ring of 208 sine values ($8D64), two new ones a frame ($8CC2):
//          x = 288 + sin(phase) * amplitude / 16384, the speed / amplitude
//          following a script ($BA2A). The oldest entry is on line 4, so the
//          wave climbs.
//   flip   $B2BA (+ $B456 in kernel $1628): the same rows and x, but row i
//          goes to the line a table gives for this frame (90 frames x 200,
//          $3E496): the picture turns over. Lines nobody claims are blank.
// Colour 0 is the faded palette's colour 0 on every line the effect owns.
// --------------------------------------------------------------------------
const data = @import("data.zig");
const lines = @import("lines.zig");
const vram = @import("vram.zig");

const RING: usize = 208; // $680 / 8
var ring: [RING]u16 = [_]u16{0} ** RING; // x in px
var at: usize = 0; // $BA1A / 8: the entry the next one goes to (+1)
var phase: u16 = 0; // $BA1C
var speed: u16 = 2; // $BA1E
var limit: u16 = 0x400; // $BA20
var amp: u16 = 0; // $BA22
var count: u16 = 0; // $BA24
var script: usize = 0; // $BA26: word index into the script
var flip_frame: u16 = 0; // $B618

inline fn sw(i: usize) u16 {
    return data.be16(data.wobble_script, i);
}

/// $8CC2: one new ring entry.
fn push() void {
    phase = (phase +% speed) & 0x3ff;
    var d1 = count +% speed;
    if (@as(i16, @bitCast(d1)) > @as(i16, @bitCast(limit))) {
        d1 -%= limit;
        var s = sw(script);
        script += 1;
        if (@as(i16, @bitCast(s)) < 0) { // the end: back to the script's start
            script = 1;
            s = sw(0);
        }
        speed = s;
        limit = sw(script);
        amp = sw(script + 1);
        script += 2;
    }
    count = d1;
    const sin: i32 = @as(i16, @bitCast(data.be16(data.sin_b61a, phase / 2)));
    const prod: i32 = sin *% @as(i16, @bitCast(amp)); // muls.w
    const x: i16 = @truncate(@as(i32, @bitCast(@as(u32, @bitCast(prod)) << 2)) >> 16);
    at = (at + 1) % RING;
    ring[(at + RING - 1) % RING] = @bitCast(x +% 0x120);
}

inline fn src(i: usize) u32 {
    const x: u32 = ring[(at + i) % RING];
    return vram.pic + @as(u32, @intCast(i)) * vram.PIC_W + x;
}

pub fn wobble(colour0: u16) void {
    lines.setColour(0, 4, colour0);
    for (0..200) |i| lines.table[4 + i] = .{ .src = src(i), .colour = colour0 };
    lines.setColour(204, 4, colour0);
    push();
    push();
}

pub fn flip(colour0: u16) void {
    push();
    push();
    const t = flip_frame;
    flip_frame = if (flip_frame + 1 == 90) 0 else flip_frame + 1;
    lines.fill(0, 208, vram.blank, colour0);
    for (0..200) |i| {
        const off: u16 = data.be16(data.flip, @as(usize, t) * 200 + i);
        lines.table[4 + off / 8] = .{ .src = src(i), .colour = colour0 };
    }
}
