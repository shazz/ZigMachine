// The B.I.G. Demo, KEY 3 — the raster field, one of the three Psych-O-Screens
// the main picture advertises ("Hit 1...3 for Psych-O-Screens") and the CODEF
// remake never implemented.
//
// WHAT IT IS. A plain 320x200 low-res screen, borders closed and black, whose
// BITMAP is almost empty: 1,224 of 64,000 pixels, just the four-arrow cross in
// the middle. Everything else you see — the whole dense red/green field — is
// colour 0, rewritten 84 times a scanline. The bitmap dump settles it: pen 0
// covers 62,776 pixels.
//
// THE SCHEDULE, in display lines, measured off the real screen's own capture
// and confirmed against the code's tables word for word:
//
//   line 0, 1      black; Timer B has not fired yet
//   line 4n+2      FLAT, colour = the per-line word A1[n]
//   line 4n+3      27 bands, 12 px each, from the 41-word run R1
//   line 4n+4      FLAT, colour = the per-line word A2[n]
//   line 4n+5      27 bands from the 41-word run R2
//
// So the field lands on every OTHER line with a flat line between, which is
// why one outer iteration of the demo's loop measures 4 scanlines and covers
// 2 banded ones.
//
// THE 12-PIXEL BAND is the give-away that ties picture to code. A `move.w` to
// $FF8240 is 12 cycles, ST low res runs 1 pixel per cycle, so one write paints
// 12 pixels. 41 writes x 12 = 492 cycles, which is the 510 the profiler
// measured for one run less its loop overhead; and 320 visible pixels / 12 =
// 26.7, which is the 27 bands the capture shows. The other 14 writes land in
// the border and in blanking, where a borders-closed screen shows nothing.
//
// Every band boundary in the capture sits at x = 9 + 12k, 2562 of ~2700 of
// them, with the first change at x = 9 on all 99 banded rows without exception.
// The nine-pixel first band is the tail of the write the display opened in the
// middle of.
//
// WHICH WRITE IS FIRST VISIBLE was the one number left open, and the capture
// answers it exactly: the 27 visible bands are a CYCLIC slice of the run, 27 of
// 27 matching, starting at R1 word 37 and at R2 word 24. Cyclic because the
// run is 492 cycles against a 512-cycle line and is reloaded from a fixed
// pointer every line — so the display window straddles a run boundary and the
// same table supplies both ends of it.
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;
const D = @import("key3_data.zig");

pub const W: usize = 320;
pub const H: usize = 200;
const X0: usize = (zg.PHYSICAL_WIDTH - W) / 2; // 40
const Y0: usize = (zg.PHYSICAL_HEIGHT - H) / 2; // 40
const BLACK: u8 = 0; // this screen's own pen 0, $0000

const BAND_W: usize = 12; // one move.w to $FF8240, at 1 pixel per cycle
const FIRST_W: usize = 9; // the display opens 9 px into a band
const BANDS: usize = 27;
const R1_FIRST: usize = 37; // measured: the first visible write of run 1
const R2_FIRST: usize = 24; // and of run 2 — the runs are not in phase

/// The demo's four rings of pens, rotated together to make the arrows crawl.
/// The blue arrow has only THREE pens, not four — it is that way in the base
/// palette ($0027 $0015 $0004) and not a transcription slip.
const RINGS = [_][]const u8{ &.{ 1, 2, 3, 4 }, &.{ 5, 6, 7, 8 }, &.{ 9, 10, 11, 12 }, &.{ 13, 14, 15 } };
const RING_FRAMES: u32 = 3; // one step every three frames

pub const cross = @embedFile("../../assets/screens/big_demo/key3_cross.raw");
pub const palette = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/big_demo/key3_pal.dat"));

/// One table's scroll: it shifts up a word every `fast` frames, and after
/// `count` shifts the script moves on to the next (count, reload) pair.
const Scroll = struct {
    script: []const D.Step,
    base: usize,
    len: usize,
    step: usize = 0,
    left: u16 = 0,
    fast: u16 = 0,

    fn arm(self: *Scroll) void {
        self.step = 0;
        self.left = self.script[0].count;
        self.fast = self.script[0].reload;
    }
};

pub const Key3 = struct {
    /// The four tables, contiguous as they are in the demo's memory, and
    /// MUTABLE because the scroll engine shifts them in place.
    region: [D.REGION.len]u8,
    scroll: [4]Scroll,
    frame: u32,

    pub fn init(self: *Key3) void {
        self.region = D.REGION;
        self.frame = 0;
        self.scroll = .{
            .{ .script = &D.S_A1, .base = D.A1, .len = D.PER_LINE },
            .{ .script = &D.S_A2, .base = D.A2, .len = D.PER_LINE },
            .{ .script = &D.S_R1, .base = D.R1, .len = D.RUN },
            .{ .script = &D.S_R2, .base = D.R2, .len = D.RUN },
        };
        for (&self.scroll) |*s| s.arm();
    }

    /// Install this screen's own 84-pen palette and black the whole plane. The
    /// plane stays the menu's 400x280 overscan buffer and everything outside
    /// the 320x200 screen is painted pen 0 — which is what a closed black
    /// border looks like, without switching the plane's mode underneath it.
    pub fn enter(self: *Key3, fb: *LogicalFB) void {
        self.init();
        fb.setPalette(palette);
        fb.clearFrameBuffer(BLACK);
    }

    pub fn draw(self: *Key3, fb: *LogicalFB) void {
        for (RINGS) |ring| {
            const p = (self.frame / RING_FRAMES) % ring.len;
            for (ring, 0..) |pen, i| fb.setPaletteEntry(pen, palette[ring[(i + p) % ring.len]]);
        }
        var y: usize = 0;
        while (y < H) : (y += 1) {
            const dst = fb.fb[(Y0 + y) * zg.PHYSICAL_WIDTH + X0 ..][0..W];
            if (y < 2) {
                @memset(dst, BLACK);
            } else switch ((y - 2) % 4) {
                0 => @memset(dst, self.region[D.A1 + (y - 2) / 4]),
                2 => @memset(dst, self.region[D.A2 + (y - 2) / 4]),
                1 => self.bands(dst, D.R1, R1_FIRST),
                else => self.bands(dst, D.R2, R2_FIRST),
            }
            for (cross[y * W ..][0..W], dst) |c, *d| {
                if (c != 0) d.* = c;
            }
        }
        self.tick();
    }

    fn bands(self: *const Key3, dst: []u8, base: usize, first: usize) void {
        var x: usize = 0;
        for (0..BANDS) |i| {
            const pen = self.region[base + (first + i) % D.RUN];
            const w = if (i == 0) FIRST_W else @min(BAND_W, W - x);
            @memset(dst[x..][0..w], pen);
            x += w;
        }
    }

    fn tick(self: *Key3) void {
        self.frame +%= 1;
        for (&self.scroll) |*s| {
            if (s.fast > 1) {
                s.fast -= 1;
                continue;
            }
            // A 61-word ROTATION, which is exactly what the demo does. Its
            // own code saves word 0 (`move.w (a0),d0` at $1B3E8), shifts words
            // 1..60 down with three 20-word movem blocks, and then writes the
            // saved word back into word 60 (`move.w d0,$78(a0)` at $1B40C).
            // The first reading of it stopped two instructions short of that
            // last move and looked like a drain, which would have emptied the
            // table in 60 steps — four seconds at the script's own reload of 1.
            // Distrusting a mechanism that cannot run is what found it.
            const t = self.region[s.base .. s.base + s.len];
            const head = t[0];
            for (0..t.len - 1) |i| t[i] = t[i + 1];
            t[t.len - 1] = head;
            s.left -= 1;
            if (s.left == 0) {
                s.step = (s.step + 1) % s.script.len;
                s.left = s.script[s.step].count;
            }
            s.fast = s.script[s.step].reload;
        }
    }
};

comptime {
    if (FIRST_W + (BANDS - 1) * BAND_W < W) @compileError("27 bands do not reach the right edge");
    if (cross.len != W * H) @compileError("key3_cross.raw is not 320x200");
    if (D.REGION.len != 2 * D.PER_LINE + 2 * D.RUN) @compileError("the region is not the four tables");
}
