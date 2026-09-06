// --------------------------------------------------------------------------
// Resolution-switch demo — one screen, two resolutions. A 640-wide MEDIUM plane
// is filled with fine vertical colour bars + labels; a per-plane HBL handler
// flips the RESOLUTION register to LOW for a band of scanlines that sweeps down
// the screen. In that band the machine composites the SAME buffer pixel-doubled
// (first 320 columns), so the bars/text go chunky — the classic ST per-scanline
// resolution switch (see hw/video.zig renderPlaneMedium).
//
// Select in apps/floppy.zig. Plane 0, medium res.
// --------------------------------------------------------------------------
const std = @import("std");

const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;

const MW: u16 = zg.MEDIUM_WIDTH; // 640
const MH: u16 = zg.MEDIUM_HEIGHT; // 200
const BAND: i32 = 46; // low-res band height (scanlines)

var g_lo: i32 = 0; // band top scanline (animated)

pub const Demo = struct {
    fc: u32 = 0,

    pub fn init(self: *Demo, os: *ZigOS) void {
        _ = self;
        Console.log("res_switch init", .{});
        const fb: *LogicalFB = &os.lfbs[0];
        fb.is_enabled = true;
        fb.setMediumPlane();

        // 15-colour rainbow bars + white ink.
        var i: u16 = 0;
        while (i < 16) : (i += 1) fb.setPaletteEntry(@intCast(i), wheel(@intCast(i)));
        fb.setPaletteEntry(16, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
        fb.setPaletteEntry(17, .{ .r = 0, .g = 0, .b = 0, .a = 255 });

        // Fine 6px vertical colour bars across the whole 640 buffer.
        var y: u16 = 0;
        while (y < MH) : (y += 1) {
            var x: u16 = 0;
            while (x < MW) : (x += 1) fb.setPixelValue(x, y, @intCast((x / 6) % 15 + 1));
        }
        // Labels (crisp where medium, chunky where the low band sweeps over them).
        os.printText(fb, "MEDIUM 640x200 - crisp text, fine bars", 40, 24, 16, 17);
        os.printText(fb, "an HBL drops this band to LOW 320 (doubled)", 40, 150, 16, 17);
        os.printText(fb, "same pixels, switched per scanline", 40, 172, 16, 17);

        fb.setFrameBufferHBLHandler(0, resHBL); // fires every scanline in medium mode
    }

    pub fn update(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        self.fc += 1;
        // Sweep the low-res band up and down the screen.
        const t: f32 = @floatFromInt(self.fc);
        g_lo = @intFromFloat((0.5 + 0.5 * @sin(t * 0.02)) * @as(f32, @floatFromInt(@as(i32, MH) - BAND)));
    }

    pub fn render(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = self;
        _ = os;
        _ = dt;
        // Static image; the machine does the per-scanline resolution switch.
    }
};

// Per-scanline: LOW inside the sweeping band, MEDIUM elsewhere.
fn resHBL(fb: *LogicalFB, os: *ZigOS, line: u16, x: u16) void {
    _ = fb;
    _ = x;
    const ly: i32 = line;
    if (ly >= g_lo and ly < g_lo + BAND) os.setResolution(.planes) else os.setResolution(.medium);
}

fn wheel(i: u8) Color {
    const h: f32 = @as(f32, @floatFromInt(i)) / 16.0 * 6.0;
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
