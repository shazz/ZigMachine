// --------------------------------------------------------------------------
// Medium OVERSCAN demo — a medium-res plane covering the WHOLE 800x280 raster,
// borders included (LogicalFB.setMediumFullscreen). Coordinates are physical;
// the "visible window" is the centre 640x200 at (80,40). This fills the borders
// with crisp medium content — the medium twin of the low-res Option-B overscan.
//
// Select in apps/floppy.zig. Plane 0, medium overscan.
// --------------------------------------------------------------------------
const std = @import("std");

const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;

const RW: u16 = zg.RASTER_WIDTH; // 800
const RH: u16 = zg.RASTER_HEIGHT; // 280
const BX: u16 = 80; // physical border
const BY: u16 = 40;
const VW: u16 = 640; // visible window
const VH: u16 = 200;

pub const Demo = struct {
    fc: u32 = 0,

    pub fn init(self: *Demo, os: *ZigOS) void {
        _ = self;
        Console.log("medium_overscan init", .{});
        const fb: *LogicalFB = &os.lfbs[0];
        fb.is_enabled = true;
        fb.setMediumFullscreen();

        fb.setPaletteEntry(0, .{ .r = 20, .g = 20, .b = 40, .a = 255 }); // visible bg
        fb.setPaletteEntry(1, .{ .r = 235, .g = 235, .b = 245, .a = 255 }); // ink
        fb.setPaletteEntry(2, .{ .r = 250, .g = 60, .b = 90, .a = 255 }); // frame
        var i: u16 = 3;
        while (i < 16) : (i += 1) fb.setPaletteEntry(@intCast(i), wheel(@intCast(i - 3), 13));
    }

    pub fn update(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = dt;
        self.fc += 1;
        const fb: *LogicalFB = &os.lfbs[0];
        self.paint(fb);
    }

    // Redraw each frame so the border pattern animates (proving it's live content
    // in the border area, not a static blank).
    fn paint(self: *Demo, fb: *LogicalFB) void {
        const ph: i32 = @intCast(self.fc);
        var y: u16 = 0;
        while (y < RH) : (y += 1) {
            const inWinY = (y >= BY and y < BY + VH);
            var x: u16 = 0;
            while (x < RW) : (x += 1) {
                if (inWinY and x >= BX and x < BX + VW) {
                    fb.setPixelValue(x, y, 0); // dark visible area
                } else {
                    // animated diagonal rainbow in the BORDER region (indices 3..15)
                    const d = @mod(@as(i32, x) + @as(i32, y) - ph, 78);
                    fb.setPixelValue(x, y, @intCast(@divFloor(d, 6) + 3));
                }
            }
        }
        // bright frame at the very physical edge (only overscan can reach it)
        drawFrame(fb);
    }

    fn drawFrame(fb: *LogicalFB) void {
        var x: u16 = 0;
        while (x < RW) : (x += 1) {
            fb.setPixelValue(x, 0, 2);
            fb.setPixelValue(x, RH - 1, 2);
        }
        var y: u16 = 0;
        while (y < RH) : (y += 1) {
            fb.setPixelValue(0, y, 2);
            fb.setPixelValue(RW - 1, y, 2);
        }
    }

    pub fn render(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = self;
        _ = dt;
        const fb: *LogicalFB = &os.lfbs[0];
        os.printText(fb, "MEDIUM OVERSCAN 800x280 - drawing into the borders!", 8, 14, 1, 255);
        os.printText(fb, "the visible window is the dark centre; rainbow = border", @intCast(BX + 60), @intCast(BY + 90), 1, 0);
        os.printText(fb, "borders are live medium content now", @intCast(BX + 140), @intCast(BY + VH + 14), 1, 255);
    }
};

fn wheel(i: u8, n: u8) Color {
    const h: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n)) * 6.0;
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
