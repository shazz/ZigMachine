// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;

const Console = zg.Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const PHYSICAL_WIDTH: u16 = zg.PHYSICAL_WIDTH; // 400
const PHYSICAL_HEIGHT: u16 = zg.PHYSICAL_HEIGHT; // 280

// image: the full 400x280 overscan picture (borders included). It is the exact
// composite of the top/bottom/left/right/center pieces next to it, which all
// share this palette.
const modmate_b = @embedFile("../assets/screens/fullscreen/modmate.raw");

// palettes
const modmate_pal = convertU8ArraytoColors(@embedFile("../assets/screens/fullscreen/modmate_pal.dat"));

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
// Overscan is EARNED, ST-style: the plane holds a 400x280 buffer whose borders
// stay closed until we "open" them with the resolution-flicker trick. A per-plane
// HBL handler registered at OVERSCAN_MAGIC_X fires on every scanline and calls
// flickerBorder() — flickering in the top/bottom bands opens them, flickering on a
// visible line opens both side borders. Miss the magic column and the border shows
// garbage (see docs/HW_API.md "Opening the borders (overscan)").
fn handler_overscan(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    _ = zigos;
    _ = line;
    _ = col;
    fb.flickerBorder();
}

pub const Demo = struct {
    name: u8 = 0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane, overscan (physical coordinates 0..400 x 0..280)
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setOverscanBuffer();
        fb.setPalette(modmate_pal);
        // Do the border-opening trick every scanline at the magic column.
        fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, handler_overscan);

        comptime std.debug.assert(modmate_b.len == @as(usize, PHYSICAL_WIDTH) * @as(usize, PHYSICAL_HEIGHT));
        for (modmate_b, 0..) |pal_entry, idx| {
            fb.fb[idx] = pal_entry;
        }

        Console.log("demo init done!", .{});

        _ = self;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = zigos;
        _ = elapsed_time;
        _ = self;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        // static picture: the fullscreen buffer is filled once in init()
        _ = zigos;
        _ = elapsed_time;
        _ = self;
    }
};
