// --------------------------------------------------------------------------
// The short accents between the parts, all on the 030 (no DSP), all full-screen fills or
// feedback passes (prototypes/falcon_ays_re/notes_text_accents.txt):
//   807 $4A76  clear                 823 $6FE8  white          824 $70C6  white, lines 25..174
//   81A/81B $628E  a grey flash: one colour from a 64-step grey ramp, from near white down to
//              black, 8 bytes (2 steps) a 100 Hz timer tick: 0.3 s (the timer $6378)
//   809 $3172  TV static in lines 75..124: 160x25 cells of 2x2, a PRNG byte indexing a window
//              of a 768-entry grey table that slides 6 entries a tick from black to the ramps
//   825 $72A0  a feedback blur: the back buffer = the shown frame, each pixel averaged with its
//              right neighbour, (a>>1 & $7BEF) + (b>>1 & $7BEF), so the smear grows every pass
//              (one every 6 ticks, 11 in all: show.zig)
// The tables are arithmetic ramps; only the flash's (lilac-tinted) one comes from the rip.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const tc = zg.tc;
const art = @import("art.zig");

pub const W = 320;
pub const H = 200;

pub fn white(fb: tc.Fb, top: usize, bottom: usize) void {
    for (top..bottom) |y| {
        const words: [*]u32 = @ptrCast(@alignCast(fb.pixels + y * fb.stride));
        @memset(words[0 .. W / 2], 0xFFFF_FFFF);
    }
}

/// 81A/81B: the flash colour at byte index `i` ($F8 at the start, -8 a tick): the grey ramp's
/// long i/4, of 64 (entry 0 black, 63 white).
pub fn grey(i: u8) u16 {
    if (art.flash_ramp.len == 512) return art.be16(art.flash_ramp, i & 0xFC); // DATA $EBFEC (a lilac tint)
    const g: u32 = @as(u32, i >> 2) * 255 / 63;
    return tc.rgb565(@intCast(g), @intCast(g), @intCast(g));
}

pub const GreyFlash = struct {
    i: u8 = 0xF8,
    pub fn tick(self: *GreyFlash) void {
        self.i -|= 8;
    }
    pub fn draw(self: *const GreyFlash, fb: tc.Fb) void {
        fb.fill(grey(self.i));
    }
};

/// 809: the static band. `seed` follows the routine at TEXT $4 (d0 = d0*d0 ^ d0 + 7).
pub const Noise = struct {
    window: u16 = 0, // first entry of the 256-entry window into the grey table
    seed: u32 = 1,

    pub fn tick(self: *Noise) void {
        if (self.window < 0x200) self.window += 6;
    }

    pub fn draw(self: *Noise, fb: tc.Fb) void {
        fb.fill(0);
        var d0 = self.seed;
        var y: usize = 75;
        while (y < 125) : (y += 2) {
            const r0: [*]u32 = @ptrCast(@alignCast(fb.pixels + y * fb.stride));
            const r1: [*]u32 = @ptrCast(@alignCast(fb.pixels + (y + 1) * fb.stride));
            for (0..W / 2) |x| {
                d0 = ((d0 & 0xFFFF) * (d0 & 0xFFFF) ^ d0) +% 7;
                const c = noiseGrey(self.window + (d0 & 255));
                const pair = @as(u32, c) | @as(u32, c) << 16;
                r0[x] = pair;
                r1[x] = pair;
            }
        }
        self.seed = d0;
    }
};

// The 768-entry table (DATA $3892C): black to 257, two black -> white ramps (258..383,
// 384..510), white from 511.
fn noiseGrey(e: u32) u16 {
    const g: u32 = if (e < 258) 0 else if (e < 384) (e - 258) * 255 / 125 else if (e < 511) (e - 384) * 255 / 126 else 255;
    return tc.rgb565(@intCast(g), @intCast(g), @intCast(g));
}

/// 825: back = the shown frame smeared one pixel right (the right edge keeps its pixel).
pub fn smear(dst: tc.Fb, src: tc.Fb) void {
    average(dst, src, 0, H);
}

/// The Falcon's feedback pass (825 $72A0, 816 $4B10, 83E): rows y0..y1 of `dst` = `src` with
/// each pixel averaged with its right neighbour, (a>>1 & $7BEF) + (b>>1 & $7BEF); the last
/// column kept. Two pixels a word: the pair's right neighbours are the word shifted by 16.
pub fn average(dst: tc.Fb, src: tc.Fb, y0: usize, y1: usize) void {
    const m: u32 = 0x7BEF_7BEF;
    for (y0..y1) |y| {
        const s: [*]const u32 = @ptrCast(@alignCast(src.pixels + y * src.stride));
        const d: [*]u32 = @ptrCast(@alignCast(dst.pixels + y * dst.stride));
        var cur = s[0];
        for (0..W / 2 - 1) |i| {
            const next = s[i + 1];
            const right = (cur >> 16) | (next << 16);
            d[i] = ((cur >> 1) & m) + ((right >> 1) & m);
            cur = next;
        }
        const last_right = (cur >> 16) | (cur & 0xFFFF_0000);
        d[W / 2 - 1] = (((cur >> 1) & 0x7BEF) + ((last_right >> 1) & 0x7BEF)) | (cur & 0xFFFF_0000);
    }
}

test "the grey flash runs from near white to black in 31 ticks" {
    var f = GreyFlash{};
    try std.testing.expect(grey(f.i) > 0xE000);
    for (0..31) |_| f.tick();
    try std.testing.expectEqual(@as(u16, 0), grey(f.i));
}

test "the static's table: black, then two ramps, then white" {
    try std.testing.expectEqual(@as(u16, 0), noiseGrey(100));
    try std.testing.expect(noiseGrey(380) > noiseGrey(300));
    try std.testing.expectEqual(@as(u16, 0xFFFF), noiseGrey(600));
}
