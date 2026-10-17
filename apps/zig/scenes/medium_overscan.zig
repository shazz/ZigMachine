// --------------------------------------------------------------------------
// Medium OVERSCAN demo — a medium-res plane covering the WHOLE 800x280 raster,
// borders included (LogicalFB.setMediumOverscan). Coordinates are physical;
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

// Diagonal rainbow: pixel (x,y) = ((x + y - phase) mod 78) / 6 + 3; indexed from the
// row's start offset, so RING[s + x] for x in 0..RW. (Generator: this block.)
const PERIOD: i32 = 78;
const RING: [RW + PERIOD]u8 = blk: {
    var t: [RW + PERIOD]u8 = undefined;
    for (&t, 0..) |*v, j| v.* = @intCast(@divFloor(@as(i32, @intCast(j)) % PERIOD, 6) + 3);
    break :blk t;
};

pub const Demo = struct {
    fc: u32 = 0,

    pub fn init(self: *Demo, os: *ZigOS) void {
        _ = self;
        Console.log("medium_overscan init", .{});
        const fb: *LogicalFB = &os.lfbs[0];
        fb.is_enabled = true;
        fb.setMediumOverscan();

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
    // in the border area, not a static blank). A row is one memcpy from the
    // diagonal ring (the original per-pixel mod/divFloor, tabulated), then a
    // memset for the dark window: ~280 block moves instead of 224,000 pixel calls.
    fn paint(self: *Demo, fb: *LogicalFB) void {
        const ph: i32 = @intCast(self.fc);
        var y: u16 = 0;
        while (y < RH) : (y += 1) {
            const row = fb.fb + @as(usize, y) * RW;
            const s: usize = @intCast(@mod(@as(i32, y) - ph, PERIOD));
            @memcpy(row[0..RW], RING[s..][0..RW]);
            if (y >= BY and y < BY + VH) @memset(row[BX .. BX + VW], 0);
        }
        // bright frame at the very physical edge (only overscan can reach it)
        drawFrame(fb);
    }

    fn drawFrame(fb: *LogicalFB) void {
        @memset(fb.fb[0..RW], 2);
        @memset(fb.fb[@as(usize, RH - 1) * RW ..][0..RW], 2);
        var y: usize = 0;
        while (y < RH) : (y += 1) {
            fb.fb[y * RW] = 2;
            fb.fb[y * RW + RW - 1] = 2;
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
