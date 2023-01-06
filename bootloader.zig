// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const ZigOS = @import("zigos.zig").ZigOS;
const LogicalFB = @import("zigos.zig").LogicalFB;
const Demo = @import("demo.zig").Demo;
const Console = @import("utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Types
// --------------------------------------------------------------------------
const Resolution = @import("zigos.zig").Resolution;
const Color = @import("zigos.zig").Color;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: usize = @import("zigos.zig").HEIGHT;
const WIDTH: usize = @import("zigos.zig").WIDTH;
const NB_PLANES: u8 = @import("zigos.zig").NB_PLANES;
const VERSION = "0.1";

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var zigos: ZigOS = undefined;
var demo: Demo = undefined;

// --------------------------------------------------------------------------
//
// Exposed WASM functions
//
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// boot!
// --------------------------------------------------------------------------
export fn boot() void {
    Console.log("ZigMachine v. {s}\n", .{VERSION});

    zigos.init();
    demo.init(&zigos);
}

// --------------------------------------------------------------------------
// compute a frame
// --------------------------------------------------------------------------
export fn frame() void {
    demo.update(&zigos);
    demo.render(&zigos);
}

// --------------------------------------------------------------------------
//
// --------------------------------------------------------------------------
export fn getPhysicalFrameBufferNb() u8 {
    return NB_PLANES;
}

// --------------------------------------------------------------------------
// The returned pointer will be used as an offset integer to the wasm memory
// --------------------------------------------------------------------------
export fn getPhysicalFrameBufferPointer() [*]u8 {
    return @ptrCast([*]u8, &zigos.physical_framebuffer);
}
// --------------------------------------------------------------------------
// generate render buffer
// --------------------------------------------------------------------------
export fn renderPhysicalFrameBuffer(fb_id: u8) void {
    if (zigos.resolution == Resolution.planes) {

        // get logical framebuffer
        const s_fb: LogicalFB = zigos.lfbs[fb_id];
        const palfb: [WIDTH * HEIGHT]u8 = s_fb.fb;
        const palette: [256]Color = s_fb.palette;

        var i: u32 = 0;

        // can call a VBL handler here
        for (zigos.physical_framebuffer) |*row| {

            // can call a HBL handler here
            for (row) |*pixel| {
                const pal_entry: u8 = palfb[i];
                const color: Color = palette[pal_entry];

                pixel.* = color.toRGBA();

                i += 1;
            }
        }
    } else {
        Console.log("This is TrueColor!", .{});
        // only one FB in truecolor
        if (fb_id == 0) {
            for (zigos.physical_framebuffer) |*row, y| {
                // can call a HBL handler here
                for (row) |*pixel, x| {
                    const col: Color = Color{ .r = @intCast(u8, x), .g = @intCast(u8, y), .b = @intCast(u8, y), .a = 255 };
                    pixel.* = col.toRGBA();
                }
            }
        }
    }
}
