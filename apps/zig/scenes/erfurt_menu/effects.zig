// --------------------------------------------------------------------------
// The menu's smaller effects, each the original's own data:
//
// FLOOR ($11F66): 31 lines from line 167, plane 0. Line i owns 16, 32 or 64
// ready-made 320-px chequer rows (the generated block at $4EDCE); it shows
// row ((pan >> shift) + (depth phase crossing $100 ? half : 0)) & mask, the
// pan and the forward motion each driven by the sine table.
// SHADOW ($1221A): 12 dithered rows in plane 1 under the drum, x 64..255,
// thinner the higher the drum hops (8 sizes, $14130).
// GLINT ($126E8): every 322 frames, 66 frames of XOR deltas over the logo,
// code generated as `eori #imm,d16(a1)` lists ($14A40) and ripped as data.
// Each of the ST's two screens takes every other step, as here.
// SPARKLE ($12350): every 450 still frames, an 8-line band sweeps down the
// drum for 64 frames smearing its text 1-2 px to the right ($12436).
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const S = @import("screen.zig");

pub const FLOOR_TOP = 167; // $4EBC8
const FLOOR_LINES = 31; // $4EBCA
const SHADOW_TOP = FLOOR_TOP + 6;

pub const Floor = struct {
    depth: u16, // $4EBD0
    ph_a: u16, // $4EBD4
    ph_b: u16, // $4EBD6

    pub fn init(self: *Floor) void {
        self.* = .{ .depth = 0, .ph_a = 0, .ph_b = 0 };
    }

    pub fn draw(self: *Floor, st: *S.Screen) void {
        self.ph_a +%= 0x120;
        self.ph_b +%= 0xC0;
        self.depth +%= @bitCast(A.sin(self.ph_a) >> 7);
        const across: i16 = A.sin(self.ph_a +% 0x4000) >> 4;
        const s = A.sin(self.ph_b);
        const pan: u16 = @bitCast(((s *% 5) >> 4) +% across);
        for (0..FLOOR_LINES) |i| {
            const shift: u4, const half: u16, const mask: u16, const base: usize = if (i < 8)
                .{ 5, 8, 15, i * 0x280 }
            else if (i < 19)
                .{ 4, 16, 31, 8 * 0x280 + (i - 8) * 0x500 }
            else
                .{ 3, 32, 63, 8 * 0x280 + 11 * 0x500 + (i - 19) * 0xA00 };
            var k = pan >> shift;
            if ((A.be(A.floor_z, i) +% self.depth) & 0x100 != 0) k +%= half;
            k &= mask;
            const src = base + @as(usize, k) * 40;
            const row = &st.rows[FLOOR_TOP + i];
            for (0..20) |g| row[4 * g] = A.be(A.floor, src / 2 + g);
        }
    }
};

/// $1221A: the shadow's size from how high the drum is off the floor.
pub fn shadow(st: *S.Screen, hop_h: i16) void {
    const lifted: u16 = @as(u16, @bitCast(hop_h)) >> 9;
    const v: usize = @min(lifted, 7);
    for (0..12) |r| {
        const row = &st.rows[SHADOW_TOP + r];
        for (0..12) |j| row[4 * (4 + j) + 1] = A.be(A.shadow, v * 0x90 + r * 12 + j);
    }
}

pub const Glint = struct {
    clock: u16, // $62544

    pub fn init(self: *Glint) void {
        self.clock = 0;
    }

    /// One frame: the step (if any) XORed into this frame's copy of the logo.
    pub fn step(self: *Glint, logo: *[S.LOGO_ROWS][S.WORDS]u16) void {
        const t = self.clock;
        self.clock = (self.clock + 1) % 0x142;
        if (t < 0x20 or t - 0x20 >= A.GLINT_STEPS) return;
        const o = A.glint_start[t - 0x20];
        const n = A.be(A.glint, o);
        for (0..n) |k| {
            const at = A.be(A.glint, o + 1 + 2 * k) / 2; // byte offset -> word
            const x = A.be(A.glint, o + 2 + 2 * k);
            logo[at / S.WORDS][at % S.WORDS] ^= x;
        }
    }
};

pub const Sparkle = struct {
    wait: u16, // $620BC
    t: u16, // $620BE: 0 = idle, else the sweep's frame + 1
    band: ?i32, // the first line smeared last frame, to put back

    pub fn init(self: *Sparkle) void {
        self.* = .{ .wait = 0x96, .t = 0, .band = null };
    }

    /// $12350: `busy` is the drum moving ($12C68); top/bottom its drawn lines.
    pub fn draw(self: *Sparkle, st: *S.Screen, busy: bool, top: i32, bottom: i32) void {
        if (self.band) |b| restore(st, b);
        self.band = null;
        var frame: u16 = undefined;
        if (self.t == 0) {
            self.wait -%= 1;
            if (self.wait != 0) return;
            if (busy) {
                self.wait = 0x20;
                return;
            }
            self.t = 1;
            frame = 1;
        } else {
            if (busy) {
                self.t = 0;
                self.wait = 0x20;
                return;
            }
            frame = self.t;
        }
        self.t += 1;
        if (self.t > 0x40) {
            self.t = 0;
            self.wait = 0x1C2;
        }
        const lo = @max(top, 45);
        const hi = @min(bottom, 166);
        if (hi < lo) return;
        var y: i32 = @intCast(((166 - 0x1C) * @as(u32, frame - 1)) >> 6);
        y += 0x25;
        self.band = y;
        for (0..8) |b| {
            const kind = A.be(A.sparkle, b);
            if (kind != 0 and y >= lo and y <= hi) smear(&st.rows[@intCast(y)], kind);
            y += 1;
        }
    }
};

/// The original saves the words it smears and puts them back the next frame.
/// Here drum.draw rewrites groups 4..15 of every drum line each frame, and
/// groups 2..3 only ever receive their own (empty) words; what is left is the
/// spill out of group 15 into 16..18 (x 256..303), which nothing else draws in
/// planes 0+1 on lines 45..166, so putting it back is clearing it.
fn restore(st: *S.Screen, first: i32) void {
    var y = @max(first, 45);
    while (y <= @min(first + 7, 166)) : (y += 1) {
        const row = &st.rows[@intCast(y)];
        for (16..19) |g| {
            row[4 * g] = 0;
            row[4 * g + 1] = 0;
        }
    }
}

/// $12436: planes 0+1 of 17 groups from x 32, as one long each, shifted right
/// by `kind` pixels and ORed back over themselves (the text blooms).
fn smear(row: *[S.WORDS]u16, kind: u16) void {
    const k: u5 = @intCast(kind);
    const keep: u32 = if (kind == 1) 0x7FFF_7FFF else 0x3FFF_3FFF;
    var carry: u32 = 0;
    for (2..19) |g| {
        const v = (@as(u32, row[4 * g]) << 16) | row[4 * g + 1];
        if (v == 0) {
            row[4 * g] = @truncate(carry >> 16);
            row[4 * g + 1] = @truncate(carry);
            carry = 0;
            continue;
        }
        const r = (v >> k) | (v << @intCast(32 - @as(u6, k)));
        const out = (r & keep) | carry | v;
        row[4 * g] = @truncate(out >> 16);
        row[4 * g + 1] = @truncate(out);
        const spill = r & ~keep;
        carry = (spill >> 16) | (spill << 16);
    }
}
