// --------------------------------------------------------------------------
// The eight foreground stars (game.go's infStars).
//
// Each is [x, y, divisor, phase]: x on a 32-pixel grid across the content, y
// anywhere down it, `div` 4..8, and a phase that advances 1/div a frame and
// picks the 10-frame animation strip. At phase >= 9 the star respawns at a new
// random place and a new speed. That is the remake's whole model; the only
// thing chosen here is the generator, which is a fixed-seed xorshift so the
// headless harness can predict every frame of it (the Go seeds from the clock).
//
// All of it is 1x: the remake's round(rand*9)*64 and round(rand*354) become
// *32 and /2, and the phase stays in Q16.16 frames so 1/div is exact enough for
// a 10-frame animation.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");

pub const Star = struct {
    x: i32, // 0..288, content column
    y: i32, // 0..177, content row
    div: u8, // 4..8: frames per animation step inverted
    phase: u32, // Q16.16 animation frames, 0..9
};

pub const Field = struct {
    s: [A.STAR_COUNT]Star,
    rng: u32,

    pub fn init(self: *Field, seed: u32) void {
        self.rng = if (seed == 0) 0x1234_5678 else seed;
        for (&self.s) |*st| self.respawn(st, true);
    }

    pub fn update(self: *Field) void {
        for (&self.s) |*st| {
            st.phase +%= (@as(u32, 65536) + st.div / 2) / st.div;
            if (st.phase >= 9 << 16) self.respawn(st, false);
        }
    }

    /// game.go's respawn block. `initial` also draws the starting phase, which
    /// the Go does once per star in NewGame and never again.
    fn respawn(self: *Field, st: *Star, initial: bool) void {
        const x = self.rnd16();
        const y = self.rnd16();
        const d = self.rnd16();
        st.x = @intCast(roundMul(x, 9) * 32);
        st.y = @intCast(roundMul(y, 354) >> 1);
        st.div = @intCast(roundMul(d, 4) + 4);
        st.phase = if (initial) roundMul(self.rnd16(), 10) << 16 else 0;
    }

    fn rnd16(self: *Field) u32 {
        var x = self.rng;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.rng = x;
        return (x >> 16) & 0xFFFF;
    }

    /// Draw the animation frame and overwrite the content where the star is ink.
    /// No clipping: x <= 288 and y <= 177, so every 32x23 frame is inside
    /// 320x200 by construction.
    pub fn draw(self: *const Field, fb: *zg.LogicalFB) void {
        for (self.s) |st| {
            const tile: usize = @intCast((st.phase + 32768) >> 16);
            if (tile >= A.STAR_FRAMES) continue;
            const atlas_row = A.STAR_W * A.STAR_FRAMES;
            var r: usize = 0;
            while (r < A.STAR_H) : (r += 1) {
                const dst = (A.CONTENT_Y + @as(usize, @intCast(st.y)) + r) * fb.stride +
                    A.CONTENT_X + @as(usize, @intCast(st.x));
                const src = r * atlas_row + tile * A.STAR_W;
                var c: usize = 0;
                while (c < A.STAR_W) : (c += 1) {
                    const v = A.stars[src + c];
                    if (v != 0) fb.fb[dst + c] = v;
                }
            }
        }
    }
};

/// round(r * n / 65536) with r a 16-bit uniform value: (r*n + 32768) >> 16.
fn roundMul(r: u32, n: u32) u32 {
    return (r * n + 32768) >> 16;
}
