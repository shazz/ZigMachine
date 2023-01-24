// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const readU16Array = @import("../utils/loaders.zig").readU16Array;
const readI16Array = @import("../utils/loaders.zig").readI16Array;
const convertU8ArraytoColors = @import("../utils/loaders.zig").convertU8ArraytoColors;

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;
const RenderTarget = @import("../zigos.zig").RenderTarget;
const Resolution = @import("../zigos.zig").Resolution;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

// image
const center_b = @embedFile("../assets/screens/fullscreen/center.raw");
const top_b = @embedFile("../assets/screens/fullscreen/top.raw");
const bottom_b = @embedFile("../assets/screens/fullscreen/bottom.raw");
const left_b = @embedFile("../assets/screens/fullscreen/left.raw");
const right_b = @embedFile("../assets/screens/fullscreen/right.raw");

// palettes
const modmate_pal = convertU8ArraytoColors(@embedFile("../assets/screens/fullscreen/center_pal.dat"));


// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
// fn handler_hbl(zigos: *ZigOS, line: u16) void {
//     zigos.setBackgroundColor(back_rasters_b[(line + 12 + raster_index) % 255]);     
// }


fn handler_back(fb: *LogicalFB, zigos: *ZigOS, line: u16) void {
    
    // var fb2 = &zigos.lfbs[0];

    if(line == 0) {
        // Console.log("opening the top border", .{});
        zigos.setResolution(Resolution.truecolor);
    }

    if(line < 40) {
        var i: usize = line * WIDTH;
        while(i < (line + 1) * WIDTH) : (i += 1) {
            fb.fb[i] = top_b[i];
        }   
    }

    if(line == 40) {
        var i: usize = 0;
        while(i < WIDTH * 40) : (i += 1) {
            fb.fb[i] = center_b[i];
        }
    }

    if(line == 240) {
        // Console.log("opening the bottom border", .{});
        zigos.setResolution(Resolution.truecolor);
    }    

    if(line >= 240 and line < 279) {
        var i: usize = 0;
        var index: usize = (line - 80) * WIDTH;
        var index2: usize = (line - 240) * WIDTH;

        while(i < WIDTH) : (i += 1) {
            fb.fb[index + i] = bottom_b[index2 + i];
        }   
    }    
    if(line == 279) {
        var i: usize = (HEIGHT - 40) * WIDTH;
        while(i < HEIGHT * WIDTH) : (i += 1) {
            fb.fb[i] = center_b[i];
        }  
    }

    // Console.log("opening the left and right border", .{});
    // zigos.setResolution(Resolution.truecolor);    

    // _ = zigos;
}

pub const Demo = struct {
  
    name: u8 = 0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(modmate_pal);
  
        for(center_b) |pal_entry, idx| {
            fb.fb[idx] = pal_entry;
        }

        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(handler_back); 
        // zigos.setHBLHandler(handler_hbl);     

        Console.log("demo init done!", .{});

        _ = self;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        _ = zigos;
        _ = elapsed_time;
        _ = self;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        // var fb = &zigos.lfbs[0];

        _ = zigos;
        _ = elapsed_time;
        _ = self;
    }
};
