// --------------------------------------------------------------------------
// Depack effects: what the screen does while a packed asset unpacks.
//
// The effect is chosen at PACK time and stored in the container's fx byte
// (zx0.zig), so the cart just calls `Runner.start` and then `frame` once per
// frame until it answers .done. Every effect is driven by the depack itself,
// never by a clock: it ends exactly when the data is ready.
//
//   rasters  colour 0 (background + border) flickers with the data, per scanline
//   bar      a loading bar fills with written / total
//   text     the container's message, printed while it works
//   fade     the background steps white -> black in ST 3-bit levels as it goes
//   noise    TV snow on plane 0 (libs/zig/tvnoise/tvnoise.zig), until the data is ready
//   automation  the Automation Packer v2.3r depack screen: random colour bars under
//            the Automation logo and the busy bee, redrawn every frame
//
// AUTOMATION is CODEF's AtariDecrunch(0, 100, 0, 200) (prototypes/codef/168/
// lib/codef_decrunch.js), the fake depack screen that opens the Replicants'
// Kick Off 2 remake (and Elite Snooker, CODEF 422), moved here from
// replicants_kickoff2.zig so it runs while real data depacks. The one parameter
// that changes the look, MaxBarHeight (168: 100, 422: 30), is stored in the
// container header (zx0.Header.bars); DecrunchMaxVBL is replaced by the depack
// itself. Kept exactly: each frame picks tallest = 10 + round(rnd*MaxBarHeight),
// then bars of round(rnd*tallest) canvas rows in palette[round(rnd*12)] down a
// canvas twice the plane's height, one plane row per two canvas rows. round()
// can give 12, which the palette lacks: the canvas keeps its last fillStyle, so
// the bar takes the previous colour. The 12 colours, the logo at canvas
// (320 - w/2, 7) and the bee at (320, 50), both halved and inked black, are the
// scene's own assets (automation/*.raw, from the base64 PNGs in codef_decrunch.js).
// Adapted: the remake ran for a fixed 200 frames on a 320x240 canvas; here it
// runs until the data is ready and covers the whole plane (320x200, or 400x280
// with the logo placed from the 320x200 window at (40,40)). Math.random is
// xorshift64*, as in the scene, and the plane's palette entries 1 and 3..14 hold
// the ink and bar colours while it runs.
//
// `Runner` is generic over the ZigOS namespace and, optionally, the tvnoise
// module: `Runner(@import("zigos"), null)` or
// `Runner(@import("zigos"), @import("tvnoise"))`. That keeps this module free of
// either dependency. Without tvnoise, an image packed with NOISE is refused at
// `start`, before anything is touched, rather than depacked without its effect.
// The runner records the background
// colour, the global HBL handler, every plane's enable flag and plane 0's
// palette entries 0..15, and puts them all back when the depack ends.
//
// NOISE draws one frame of tvnoise snow per frame. tvnoise.fill takes no
// time or progress input, so the snow does not change with progress; the effect
// just runs for exactly as long as the depack does.
//
// RASTERS is the one effect that works inside the beam. A global HBL handler
// (physical lines 0..279, borders included) depacks a budget of bytes on every
// scanline and loads colour 0 from the data, so each stripe IS a stretch of
// depacking. What it writes follows Jampack 4.0's own depackers (MajicSoft MAGE
// extras, ~/projects/Atari_ST_Sources/GFA Basic/MajicSoft/MAGE/EXTRAS/JAMPACK4/):
//   DEPICE.S:55  MOVE.W D7,$FFFF8240  on every bit-buffer reload, with the packed
//                byte just fetched: the rasters here load colour 0 from the
//                ZX0 bit reader's byte the same way.
//   DEPV2.S:17   ROL.W D7 then MOVE.W D7,$FFFF8240 on every step (not used)
//   DEPLZH.S:187 #$222 then #$000 each step: once-per-line sampling always
//                reads black (not used)
// Unverified, stated plainly: DEPICE.S loads that byte with MOVE.B, so D7's
// upper byte (the red nibble) is whatever earlier code left there. It is taken
// as 0, which gives green/blue stripes. The machine also samples colour 0 once
// per scanline, where a real ST shows mid-line writes too. And ZX0 reloads its
// bit buffer at a different rate from Pack-Ice, so the stripe density is ZX0's.
// --------------------------------------------------------------------------
const std = @import("std");
const zx0 = @import("zx0.zig");

pub const Rgb = struct { r: u8, g: u8, b: u8 };

/// An ST (not STE) palette word $0RGB to 8 bits a gun: three bits each, and
/// the hardware ignores bit 3 of every nibble.
pub fn stColour(word: u16) Rgb {
    return .{ .r = gun(word >> 8), .g = gun(word >> 4), .b = gun(word) };
}

fn gun(nibble: u16) u8 {
    const v: u8 = @intCast(nibble & 7);
    return (v << 5) | (v << 2) | (v >> 1);
}

/// FADE: white ($777) at 0 bytes down to black ($000), in the eight 3-bit levels
/// an ST palette has. Level 0 is reached only when the last byte is written, so
/// the fade ends exactly when the depack does.
pub fn fadeWord(written: u32, total: u32) u16 {
    if (total == 0 or written >= total) return 0;
    const step: u16 = @intCast(@as(u64, written) * 7 / total);
    return (7 - step) * 0x111;
}

/// BAR: filled pixels out of `width`.
pub fn barFill(written: u32, total: u32, width: u16) u16 {
    if (total == 0) return width;
    return @intCast(@as(u64, written) * width / total);
}

/// RASTERS: the ST colour word loaded after a scanline's worth of depacking.
pub fn rasterWord(stream: *const zx0.Stream) u16 {
    return stream.lastBitByte();
}

const BAR_X = 40;
const BAR_W = 240;
const BAR_Y = 96;
const BAR_H = 8;
const TEXT_Y = 96;
const GLYPH_W = 8;
/// NOISE puts tvnoise's grey ramp at plane-0 entries 8..15, clear of bar/text's 0..2.
const NOISE_FIRST = 8;
const SAVED_ENTRIES = 16;

// --- AUTOMATION (AtariDecrunch) -----------------------------------------------
/// AtariDecrunch's this.palette for DType AtariAutomation, in order.
pub const AUTOMATION_COLOURS = [12]Rgb{
    .{ .r = 0xa0, .g = 0xb0, .b = 0x00 }, .{ .r = 0xa0, .g = 0xa0, .b = 0x00 }, .{ .r = 0xa0, .g = 0x20, .b = 0x10 },
    .{ .r = 0xa0, .g = 0x20, .b = 0x90 }, .{ .r = 0xa0, .g = 0xc0, .b = 0x30 }, .{ .r = 0xa0, .g = 0xd0, .b = 0xa0 },
    .{ .r = 0xa0, .g = 0x40, .b = 0x00 }, .{ .r = 0xa0, .g = 0x80, .b = 0xa0 }, .{ .r = 0xa0, .g = 0x80, .b = 0x00 },
    .{ .r = 0xa0, .g = 0x00, .b = 0xf0 }, .{ .r = 0xa0, .g = 0xd0, .b = 0x60 }, .{ .r = 0xa0, .g = 0xa0, .b = 0xa0 },
};
/// Plane-0 entries: the black ink (and the canvas's initial fillStyle), then the bars.
pub const AUTOMATION_INK = 1;
pub const AUTOMATION_FIRST = 3;
const AUTOMATION_SEED: u64 = 0x9E3779B97F4A7C15;
const LOGO_W = 182;
const LOGO_H = 8;
const LOGO_Y = 7 / 2; // drawImage(automation, 320 - w1/2, 7), halved
const BEE_W = 16;
const BEE_X = 320 / 2; // drawImage(bee, 320, 50), halved
const BEE_Y = 50 / 2;

/// A 1-byte-per-pixel 0/1 mask packed to bits at compile time (a cart pays
/// 214 bytes for both images, not 1.7 KB).
fn Mask(comptime w: usize, comptime h: usize) type {
    return struct {
        bits: [(w * h + 7) / 8]u8,
        pub const W = w;
        pub const H = h;
        fn init(comptime raw: []const u8) @This() {
            if (raw.len != w * h) @compileError("mask size does not match its dimensions");
            @setEvalBranchQuota(4 * w * h + 1000);
            var m: @This() = .{ .bits = [_]u8{0} ** ((w * h + 7) / 8) };
            for (raw, 0..) |p, i| switch (p) {
                0 => {},
                1 => m.bits[i / 8] |= @as(u8, 1) << @intCast(i % 8),
                else => @compileError("mask pixel is not 0 or 1"),
            };
            return m;
        }
        pub fn ink(self: *const @This(), x: usize, y: usize) bool {
            const i = y * w + x;
            return self.bits[i / 8] >> @intCast(i % 8) & 1 == 1;
        }
    };
}

pub const automation_logo = Mask(LOGO_W, LOGO_H).init(@embedFile("automation/automation.raw"));
pub const automation_bee = Mask(BEE_W, BEE_W).init(@embedFile("automation/bee.raw"));

/// The AUTOMATION effect's state: Math.random and the canvas's fillStyle, which
/// persists from one frame (and one bar) to the next.
pub const Automation = struct {
    /// MaxBarHeight, from the container header (zx0.Header.bars).
    bar_max: u8,
    rng: u64 = AUTOMATION_SEED,
    fill: u8 = AUTOMATION_INK,

    /// Math.random stand-in: xorshift64*, 53 bits into [0, 1).
    pub fn random(self: *Automation) f64 {
        self.rng ^= self.rng >> 12;
        self.rng ^= self.rng << 25;
        self.rng ^= self.rng >> 27;
        const bits = (self.rng *% 0x2545F4914F6CDD1D) >> 11;
        return @as(f64, @floatFromInt(bits)) * 0x1.0p-53;
    }

    /// One doDecrunch bar pass: `rows` holds a plane entry per row; plane row k
    /// shows canvas row 2k of a canvas 2 * rows.len tall.
    pub fn bars(self: *Automation, rows: []u8) void {
        const canvas_h = 2 * rows.len;
        const tallest = 10 + jsRound(self.random() * @as(f64, @floatFromInt(self.bar_max)));
        var y: usize = 0;
        while (y <= canvas_h) {
            const barh: usize = @intFromFloat(jsRound(self.random() * tallest));
            const col = jsRound(self.random() * AUTOMATION_COLOURS.len);
            if (col < AUTOMATION_COLOURS.len) self.fill = AUTOMATION_FIRST + @as(u8, @intFromFloat(col));
            // plane rows k with y <= 2k < y + barh
            const first = (y + 1) / 2;
            const end = @min((y + barh + 1) / 2, rows.len);
            if (end > first) @memset(rows[first..end], self.fill);
            y += barh;
        }
    }
};

/// JS Math.round for the non-negative values it sees here.
fn jsRound(x: f64) f64 {
    return @floor(x + 0.5);
}

pub fn Runner(comptime zg: type, comptime tvnoise: ?type) type {
    return struct {
        const Self = @This();
        const ZigOS = zg.ZigOS;
        const Color = zg.Color;
        const Hbl = @TypeOf(@as(ZigOS, undefined).hbl_handler);

        /// The runner the HBL handler serves: a handler takes no context.
        var active: ?*Self = null;

        stream: zx0.Stream,
        fx: zx0.Fx,
        text: []const u8,
        bytes_per_line: u32,
        saved_bg: Color,
        saved_hbl: Hbl,
        saved_enabled: [4]bool,
        saved_pal: [SAVED_ENTRIES]Color,
        noise: if (tvnoise) |t| t.Noise else void,
        automation: Automation,

        /// Begin depacking `image` into `dst`, `bytes_per_line` bytes per physical
        /// scanline (x280 a frame). False when the image is unreadable or does not fit.
        pub fn start(self: *Self, zigos: *ZigOS, image: []const u8, dst: []u8, bytes_per_line: u32) bool {
            const h = zx0.parseHeader(image) orelse return false;
            if (h.fx == .noise and tvnoise == null) return false;
            const stream = zx0.Stream.init(image, dst) orelse return false;
            const p0 = &zigos.lfbs[0];
            self.* = .{
                .stream = stream,
                .fx = h.fx,
                .text = h.text,
                .bytes_per_line = @max(1, bytes_per_line),
                .saved_bg = zigos.getBackgroundColor(),
                .saved_hbl = zigos.hbl_handler,
                .saved_enabled = undefined,
                .saved_pal = undefined,
                .noise = if (tvnoise) |t| t.Noise.init(0x5EED) else {},
                .automation = .{ .bar_max = h.bars },
            };
            for (&self.saved_pal, 0..) |*c, i| c.* = p0.getPaletteEntry(@intCast(i));
            for (&zigos.lfbs, 0..) |*fb, i| {
                self.saved_enabled[i] = fb.is_enabled;
                fb.is_enabled = false;
            }
            switch (self.fx) {
                .none, .fade => {},
                .rasters => {
                    active = self;
                    zigos.setHBLHandler(hbl);
                },
                .bar, .text, .noise, .automation => self.openPlane(zigos),
            }
            if (self.fx != .rasters) zigos.setBackgroundColor(rgba(0));
            if (self.fx == .text) printCentered(zigos, self.text);
            if (self.fx == .bar) fillBar(p0, BAR_W, 1);
            if (self.fx == .automation) {
                p0.setPaletteEntry(AUTOMATION_INK, rgba(0));
                for (AUTOMATION_COLOURS, 0..) |c, i|
                    p0.setPaletteEntry(AUTOMATION_FIRST + @as(u8, @intCast(i)), .{ .r = c.r, .g = c.g, .b = c.b, .a = 255 });
                self.drawAutomation(p0);
            }
            return true;
        }

        /// Once per frame. Everything but RASTERS depacks here; RASTERS depacked in
        /// last frame's scanlines. Restores the machine on the frame it finishes.
        pub fn frame(self: *Self, zigos: *ZigOS) zx0.Progress {
            const progress = if (self.fx == .rasters)
                self.stream.step(0)
            else
                self.stream.step(self.bytes_per_line * zg.PHYSICAL_HEIGHT);
            const done, const total = .{ self.stream.written(), self.stream.total() };
            switch (self.fx) {
                .fade => zigos.setBackgroundColor(rgba(fadeWord(done, total))),
                .bar => {
                    const fill = barFill(done, total, BAR_W);
                    fillBar(&zigos.lfbs[0], fill, 2);
                },
                .noise => if (tvnoise != null) {
                    const fb = &zigos.lfbs[0];
                    self.noise.fill(fb.fb[0 .. @as(usize, fb.fb_w) * fb.fb_h], fb.fb_w, fb.fb_h, NOISE_FIRST);
                },
                .automation => if (progress == .more) self.drawAutomation(&zigos.lfbs[0]),
                else => {},
            }
            if (progress != .more) self.finish(zigos);
            return progress;
        }

        fn hbl(zigos: *ZigOS, line: u16) void {
            _ = line;
            const self = active orelse return;
            _ = self.stream.step(self.bytes_per_line);
            zigos.setBackgroundColor(rgba(rasterWord(&self.stream)));
        }

        fn openPlane(self: *Self, zigos: *ZigOS) void {
            _ = self;
            const p0 = &zigos.lfbs[0];
            p0.is_enabled = true;
            p0.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
            p0.setPaletteEntry(1, rgba(0x333));
            p0.setPaletteEntry(2, rgba(0x777));
            if (tvnoise) |t| for (t.RAMP, 0..) |v, i| {
                p0.setPaletteEntry(NOISE_FIRST + @as(u8, @intCast(i)), .{ .r = v, .g = v, .b = v, .a = 255 });
            };
            p0.clearFrameBuffer(0);
        }

        fn finish(self: *Self, zigos: *ZigOS) void {
            if (self.fx == .rasters) {
                active = null;
                if (self.saved_hbl) |h| zigos.setHBLHandler(h) else zigos.removeHBLHandler();
            }
            const p0 = &zigos.lfbs[0];
            if (self.fx == .bar or self.fx == .text or self.fx == .noise or self.fx == .automation) p0.clearFrameBuffer(0);
            for (self.saved_pal, 0..) |c, i| p0.setPaletteEntry(@intCast(i), c);
            for (&zigos.lfbs, self.saved_enabled) |*fb, on| fb.is_enabled = on;
            zigos.setBackgroundColor(self.saved_bg);
        }

        /// AUTOMATION: one frame of bars over the whole plane, then the logo and
        /// the bee, placed in the 320x200 window (at (40,40) on an overscan plane).
        fn drawAutomation(self: *Self, fb: anytype) void {
            const w: usize = fb.fb_w;
            const h: usize = @min(fb.fb_h, zg.PHYSICAL_HEIGHT);
            var rows: [zg.PHYSICAL_HEIGHT]u8 = undefined;
            self.automation.bars(rows[0..h]);
            for (rows[0..h], 0..) |entry, y| @memset(fb.fb[y * fb.stride ..][0..w], entry);
            const ox = (w - zg.WIDTH) / 2;
            const oy = (h - zg.HEIGHT) / 2;
            stamp(fb, &automation_logo, ox + (zg.WIDTH - LOGO_W) / 2, oy + LOGO_Y);
            stamp(fb, &automation_bee, ox + BEE_X, oy + BEE_Y);
        }

        fn stamp(fb: anytype, mask: anytype, x0: usize, y0: usize) void {
            const M = @TypeOf(mask.*);
            for (0..M.H) |y| for (0..M.W) |x| {
                if (mask.ink(x, y)) fb.fb[(y0 + y) * fb.stride + x0 + x] = AUTOMATION_INK;
            };
        }

        /// The bar's first `width` pixels, one drawScanline per row. The run ends at
        /// BAR_X + width - 1, always < 320, as drawScanline requires.
        fn fillBar(fb: anytype, width: u16, entry: u8) void {
            if (width == 0) return;
            var y: u16 = BAR_Y;
            while (y < BAR_Y + BAR_H) : (y += 1) fb.drawScanline(BAR_X, BAR_X + width - 1, y, entry);
        }

        fn printCentered(zigos: *ZigOS, text: []const u8) void {
            const x: i16 = @intCast((zg.WIDTH - text.len * GLYPH_W) / 2);
            zigos.printText(&zigos.lfbs[0], text, x, TEXT_Y, 2, 0);
        }

        fn rgba(word: u16) Color {
            const c = stColour(word);
            return .{ .r = c.r, .g = c.g, .b = c.b, .a = 255 };
        }
    };
}

test "ST colour words map 3 bits a gun and ignore bit 3" {
    try std.testing.expectEqual(Rgb{ .r = 255, .g = 0, .b = 0 }, stColour(0x0700));
    try std.testing.expectEqual(stColour(0x0777), stColour(0x0FFF));
    try std.testing.expectEqual(Rgb{ .r = 73, .g = 73, .b = 73 }, stColour(0x0222));
}

test "fade runs white to black in eight ST steps and ends black exactly" {
    try std.testing.expectEqual(@as(u16, 0x777), fadeWord(0, 800));
    try std.testing.expectEqual(@as(u16, 0x777), fadeWord(114, 800));
    try std.testing.expectEqual(@as(u16, 0x666), fadeWord(115, 800));
    try std.testing.expectEqual(@as(u16, 0x111), fadeWord(799, 800)); // still not black one byte short
    try std.testing.expectEqual(@as(u16, 0x000), fadeWord(800, 800));
    var last: u16 = 0x777;
    var w: u32 = 0;
    while (w <= 800) : (w += 13) {
        const f = fadeWord(w, 800);
        try std.testing.expect(f <= last);
        last = f;
    }
}

test "automation bars cover every row with the ink or a bar colour, and repeat from the seed" {
    var a = Automation{ .bar_max = 100 };
    var rows = [_]u8{0} ** 200;
    for (0..50) |_| {
        @memset(&rows, 0);
        a.bars(&rows);
        for (rows) |e| try std.testing.expect(e == AUTOMATION_INK or (e >= AUTOMATION_FIRST and e < AUTOMATION_FIRST + 12));
    }
    var b = Automation{ .bar_max = 100 };
    var again = [_]u8{0} ** 200;
    for (0..50) |_| b.bars(&again);
    try std.testing.expectEqualSlices(u8, &rows, &again);
    // Elite Snooker's MaxBarHeight 30 and the edge 0 (every bar round(rnd*10)
    // tall, some 0 rows) still cover the plane
    for ([_]u8{ 30, 0, 255 }) |m| {
        var c = Automation{ .bar_max = m };
        for (0..50) |_| {
            @memset(&rows, 0);
            c.bars(&rows);
            try std.testing.expect(std.mem.indexOfScalar(u8, &rows, 0) == null);
        }
    }
    // an overscan-height pass stays in its slice
    var tall = [_]u8{0} ** 281;
    a.bars(tall[0..280]);
    try std.testing.expectEqual(@as(u8, 0), tall[280]);
    try std.testing.expect(std.mem.indexOfScalar(u8, tall[0..280], 0) == null);
}

test "automation random stays in [0, 1) and round(rnd*12) can reach 12, the kept-fillStyle case" {
    var a = Automation{ .bar_max = 100 };
    var saw_twelve = false;
    for (0..100_000) |_| {
        const r = a.random();
        try std.testing.expect(r >= 0 and r < 1);
        if (jsRound(r * 12) == 12) saw_twelve = true;
    }
    try std.testing.expect(saw_twelve);
}

test "the automation logo and bee masks keep every ink pixel of their assets" {
    const logo_raw = @embedFile("automation/automation.raw");
    const bee_raw = @embedFile("automation/bee.raw");
    for (0..LOGO_H) |y| for (0..LOGO_W) |x| {
        try std.testing.expectEqual(logo_raw[y * LOGO_W + x] == 1, automation_logo.ink(x, y));
    };
    for (0..BEE_W) |y| for (0..BEE_W) |x| {
        try std.testing.expectEqual(bee_raw[y * BEE_W + x] == 1, automation_bee.ink(x, y));
    };
    // the logo fits the 320-wide window, centred as drawImage(320 - w1/2, 7) halved
    try std.testing.expectEqual(@as(usize, 69), (320 - LOGO_W) / 2);
    try std.testing.expect(BEE_X + BEE_W <= 320);
}

test "the bar fills in proportion and never overflows its width" {
    try std.testing.expectEqual(@as(u16, 0), barFill(0, 1000, BAR_W));
    try std.testing.expectEqual(@as(u16, 120), barFill(500, 1000, BAR_W));
    try std.testing.expectEqual(@as(u16, BAR_W), barFill(1000, 1000, BAR_W));
    try std.testing.expect(BAR_X + BAR_W - 1 < 320); // drawScanline drops a run ending at the plane width
}
