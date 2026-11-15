// Key 4, GFA PUNCH (ST MAGAZINE): the listing as the ST ran it (gfa.zig has the maths).
// An 8-bit plane holding a 16-colour ST low-res screen: the palette of line 3 (XBIOS 6),
// the title PRINTed in the 8x8 system font at the top left in colour 15 (TOS's text
// colour), PTST reading the floor's texture back from those very pixels, and the two FOR
// loops run in their order (y% from -99, the bottom row, up to 53; x% left to right), a
// budget of iterations a frame, so the picture builds up line by line as it did on the ST.
//
// The plane's rows 16..39 (never drawn by the listing, outside PTST's rows 0..15) carry
// the HUD (gfa_hud.zig), row 199 (never drawn either) its tap strip.
const zg = @import("zigos");
const gfa = @import("gfa.zig");

pub const ITERATIONS: u32 = 319 * 153; // lines 5-6's loops
const Y0: i32 = -99;
const Y1: i32 = 53;
const X0: i32 = -159;
const X1: i32 = 159;

/// The screen as PTST sees it: a pixel not colour 0.
const Screen = struct {
    lfb: *zg.LogicalFB,
    pub fn ptst(self: Screen, x: u32, y: u32) bool {
        return self.lfb.fb[y * self.lfb.stride + x] != 0;
    }
};

pub const St = struct {
    lfb: *zg.LogicalFB,
    x: i32,
    y: i32,
    done: u32, // loop iterations so far
    rnd: gfa.Rand,

    /// Lines 1-4: palette, a cleared screen, the title; the loops from the start.
    pub fn start(self: *St, zigos: *zg.ZigOS, lfb: *zg.LogicalFB) void {
        self.lfb = lfb;
        self.x = X0;
        self.y = Y0;
        self.done = 0;
        self.rnd = .{ .s = gfa.SEED };
        for (gfa.PALETTE, 0..) |w, i| {
            const c = gfa.stRgb(w);
            lfb.palette[i] = (zg.Color{ .r = c[0], .g = c[1], .b = c[2], .a = 255 }).toRGBA();
        }
        lfb.clearFrameBuffer(0);
        zigos.printText(lfb, gfa.TITLE, 0, 0, 15, 0);
    }

    pub fn finished(self: *const St) bool {
        return self.done >= ITERATIONS;
    }

    /// The row the loops are on (1..153), for the HUD.
    pub fn line(self: *const St) u32 {
        return if (self.finished()) 153 else @intCast(self.y - Y0 + 1);
    }

    /// Runs up to `n` iterations of the loops (lines 5-17).
    pub fn step(self: *St, n: u32) void {
        var k: u32 = 0;
        while (k < n and !self.finished()) : (k += 1) {
            self.pixel(self.x, self.y);
            self.done += 1;
            self.x += 1;
            if (self.x <= X1) continue;
            self.x = X0;
            self.y += 1;
        }
    }

    /// Lines 7-15 for one (x%, y%).
    fn pixel(self: *St, x: i32, y: i32) void {
        const xf: f32 = @floatFromInt(x);
        const yf: f32 = @floatFromInt(y);
        const v = if (gfa.sphereZ(x, y)) |z|
            gfa.sphereV(xf, yf, z)
        else if (y < 0)
            gfa.floorV(xf, yf, Screen{ .lfb = self.lfb })
        else if (y > 0 and y <= 24)
            gfa.skyV(yf)
        else
            return; // y% = 0 and above 24: the screen stays as it was
        const sx: u32 = @intCast(x + 159);
        const sy: u32 = @intCast(99 - y);
        self.lfb.fb[sy * self.lfb.stride + sx] = gfa.fnC(v, &self.rnd);
    }
};

comptime {
    if ((X1 - X0 + 1) * (Y1 - Y0 + 1) != ITERATIONS) @compileError("loop bounds");
}
