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
const Rows = @import("rowblit.zig").Rows;

const RW: u16 = zg.RASTER_WIDTH; // 800
const RH: u16 = zg.RASTER_HEIGHT; // 280
const BX: u16 = 80; // physical border
const BY: u16 = 40;
const VW: u16 = 640; // visible window
const VH: u16 = 200;

const PERIOD = 78;
// RAINBOW[i] = the border colour at diagonal distance i (mod PERIOD). Long enough
// that a pitch-1 blit (row y starts one pixel after row y-1) can read the whole
// raster: first column = the phase (< PERIOD) + the last row (RH) + the row (RW).
const RAINBOW: [PERIOD + RH + RW]u8 = blk: {
    @setEvalBranchQuota(10_000);
    var t: [PERIOD + RH + RW]u8 = undefined;
    for (&t, 0..) |*v, i| v.* = @intCast(@divFloor(@as(i32, @intCast(i % PERIOD)), 6) + 3);
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
        drawStatic(fb);
    }

    pub fn update(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = dt;
        self.fc += 1;
        const fb: *LogicalFB = &os.lfbs[0];
        self.paint(fb);
    }

    // The border is one diagonal rainbow, pixel (x,y) = RAINBOW[(y - phase) mod 78 + x],
    // and the phase moves one pixel a frame. The dark window and the frame never
    // change (init draws them once), so only the four border bands are redrawn,
    // by ONE blit each from RAINBOW with a source pitch of 1: row y then starts at
    // RAINBOW[s0 + y], the same colours the per-row 800-byte copy wrote, for
    // 96,000 px of blitter instead of 224,000 + 128,000 CPU stores.
    fn paint(self: *Demo, fb: *LogicalFB) void {
        const s0: usize = @intCast(@mod(-@as(i32, @intCast(self.fc)), PERIOD));
        var rows = Rows.open(fb, 1, null);
        const x1: u16 = RW - 1; // the frame's own pixels stay
        const y1: u16 = RH - 1;
        // The blitter clips this 800-stride plane to 200 rows, so the bands are
        // cut at row 200 and the lower part is drawn from a second base.
        band(&rows, s0, 1, 1, 0, x1 - 1, BY - 1); // top
        band(&rows, s0, 1, BY, 0, BX - 1, 200 - BY); // left, upper
        band(&rows, s0, BX + VW, BY, 0, x1 - (BX + VW), 200 - BY); // right, upper
        rows.destRow(fb, 200);
        band(&rows, s0, 1, 200, 200, BX - 1, BY + VH - 200); // left, lower
        band(&rows, s0, BX + VW, 200, 200, x1 - (BX + VW), BY + VH - 200); // right, lower
        band(&rows, s0, 1, BY + VH, 200, x1 - 1, y1 - (BY + VH)); // bottom
    }

    // One band at plane (x,y), `base` the row the destination starts at.
    fn band(rows: *Rows, s0: usize, x: u16, y: u16, base: u16, w: u16, h: u16) void {
        rows.blit(@intFromPtr(&RAINBOW) + s0 + y + x, @intCast(x), @intCast(y - base), w, h);
    }

    // The dark visible window and the bright frame at the very physical edge
    // (only overscan can reach it): constant, drawn once (by the CPU: the
    // blitter cannot reach rows 200+ of this plane from its own base, see paint).
    fn drawStatic(fb: *LogicalFB) void {
        fb.clearFrameBuffer(0);
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
