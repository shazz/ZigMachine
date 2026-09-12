// --------------------------------------------------------------------------
// Hardware-scroll demo — a bigger-than-screen (640x400) image shown through the
// 320x200 window of a SCROLL-mode plane (hw/video.zig renderPlaneScroll).
//
//   key 1  PAN      the window drifts around the big image (Lissajous), moving
//                   only FB_BASE — zero per-pixel work, pure hardware scroll.
//   key 2  DISTORT  a per-scanline sine offset written from an HBL handler
//                   (HSCROLL is re-read every line in scroll mode) — the classic
//                   ST/Amiga "screen-offset" wobble.
//
// Select in apps/floppy.zig. Plane 0 only.
// --------------------------------------------------------------------------
const std = @import("std");

const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;

const WIDTH: u32 = zg.WIDTH; // 320 visible
const HEIGHT: u32 = zg.HEIGHT; // 200 visible
const BUF_W: u16 = 640;
const BUF_H: u16 = 400;
const PAN_X_MAX: f32 = 320.0; // BUF_W - WIDTH
const PAN_Y_MAX: f32 = 200.0; // BUF_H - HEIGHT
const DISTORT_AMP: f32 = 24.0;

// Handler + update communicate through module state (an HBL handler is a plain fn).
var g_mode: u8 = 0;
var g_phase: f32 = 0;

pub const Demo = struct {
    fc: u32 = 0, // frame counter (elapsed_time from the loader is in ms, unreliable for phase)
    os: *ZigOS = undefined, // kept so setShadeMode(self, m) can reach the plane

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("scroll_demo init", .{});
        self.os = zigos;
        const fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;

        // Rainbow palette (0..63) + a bright text ink (64).
        var i: u16 = 0;
        while (i < 64) : (i += 1) fb.setPaletteEntry(@intCast(i), wheel(@intCast(i)));
        fb.setPaletteEntry(64, .{ .r = 245, .g = 245, .b = 255, .a = 255 });

        fb.setScrollPlane(BUF_W, BUF_H);
        paint(zigos, fb);
        self.setShadeMode(0);
    }

    // Register the per-line HBL only in DISTORT (each scanline is a machine->demo
    // dispatch, so PAN pays nothing for it).
    pub fn setShadeMode(self: *Demo, m: u32) void {
        g_mode = @intCast(@min(m, 1));
        const fb: *LogicalFB = &self.os.lfbs[0];
        if (g_mode == 1) fb.setFrameBufferHBLHandler(0, distortHBL) else fb.clearFrameBufferHBLHandler();
        Console.log("scroll_demo mode -> {s}", .{if (g_mode == 0) "PAN" else "DISTORT"});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        self.fc += 1;
        const t: f32 = @floatFromInt(self.fc);
        g_phase = t * 0.05;
        const fb: *LogicalFB = &zigos.lfbs[0];
        if (g_mode == 0) {
            const sx: u32 = @intFromFloat((0.5 + 0.5 * @sin(t * 0.006)) * PAN_X_MAX);
            const sy: u32 = @intFromFloat((0.5 + 0.5 * @sin(t * 0.0047)) * PAN_Y_MAX);
            fb.setScroll(sx, sy);
        } else {
            fb.setScroll(0, 0); // distort keeps the window fixed; the HBL bends each line
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt;
        // Nothing per-frame: the image is static, the hardware does the scrolling.
    }
};

// Per-scanline horizontal offset. In PAN mode it stays 0; in DISTORT it follows a
// travelling sine so each line samples the image shifted — a wavy screen.
fn distortHBL(fb: *LogicalFB, zigos: *ZigOS, line: u16, x: u16) void {
    _ = zigos;
    _ = x;
    if (g_mode == 0) {
        fb.setScrollFine(0);
        return;
    }
    const s = @sin(@as(f32, @floatFromInt(line)) * 0.08 + g_phase);
    fb.setScrollFine(@intFromFloat(DISTORT_AMP + DISTORT_AMP * s));
}

// Fill the 640x400 buffer with an XOR moiré + a few text banners.
fn paint(zigos: *ZigOS, fb: *LogicalFB) void {
    var y: u16 = 0;
    while (y < BUF_H) : (y += 1) {
        var x: u16 = 0;
        while (x < BUF_W) : (x += 1) {
            const v: u8 = @intCast(((@as(u32, x) ^ @as(u32, y)) >> 1) & 0x3F);
            fb.setPixelValue(x, y, v);
        }
    }
    var row: u16 = 24;
    while (row < BUF_H) : (row += 80) {
        zigos.printText(fb, "ZIGMACHINE * HARDWARE SCROLL * >>>", 20, @intCast(row), 64, 0);
    }
}

// A 64-step rainbow (RGB from a hue wheel).
fn wheel(i: u8) Color {
    const h: f32 = @as(f32, @floatFromInt(i)) / 64.0 * 6.0;
    const f = h - @floor(h);
    const q: u8 = @intFromFloat(255.0 * (1.0 - f));
    const t: u8 = @intFromFloat(255.0 * f);
    return switch (@as(u8, @intFromFloat(h)) % 6) {
        0 => .{ .r = 255, .g = t, .b = 0, .a = 255 },
        1 => .{ .r = q, .g = 255, .b = 0, .a = 255 },
        2 => .{ .r = 0, .g = 255, .b = t, .a = 255 },
        3 => .{ .r = 0, .g = q, .b = 255, .a = 255 },
        4 => .{ .r = t, .g = 0, .b = 255, .a = 255 },
        else => .{ .r = 255, .g = 0, .b = q, .a = 255 },
    };
}
