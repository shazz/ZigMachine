// --------------------------------------------------------------------------
// What the demo layers over every part:
//   fader $318C (Timer A tail, each frame): the field palette ($5A4) steps one
//         3-bit level per channel towards a target every speed+1 frames,
//         8 steps; $3236 starts it
//   bars  $38A6: the two chrome bars, lines 0..13 and 207..194 (mirrored),
//         blank lines whose colour 0 is a 14-word window sliding over the
//         gradient at $38D6 (in: 0 -> 16, out: 16 -> 0): a REAL raster
//   vhs   $16A48 (VBL, the reversed half): one field line in 32 made blank
//         with colour 0 = $FFF, rolling 12 bytes (1.5 lines) a frame
// --------------------------------------------------------------------------
const data = @import("data.zig");
const lines = @import("lines.zig");
const vram = @import("vram.zig");

pub var pal: [16]u16 = [_]u16{0} ** 16;
var target: [16]u16 = [_]u16{0} ** 16;
var active: bool = false;
var reload: i8 = 0;
var counter: i8 = 0;
var steps: u16 = 8;

pub fn fadeTo(t: [16]u16, speed: i8) void {
    target = t;
    active = true;
    counter = speed;
    reload = speed;
}

fn toward(c: u16, t: u16, mask: u16, one: u16) u16 {
    if (c & mask == t & mask) return c;
    return if (c & mask > t & mask) c -% one else c +% one;
}

pub fn fadeTick() void {
    if (!active) return;
    counter -%= 1;
    if (counter >= 0) return;
    counter = reload;
    steps -= 1;
    if (steps == 0) {
        active = false;
        steps = 8;
    }
    for (&pal, target) |*c, t| {
        c.* = toward(c.*, t, 0x700, 0x100);
        c.* = toward(c.*, t, 0x070, 0x010);
        c.* = toward(c.*, t, 0x007, 0x001);
    }
}

pub const BAR_STEPS: usize = 17;

pub fn bars(step: usize) void {
    for (0..14) |k| {
        const c = data.be16(data.bars, step + k);
        lines.table[k] = .{ .src = vram.blank, .colour = c };
        lines.table[207 - k] = .{ .src = vram.blank, .colour = c };
    }
}

pub var vhs_on: bool = false; // $16A9A
var vhs_pos: u16 = 0; // the high word of $16A96

pub fn vhs() void {
    if (!vhs_on) return;
    var d0 = vhs_pos;
    for (0..8) |_| {
        const off = d0 & 0x7f8;
        if (off < 0x5a0) lines.table[14 + off / 8] = .{ .src = vram.blank, .colour = 0x0fff };
        d0 = off +% 0x100;
    }
    vhs_pos -%= 12;
}
