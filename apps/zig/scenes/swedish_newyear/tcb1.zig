// whichpart 3 -- TCB SCREEN #1, the "A-COUPLE-OF-BORDERS-SCREEN" (screen.js
// do_tcb1). It draws straight onto the 768x536 main canvas, which here is the
// physical frame: main-ST (0,0) = physical (8,10), mycanvas sitting at (32,30).
//   white noise: 12 frames of 320x240, half the pixels #AAAAAA (fillpix: a
//     shuffled 50% mask), drawn 2x into mycanvas, which is drawn 1.2x over the
//     whole main canvas (the noise pixel is 1.2 ST pixels);
//   while intro.ogg plays (musicplease 0): black masks 60 px deep on all four
//     sides, the noise only in the screen window;
//   after it (musicplease >= 1): the noise fills the top and side borders, only
//     the bottom 60 px masked, and tcb.png wobbles on FX sinx(230, 140).
// Deviations, all ST-ward: the 1.2x draw is nearest, not smoothed; the noise
// continues past the remake's 768x536 frame to the edge of the tube (the part
// opens every border), wrapping its 320x240 pattern; Math.random is a seeded
// xorshift, the shuffle is fillpix's own.
const gen = @import("assets_gen.zig");
const assets = @import("assets.zig");
const ram = @import("ram.zig");
const image = @import("image.zig");
const fx = @import("fx.zig");

const NBA = 12;
const NX = 320;
const NY = 240;
const MAIN_X: i32 = 8; // main-ST origin in physical pixels
const MAIN_Y: i32 = 10;

/// The 12 noise frames, a bit a pixel: TCB #1's scratch in the part buffer.
pub const Noise = [NBA][NX * NY / 8]u8;

pub const Tcb1 = struct {
    n: usize,
    music_please: u8,
    logo_fx: fx.Fx(3),

    pub fn init(self: *Tcb1) void {
        self.n = 0;
        self.music_please = 0;
        self.logo_fx = .{ .p = .{
            .{ .value = 0, .amp = 1, .inc = 0.2, .offset = -0.05 },
            .{ .value = 0, .amp = 15, .inc = 0.05, .offset = 0.005 },
            .{ .value = 0, .amp = 7, .inc = 0.1, .offset = 0.08 },
        } };
    }

    /// On entering the part: the noise frames, regenerated from the same seed
    /// (they share the part buffer with the other parts' pictures).
    pub fn enter(_: *Tcb1) void {
        const noise = assets.scratch(.tcb1);
        var rng = Rng{ .s = 0x2951_988 };
        for (noise) |*n| fillpix(n, &rng);
    }

    /// One do_tcb1(); returns true on the frame the music must start.
    pub fn step(self: *Tcb1) bool {
        const cur = self.n;
        self.n = (self.n + 1) % NBA;
        var start_music = false;
        if (self.music_please == 1) {
            start_music = true;
            self.music_please = 2;
        }
        var shifts: [32]f64 = undefined;
        if (self.music_please >= 1) self.logo_fx.run(&shifts);
        // Locals, not reloads: the pixel stores go through a pointer, so the
        // compiler cannot keep anything it reads through another in a register.
        const view = View{
            .noise = &assets.scratch(.tcb1)[cur],
            .logo = assets.tcb,
            .masked = self.music_please == 0,
            .shifts = &shifts,
        };
        const px_rows = ram.buf.px;
        for (px_rows, 0..) |*row, py| {
            for (row, 0..) |*o, px| o.* = view.pixel(@intCast(px), @intCast(py));
        }
        return start_music;
    }
};

const View = struct {
    noise: *const [NX * NY / 8]u8,
    logo: image.Img,
    masked: bool, // musicplease 0: the intro's four black masks
    shifts: *const [32]f64,

    fn pixel(self: *const View, px: i32, py: i32) u16 {
        const mx = 2 * (px - MAIN_X); // main-canvas pixel
        const my = 2 * (py - MAIN_Y);
        if (self.masked) {
            if (mx < 60 or mx >= 708 or my < 60 or my >= 476) return 0;
        } else {
            if (my >= 476) return 0;
            const i = my - 140;
            if (i >= 0 and i < 32) {
                const c = image.ifloor(@as(f64, @floatFromInt(mx)) + 0.5 - (self.shifts[@intCast(i)] + 230));
                const g = self.logo.at(c, i);
                if (g != image.NONE) return g;
            }
        }
        return if (noiseAt(self.noise, mx, my)) gen.NOISE_GID else 0;
    }
};

/// mycanvas.draw(maincanvas, 0, 0, 1, 0, 1.2, 1.2) of minicanv drawn 2x.
fn noiseAt(noise: *const [NX * NY / 8]u8, mx: i32, my: i32) bool {
    const xm = image.ifloor((@as(f64, @floatFromInt(mx)) + 0.5) / 1.2);
    const ym = image.ifloor((@as(f64, @floatFromInt(my)) + 0.5) / 1.2);
    const u: usize = @intCast(@mod(@divFloor(xm, 2), NX));
    const v: usize = @intCast(@mod(@divFloor(ym, 2), NY));
    const bit = v * NX + u;
    return noise[bit >> 3] & (@as(u8, 1) << @intCast(bit & 7)) != 0;
}

/// fillpix(c1, canvas, 320, 240, 320*240/2): exactly half set, then shuffle().
/// The shuffle swaps bits in place (a byte-a-pixel mask would be 75 KB of cart RAM).
fn fillpix(out: *[NX * NY / 8]u8, rng: *Rng) void {
    @memset(out, 0);
    @memset(out[0 .. NX * NY / 16], 0xFF);
    var i: usize = NX * NY;
    while (i > 0) {
        const j: usize = @intFromFloat(@floor(rng.next() * @as(f64, @floatFromInt(i))));
        i -= 1;
        const bi = getBit(out, i);
        setBit(out, i, getBit(out, j));
        setBit(out, j, bi);
    }
}

fn getBit(bits: *const [NX * NY / 8]u8, k: usize) u1 {
    return @truncate(bits[k >> 3] >> @intCast(k & 7));
}

fn setBit(bits: *[NX * NY / 8]u8, k: usize, b: u1) void {
    const m = @as(u8, 1) << @intCast(k & 7);
    if (b == 1) bits[k >> 3] |= m else bits[k >> 3] &= ~m;
}

/// Math.random, seeded: xorshift32 / 2^32.
pub const Rng = struct {
    s: u32,
    pub fn next(self: *Rng) f64 {
        self.s ^= self.s << 13;
        self.s ^= self.s >> 17;
        self.s ^= self.s << 5;
        return @as(f64, @floatFromInt(self.s)) / 4294967296.0;
    }
};
