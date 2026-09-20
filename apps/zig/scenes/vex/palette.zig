// --------------------------------------------------------------------------
// VEX's colours.  The intro is an STE screen: $ab86/$196 mask $f00/$f0/$f and
// step each channel through the tables at $2ba/$2ca, so every colour word is a
// 4-bit-per-channel STE value, not the ST's 3.
//
// Two mechanisms, both the original's:
//  * a 21-word crossfade ($ab86, called every VBL with d7 = $14) that walks the
//    live palette one level per channel toward a target, every 3 frames.  The
//    21 words are the 16 screen colours plus the five raster colours the Timer-B
//    chain writes ($3130e, $31310, $31312, $31314, $31316).
//  * the Timer-B chain itself ($e90a/$e97a), 71 splits of two scanlines each
//    covering rows 47..188, writing colours 4-7 from the ramp at $30df8 and
//    colours 8-15 from the per-split table at $31198.
// --------------------------------------------------------------------------
const A = @import("assets.zig");

/// $2ba: STE hardware nibble -> linear 0..15.  $2ca is its inverse.
const HW2LIN = [16]u8{ 0, 2, 4, 6, 8, 10, 12, 14, 1, 3, 5, 7, 9, 11, 13, 15 };
const LIN2HW = [16]u4{ 0, 8, 1, 9, 2, 10, 3, 11, 4, 12, 5, 13, 6, 14, 7, 15 };

pub const WORDS: usize = 21;
/// Indices into the 21-word palette block, named for the $FF8240 writes they feed.
pub const BODY_BG: usize = 16; // $3130e
pub const TOP_BG: usize = 17; // $31310
pub const SPLIT_BG: usize = 19; // $31314
pub const SMALL_INK: usize = 20; // $31316

fn lin(hw: u16, shift: u4) u8 {
    return HW2LIN[(hw >> shift) & 0xf];
}

/// An STE $0RGB word as the machine's RGBA.  4 bits scale to 8 by *17.
pub fn rgba(hw: u16) u32 {
    const r: u32 = @as(u32, lin(hw, 8)) * 17;
    const g: u32 = @as(u32, lin(hw, 4)) * 17;
    const b: u32 = @as(u32, lin(hw, 0)) * 17;
    return (0xff << 24) | (b << 16) | (g << 8) | r;
}

/// One channel of $ab86: compare in linear space, step by one, re-encode.
fn stepChannel(cur: u16, tgt: u16, shift: u4) u16 {
    const c = HW2LIN[(cur >> shift) & 0xf];
    const t = HW2LIN[(tgt >> shift) & 0xf];
    const n: u8 = if (t == c) c else if (t > c) c + 1 else c - 1;
    return @as(u16, LIN2HW[n]) << shift;
}

pub fn stepColour(cur: u16, tgt: u16) u16 {
    return stepChannel(cur, tgt, 8) | stepChannel(cur, tgt, 4) | stepChannel(cur, tgt, 0);
}

/// The live 21-word palette and its crossfade.  $e8/$ea in TEXT are both 3, so
/// one level every three frames.
pub const Fade = struct {
    live: [WORDS]u16,
    target: [WORDS]u16,
    delay: u16,

    pub fn init(self: *Fade) void {
        // $312ee ships as 21 words of $777; $c1c overwrites the target's first
        // 16 with the logo palette at $31344.
        self.live = [_]u16{0x777} ** WORDS;
        for (&self.target, 0..) |*t, i| t.* = A.be(A.pal_target_b, i);
        self.delay = 3;
    }

    pub fn step(self: *Fade) void {
        self.delay -= 1;
        if (self.delay > 0) return;
        self.delay = 3;
        for (&self.live, 0..) |*c, i| c.* = stepColour(c.*, self.target[i]);
    }
};

/// $e81e: the ramp read pointer walks $30fc8 for a speed, adds it to a phase,
/// and the phase indexes the 232-word colour ramp the splits then step through.
pub const Ramp = struct {
    phase: u16,
    speed_idx: usize,

    pub fn init(self: *Ramp) void {
        self.phase = 0;
        self.speed_idx = 0;
    }

    pub fn advance(self: *Ramp) void {
        self.phase = (self.phase +% A.be(A.speed_b, self.speed_idx)) & 0xff;
        self.speed_idx = (self.speed_idx + 1) & (A.SPEED_LEN - 1);
    }

    /// Split `s`'s ramp colour.  $e90a checks the pointer against $30fc8 before
    /// every read, so a phase past the table's end restarts it at entry 0.
    pub fn colour(self: *const Ramp, s: usize) u16 {
        var i: usize = if (self.phase >= A.RAMP_LEN) 0 else self.phase;
        i += s;
        if (i >= A.RAMP_LEN) i -= A.RAMP_LEN;
        return A.be(A.ramp_b, i);
    }
};
