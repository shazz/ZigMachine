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
// Overscan is done the sanctioned Option-B way: the plane is switched to
// FULLSCREEN (a 400x280 buffer the machine composites across the whole raster,
// borders included). The older per-scanline "open the border with
// RES_TRUECOLOR from an HBL handler" trick is no longer implemented by the
// sealed machine (renderPlaneNormal only ever paints the visible 320x200 and
// fires its HBL for logical lines 0..199), so it cannot fill any border.
pub const Demo = struct {
    name: u8 = 0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane, fullscreen (physical coordinates 0..400 x 0..280)
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setFullscreen();
        fb.setPalette(modmate_pal);

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
