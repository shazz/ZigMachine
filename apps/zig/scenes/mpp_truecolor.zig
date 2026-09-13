// --------------------------------------------------------------------------
// MPP TRUECOLOR: more than 256 colours per plane, the STE "Multi Palette
// Picture" way (https://codeberg.org/zerkman/mpp): reload the palette between
// scanlines. A plane's HBL handler runs once before each line is composited, so
// every line can take a whole new palette. One truecolor picture, three modes:
//
//   key 1  GLOBAL    one 256-colour palette for the whole picture, 1 plane
//   key 2  PER-LINE  1 plane, a best 256-colour palette for EACH of the lines
//   key 3  4 PLANES  each pixel opaque in exactly one plane; every plane has its
//                    own per-line palette (255 + transparent) = 1020 per line
//
// The modes cycle by themselves every CYCLE_FRAMES. The picture and its palettes
// come from tools/mpp_convert.py (a procedural image, no photo); the caption band
// under it names the mode and the distinct colours the converter counted.
//
// Assets per mode (see the converter's docstring): m<N>_pal.bin RGBA bytes,
// m<N>_map.bin (plane, line) -> (offset, first entry, count), m<N>_idx.bin pixels.
// The handler is one @memcpy of count*4 bytes into the plane palette.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;

const W: usize = zg.WIDTH;
const H: usize = zg.HEIGHT;
const PLANES: usize = 4;
const IMAGE_H: i16 = 180; // rows 180..199 are the caption band (converter's IMAGE_H)
const MAP_REC: usize = 8; // u32 offset, u16 first, u16 count
const CYCLE_FRAMES: u32 = 8 * 60;
const INK: u8 = 1; // caption palette: 0 transparent, 1 white

const Assets = struct {
    pal: []const u8,
    map: []const u8,
    idx: []const u8,
    planes: usize, // 1: idx is u8 on plane 0; 4: idx is u16 LE plane << 8 | index
    title: []const u8,
};

const DIR = "../assets/screens/mpp_truecolor/";
const MODES = [3]Assets{
    .{ .pal = @embedFile(DIR ++ "m1_pal.bin"), .map = @embedFile(DIR ++ "m1_map.bin"), .idx = @embedFile(DIR ++ "m1_idx.bin"), .planes = 1, .title = "1 GLOBAL: ONE 256-COLOUR PALETTE" },
    .{ .pal = @embedFile(DIR ++ "m2_pal.bin"), .map = @embedFile(DIR ++ "m2_map.bin"), .idx = @embedFile(DIR ++ "m2_idx.bin"), .planes = 1, .title = "2 PER-LINE: 256 COLOURS EACH LINE" },
    .{ .pal = @embedFile(DIR ++ "m3_pal.bin"), .map = @embedFile(DIR ++ "m3_map.bin"), .idx = @embedFile(DIR ++ "m3_idx.bin"), .planes = PLANES, .title = "3 4 PLANES: 4x255 COLOURS A LINE" },
};

// counts.bin: source, mode 1, mode 2, mode 3 distinct colours in the image area.
const COUNTS = @embedFile(DIR ++ "counts.bin");
fn count(i: usize) u32 {
    return std.mem.readInt(u32, COUNTS[i * 4 ..][0..4], .little);
}

// HBL handlers take no user pointer: the active mode lives at module scope.
var active: *const Assets = &MODES[0];

// Load this line's palette run for this plane: one copy, no conversion.
fn hbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    if (line >= H) return;
    const rec = active.map[(@as(usize, fb.id) * H + line) * MAP_REC ..][0..MAP_REC];
    const n: usize = std.mem.readInt(u16, rec[6..8], .little);
    if (n == 0) return;
    const off: usize = std.mem.readInt(u32, rec[0..4], .little);
    const first: usize = std.mem.readInt(u16, rec[4..6], .little);
    const dst: [*]u8 = @ptrCast(fb.palette);
    @memcpy(dst[first * 4 ..][0 .. n * 4], active.pal[off..][0 .. n * 4]);
}

pub const Demo = struct {
    os: *ZigOS,
    mode: u8,
    frames: u32,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.os = zigos;
        self.mode = 0;
        self.frames = 0;
        zigos.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        for (&zigos.lfbs) |*fb| fb.setFrameBufferHBLHandler(0, hbl);
        self.apply();
    }

    pub fn setShadeMode(self: *Demo, m: u32) void {
        if (m >= MODES.len) return;
        self.mode = @intCast(m);
        self.frames = 0;
        self.apply();
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.frames += 1;
        if (self.frames >= CYCLE_FRAMES) self.setShadeMode((self.mode + 1) % MODES.len);
    }

    // Everything is drawn once per mode switch; the HBLs do the per-frame work.
    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt;
    }

    fn apply(self: *Demo) void {
        const a = &MODES[self.mode];
        active = a;
        const lfbs = &self.os.lfbs;
        for (lfbs, 0..) |*fb, p| {
            fb.is_enabled = p < a.planes;
            fb.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
        }
        if (a.planes == 1) {
            @memcpy(lfbs[0].fb[0 .. W * H], a.idx[0 .. W * H]);
        } else {
            splitPlanes(lfbs, a.idx);
        }
        self.caption(&lfbs[0]);
    }

    fn caption(self: *Demo, fb: *LogicalFB) void {
        const a = &MODES[self.mode];
        const top: usize = @intCast(IMAGE_H);
        @memset(fb.fb[top * W .. H * W], 0);
        fb.setPaletteEntry(INK, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
        var buf: [40]u8 = undefined;
        const stats = std.fmt.bufPrint(&buf, "{d} COLOURS ON SCREEN / SOURCE {d}", .{ count(self.mode + 1), count(0) }) catch "?";
        self.os.printText(fb, a.title, 4, IMAGE_H + 2, INK, 0);
        self.os.printText(fb, stats, 4, IMAGE_H + 11, INK, 0);
    }
};

// Mode 3: route each pixel's u16 (plane << 8 | index) to its plane; 0 elsewhere.
fn splitPlanes(lfbs: *[PLANES]LogicalFB, idx: []const u8) void {
    for (lfbs) |*fb| @memset(fb.fb[0 .. W * H], 0);
    for (0..W * H) |i| {
        const v = std.mem.readInt(u16, idx[i * 2 ..][0..2], .little);
        lfbs[v >> 8].fb[i] = @truncate(v);
    }
}
