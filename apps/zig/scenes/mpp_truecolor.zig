// --------------------------------------------------------------------------
// MPP TRUECOLOR: more than 256 colours per plane, the STE "Multi Palette
// Picture" way (https://codeberg.org/zerkman/mpp): reload the palette between
// scanlines. A plane's HBL handler runs once before each line is composited, so
// every line can take a whole new palette. A gallery of truecolor pictures, three modes:
//
//   key 1  GLOBAL    one 256-colour palette for the whole picture, 1 plane
//   key 2  PER-LINE  1 plane, a best 256-colour palette for EACH of the lines
//   key 3  4 PLANES  each pixel opaque in exactly one plane; every plane has its
//                    own per-line palette (255 + transparent) = 1020 per line
//   Space            the next picture (wraps)
//
// The pictures, chosen for smooth gradients that band at 256 colours:
//   SPHERES  procedural (tools/mpp_picture.py)
//   PARROT   "Parrot.red.macaw.1.arp.750pix.jpg", Adrian Pingstone, public domain
//   SUNSET   "Sunset over ocean (27717086074).jpg", Lisa Ann Yount, CC0
//   HALO     procedural, a dusk sky and a low sun (tools/mpp_gradients.py)
//   HILLS    procedural, ridges fading into fog
// (both photos from Wikimedia Commons; tools/mpp_convert.py has crops and URLs).
//
// The modes cycle every CYCLE_FRAMES, then the next picture starts at mode 1. The
// caption band names the mode, the picture and the colours the converter counted.
//
// Each picture and mode is a ZX0-packed blob (build.zig: packed_assets.mpp_truecolor).
// Unpacked they overflow the 2 MB cart window, so the one on screen is depacked into
// one working buffer per switch (mpp_truecolor/blob.zig); the HBL is one @memcpy.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const hw = @import("hardware");
const blob = @import("mpp_truecolor/blob.zig");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;

const W = blob.W;
const H = blob.H;
const PLANES = blob.PLANES;
const MAP_REC = blob.MAP_REC;
const IMAGE_H: i16 = 180; // rows 180..199 are the caption band (converter's IMAGE_H)
const CYCLE_FRAMES: u32 = 8 * 60;
const INK: u8 = 1; // caption palette: 0 black, 1 white
const FIRE: u8 = 5; // demo_main Direction.Fire: the host sends it for Space (and Enter)
const DIR = "../assets/screens/mpp_truecolor/";

const Mode = struct { planes: usize, title: []const u8 };
const MODES = [_]Mode{
    .{ .planes = 1, .title = "1 GLOBAL: ONE 256-COLOUR PALETTE" },
    .{ .planes = 1, .title = "2 PER-LINE: 256 COLOURS EACH LINE" },
    .{ .planes = PLANES, .title = "3 4 PLANES: 4x255 COLOURS A LINE" },
};

// In the converter's PICTURES order; the packed blobs are [picture][mode].
const NAMES = [_][]const u8{ "SPHERES", "PARROT", "SUNSET", "HALO", "HILLS" };
const PACKED: [NAMES.len][MODES.len][]const u8 = @import("packed_assets").mpp_truecolor;

// p<P>_counts.bin: source, mode 1, mode 2, mode 3 distinct colours in the image area
// (then the source's hash, which only the headless harness reads).
const COUNTS = blk: {
    var c: [NAMES.len][]const u8 = undefined;
    for (&c, 0..) |*f, p| f.* = @embedFile(DIR ++ std.fmt.comptimePrint("p{d}_counts.bin", .{p}));
    break :blk c;
};
fn count(picture: usize, i: usize) u32 {
    return std.mem.readInt(u32, COUNTS[picture][i * 4 ..][0..4], .little);
}

// HBL handlers take no user pointer: the depacked view lives at module scope (empty: nothing loaded).
var view: blob.View = .{ .map = &.{}, .idx = &.{}, .pal = &.{} };

// Load this line's palette run for this plane: one copy, no conversion.
fn hbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    if (line >= H or view.map.len == 0) return;
    const rec = view.map[(@as(usize, fb.id) * H + line) * MAP_REC ..][0..MAP_REC];
    const n: usize = std.mem.readInt(u16, rec[6..8], .little);
    if (n == 0) return;
    const off: usize = std.mem.readInt(u32, rec[0..4], .little);
    const first: usize = std.mem.readInt(u16, rec[4..6], .little);
    const dst: [*]u8 = @ptrCast(fb.palette);
    @memcpy(dst[first * 4 ..][0 .. n * 4], view.pal[off..][0 .. n * 4]);
}

pub const Demo = struct {
    os: *ZigOS,
    picture: u8,
    mode: u8,
    frames: u32,
    work: []u8,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.os = zigos;
        self.picture = 0;
        self.mode = 0;
        self.frames = 0;
        self.work = &.{};
        zigos.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        for (&zigos.lfbs) |*fb| fb.setFrameBufferHBLHandler(0, hbl);
        self.work = freeRam(workLen() orelse return self.fail("a packed picture is unreadable")) orelse
            return self.fail("no free RAM to depack into");
        self.apply();
    }

    pub fn setShadeMode(self: *Demo, m: u32) void {
        if (m >= MODES.len) return;
        self.mode = @intCast(m);
        self.frames = 0;
        self.apply();
    }

    // Space arrives as Fire. Taking input() rather than key() keeps Escape and
    // Back returning to the menu (demo_main.zig).
    pub fn input(self: *Demo, dir: u8) void {
        if (dir == FIRE) self.nextPicture();
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.frames += 1;
        if (self.frames < CYCLE_FRAMES) return;
        if (self.mode + 1 < MODES.len) return self.setShadeMode(self.mode + 1);
        self.mode = 0; // after the last mode, the next picture from mode 1
        self.nextPicture();
    }

    // Everything is drawn once per switch; the HBLs do the per-frame work.
    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt;
    }

    fn nextPicture(self: *Demo) void {
        self.picture = @intCast((self.picture + 1) % NAMES.len);
        self.frames = 0;
        self.apply();
    }

    fn apply(self: *Demo) void {
        if (self.work.len == 0) return; // init failed and said why
        const m = MODES[self.mode];
        view = blob.load(PACKED[self.picture][self.mode], m.planes, self.work) orelse
            return self.fail("depack failed");
        const lfbs = &self.os.lfbs;
        for (lfbs, 0..) |*fb, p| {
            fb.is_enabled = p < m.planes;
            fb.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
        }
        if (m.planes == 1) {
            @memcpy(lfbs[0].fb[0 .. W * H], view.idx[0 .. W * H]);
        } else {
            splitPlanes(lfbs, view.idx);
        }
        self.caption(&lfbs[0]);
    }

    fn caption(self: *Demo, fb: *LogicalFB) void {
        const top: usize = @intCast(IMAGE_H);
        @memset(fb.fb[top * W .. H * W], 0);
        fb.setPaletteEntry(INK, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
        var buf: [40]u8 = undefined;
        const p = self.picture;
        const stats = std.fmt.bufPrint(&buf, "{d}/{d} {s}: {d} OF {d} COLOURS", .{ p + 1, NAMES.len, NAMES[p], count(p, self.mode + 1), count(p, 0) }) catch "?";
        self.os.printText(fb, MODES[self.mode].title, 4, IMAGE_H + 2, INK, 0);
        self.os.printText(fb, stats, 4, IMAGE_H + 11, INK, 0);
    }

    // Say so on screen and in the console, with nothing half-loaded behind it.
    fn fail(self: *Demo, why: []const u8) void {
        zg.Console.log("mpp_truecolor: {s}", .{why});
        view = .{ .map = &.{}, .idx = &.{}, .pal = &.{} };
        const lfbs = &self.os.lfbs;
        for (lfbs, 0..) |*fb, p| fb.is_enabled = p == 0;
        @memset(lfbs[0].fb[0 .. W * H], 0);
        lfbs[0].setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
        lfbs[0].setPaletteEntry(INK, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
        self.os.printText(&lfbs[0], "MPP TRUECOLOR: DEPACK FAILED", 4, IMAGE_H + 2, INK, 0);
    }
};

/// The largest blob once depacked and widened: the one buffer every switch reuses.
fn workLen() ?usize {
    var most: usize = 0;
    for (PACKED) |modes| for (modes, MODES) |image, m| {
        most = @max(most, blob.need(image, m.planes) orelse return null);
    };
    return most;
}

/// `len` bytes of the cart's RAM window above its statics and stack.
fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}

// Mode 3: index bytes, then plane bytes (blob.load checked < PLANES); 0 in the other planes.
fn splitPlanes(lfbs: *[PLANES]LogicalFB, idx: []const u8) void {
    for (lfbs) |*fb| @memset(fb.fb[0 .. W * H], 0);
    for (idx[0 .. W * H], idx[W * H ..][0 .. W * H], 0..) |index, plane, i| lfbs[plane].fb[i] = index;
}
