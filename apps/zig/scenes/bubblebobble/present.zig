// --------------------------------------------------------------------------
// The Shifter: the screen at the latched video base (32000 bytes, 16-pixel
// groups of four interleaved plane words) shown through the 16 colour
// registers, as one plane of palette indices.
//
// THE RASTERS ARE REAL. The game changes colour registers in the middle of the
// picture from its MFP Timer B handlers (the title's and hi-score table's
// gradients, the side bar). st/io.zig logs each write with its line; latch()
// takes the frame's log and the plane's own HBL handler replays it, line by
// line, into the plane's palette before that line is composited: a register
// changed per scanline, as on the ST. A frame without rasters runs no handler
// (except in the ZIG mode, below, which rewrites colour 0 on every line).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const k = @import("st/cpu.zig");
const io = @import("st/io.zig");
const frame = @import("st/frame.zig");

const LINE: usize = 160;
const LINES: usize = 200;

/// One plane byte -> four pixels (one nibble), one byte lane each, MSB = leftmost pixel:
/// u32s, not a u64, so the board's rv32 does no 64-bit shifts.
const SPREAD: [16]u32 = blk: {
    var t: [16]u32 = undefined;
    for (0..16) |n| {
        var v: u32 = 0;
        for (0..4) |i| v |= @as(u32, (n >> (3 - i)) & 1) << (8 * i);
        t[n] = v;
    }
    break :blk t;
};

/// The screen bytes the plane shows now: only a line that differs is converted again
/// (the game double-buffers, but most lines of its two screens are the same).
/// (From the cart RAM arena: a module-scope array would sit in the data segment as zeros.)
var shown: []align(4) u8 = &.{};
var shown_valid: bool = false;
/// Lines converted by the last present() (the harness checks a still screen converts none).
pub var converted: u32 = 0;
var pal_shown: [16]u16 = .{0xFFFF} ** 16;

/// The frame being shown: its starting palette and its raster writes, by line.
var top: [16]u16 = .{0} ** 16;
var writes: [1024]io.RasterWrite = undefined;
var nwrites: usize = 0;
/// writes[start[y] .. start[y + 1]] were made during line y.
var start: [LINES + 1]u16 = .{0} ** (LINES + 1);
var hbl_on: bool = false;
/// The plane last presented to (the harness reads it).
pub var plane: ?*zg.LogicalFB = null;

/// Take the frame the machine just ran (after frame.runFrame()).
pub fn latch() void {
    top = io.palette_top;
    nwrites = io.raster_n;
    @memcpy(writes[0..nwrites], io.rasters[0..nwrites]);
    var i: usize = 0;
    for (0..LINES + 1) |y| {
        while (i < nwrites and writes[i].line < y) i += 1;
        start[y] = @intCast(i);
    }
}

pub fn present(fb: *zg.LogicalFB) void {
    plane = fb;
    if (zig_mode) {
        const r = k.mem[frame.BASE + 0x543]; // the round ($540, its low byte)
        if (r != sky_round) buildSky(r);
    }
    if (nwrites == 0 and !zig_mode) {
        if (hbl_on) {
            fb.clearFrameBufferHBLHandler();
            pal_shown = .{0xFFFF} ** 16; // the handler left its last line's colours: set them all
        }
        hbl_on = false;
        for (0..16) |i| if (pal_shown[i] != top[i]) { // only a colour that changed
            fb.palette[i] = stColor(top[i]);
            pal_shown[i] = top[i];
        };
    } else if (!hbl_on) {
        fb.setFrameBufferHBLHandlerPure(0, hbl);
        hbl_on = true;
        pal_shown = .{0xFFFF} ** 16; // the handler rewrites them: set them all again after
    }
    const base = io.shown_base;
    if (base + LINE * LINES > k.mem.len) return;
    const scr = k.mem[base..][0 .. LINE * LINES];
    if (shown.len == 0) shown = std.mem.sliceAsBytes(zg.mem.mustAlloc(u32, LINE * LINES / 4)[0 .. LINE * LINES / 4]);
    converted = 0;
    for (0..LINES) |y| {
        const src = scr[y * LINE ..][0..LINE];
        const old = shown[y * LINE ..][0..LINE];
        if (shown_valid and sameLine(src, old)) continue;
        converted += 1;
        @memcpy(old, src);
        convertLine(src, fb.fb[y * @as(usize, fb.stride) ..][0..320]);
    }
    shown_valid = true;
}

/// A line compared as 40 words (the screen and the copy are word-aligned: the video base is a
/// multiple of 256 and a line 160 bytes).
fn sameLine(a: *const [LINE]u8, b: *const [LINE]u8) bool {
    const x: *const [LINE / 4]u32 = @ptrCast(@alignCast(a));
    const y: *const [LINE / 4]u32 = @ptrCast(@alignCast(b));
    var diff: u32 = 0;
    for (x, y) |p, q| diff |= p ^ q;
    return diff == 0;
}

/// 320 pixels from 20 groups of four interleaved plane words.
fn convertLine(src: *const [LINE]u8, dst: *[320]u8) void {
    for (0..LINE / 4) |h| { // 8 pixels: the high bytes, then the low, of each group
        const g = (h >> 1) * 8 + (h & 1);
        inline for (0..2) |half| {
            const sh: u3 = if (half == 0) 4 else 0;
            const v = SPREAD[(src[g] >> sh) & 15] | SPREAD[(src[g + 2] >> sh) & 15] << 1 |
                SPREAD[(src[g + 4] >> sh) & 15] << 2 | SPREAD[(src[g + 6] >> sh) & 15] << 3;
            std.mem.writeInt(u32, dst[h * 8 + half * 4 ..][0..4], v, .little);
        }
    }
}

/// Before line `line`: the picture's first palette, then each register the
/// game wrote during the line above.
fn hbl(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    if (line == 0) {
        for (0..16) |i| fb.palette[i] = stColor(top[i]);
        back = top[0];
    } else if (line < LINES) {
        for (writes[start[line - 1]..start[line]]) |w| {
            fb.palette[w.reg] = stColor(w.value);
            if (w.reg == 0) back = w.value;
        }
    } else return;
    // ZIG MODE: where the game's background (colour 0) is black, a 24-bit sky, a colour a line
    if (zig_mode and back == 0) fb.palette[0] = sky[line];
}

// ---- ZIG MODE (Z) ------------------------------------------------------------
// The same game, on KESTREL's own palette: colour 0 rewritten on every line by the
// plane's HBL (a copper sky, 24-bit, far past the ST's 512 colours) wherever the game
// leaves it black, tinted by the round (one of eight hues, a new one every round).
pub var zig_mode: bool = false;
var back: u16 = 0;
var sky: [LINES]u32 = undefined;
var sky_round: u32 = 0xFFFF_FFFF;

/// The sky for round `r`: a dark ramp from the hue's deep tone at the top to near black.
fn buildSky(r: u32) void {
    const HUES = [8][3]u32{ .{ 40, 60, 140 }, .{ 120, 40, 110 }, .{ 30, 110, 100 }, .{ 130, 70, 30 }, .{ 60, 40, 150 }, .{ 30, 100, 40 }, .{ 140, 40, 50 }, .{ 70, 70, 90 } };
    const h = HUES[r % 8];
    for (&sky, 0..) |*c, y| {
        const k8: u32 = @intCast(LINES - y); // 200 at the top, 1 at the bottom
        c.* = (0xFF << 24) | (h[2] * k8 / LINES) << 16 | (h[1] * k8 / LINES) << 8 | (h[0] * k8 / LINES);
    }
    sky_round = r;
}

/// The sky's colour at a line (the harness reads it).
pub fn skyAt(line: usize) u32 {
    return sky[line];
}

/// An ST colour register ($0RGB, three bits a gun) as the plane's RGBA.
pub fn stColor(word: u16) u32 {
    const r: u32 = gun(word >> 8);
    const g: u32 = gun(word >> 4);
    const b: u32 = gun(word);
    return (0xFF << 24) | (b << 16) | (g << 8) | r;
}

fn gun(nibble: u16) u32 {
    return @as(u32, nibble & 7) * 255 / 7;
}
