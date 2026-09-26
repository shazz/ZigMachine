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
const frame = @import("frame.zig");
const gen = @import("assets_gen.zig");
const image = @import("image.zig");
const fx = @import("fx.zig");

const NBA = 12;
const NX = 320;
const NY = 240;
const MAIN_X: i32 = 8; // main-ST origin in physical pixels
const MAIN_Y: i32 = 10;

var noise: [NBA][NX * NY / 8]u8 = undefined;
var mask: [NX * NY]u8 = undefined;

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
        var rng = Rng{ .s = 0x2951_988 };
        for (0..NBA) |u| fillpix(&noise[u], &rng);
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
        for (0..frame.PH) |py| {
            const row = &frame.px[py];
            for (0..frame.PW) |px| row[px] = self.pixel(cur, @intCast(px), @intCast(py), &shifts);
        }
        return start_music;
    }

    fn pixel(self: *const Tcb1, cur: usize, px: i32, py: i32, shifts: *const [32]f64) u16 {
        const mx = 2 * (px - MAIN_X); // main-canvas pixel
        const my = 2 * (py - MAIN_Y);
        if (self.music_please == 0) {
            if (mx < 60 or mx >= 708 or my < 60 or my >= 476) return 0;
        } else {
            if (my >= 476) return 0;
            const i = my - 140;
            if (i >= 0 and i < 32) {
                const c = image.ifloor(@as(f64, @floatFromInt(mx)) + 0.5 - (shifts[@intCast(i)] + 230));
                const g = gen.tcb.at(c, i);
                if (g != image.NONE) return g;
            }
        }
        return if (noiseAt(cur, mx, my)) gen.NOISE_GID else 0;
    }
};

/// mycanvas.draw(maincanvas, 0, 0, 1, 0, 1.2, 1.2) of minicanv drawn 2x.
fn noiseAt(cur: usize, mx: i32, my: i32) bool {
    const xm = image.ifloor((@as(f64, @floatFromInt(mx)) + 0.5) / 1.2);
    const ym = image.ifloor((@as(f64, @floatFromInt(my)) + 0.5) / 1.2);
    const u: usize = @intCast(@mod(@divFloor(xm, 2), NX));
    const v: usize = @intCast(@mod(@divFloor(ym, 2), NY));
    const bit = v * NX + u;
    return noise[cur][bit >> 3] & (@as(u8, 1) << @intCast(bit & 7)) != 0;
}

/// fillpix(c1, canvas, 320, 240, 320*240/2): exactly half set, then shuffle().
fn fillpix(out: *[NX * NY / 8]u8, rng: *Rng) void {
    @memset(&mask, 0);
    @memset(mask[0 .. NX * NY / 2], 1);
    var i: usize = mask.len;
    while (i > 0) {
        const j: usize = @intFromFloat(@floor(rng.next() * @as(f64, @floatFromInt(i))));
        i -= 1;
        const t = mask[i];
        mask[i] = mask[j];
        mask[j] = t;
    }
    @memset(out, 0);
    for (mask, 0..) |b, k| out[k >> 3] |= b << @intCast(k & 7);
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
