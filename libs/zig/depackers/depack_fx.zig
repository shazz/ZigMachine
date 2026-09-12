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
                .bar, .text, .noise => self.openPlane(zigos),
            }
            if (self.fx != .rasters) zigos.setBackgroundColor(rgba(0));
            if (self.fx == .text) printCentered(zigos, self.text);
            if (self.fx == .bar) fillBar(p0, BAR_W, 1);
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
            if (self.fx == .bar or self.fx == .text or self.fx == .noise) p0.clearFrameBuffer(0);
            for (self.saved_pal, 0..) |c, i| p0.setPaletteEntry(@intCast(i), c);
            for (&zigos.lfbs, self.saved_enabled) |*fb, on| fb.is_enabled = on;
            zigos.setBackgroundColor(self.saved_bg);
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

test "the bar fills in proportion and never overflows its width" {
    try std.testing.expectEqual(@as(u16, 0), barFill(0, 1000, BAR_W));
    try std.testing.expectEqual(@as(u16, 120), barFill(500, 1000, BAR_W));
    try std.testing.expectEqual(@as(u16, BAR_W), barFill(1000, 1000, BAR_W));
    try std.testing.expect(BAR_X + BAR_W - 1 < 320); // drawScanline drops a run ending at the plane width
}
