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


fn handler_back(fb: *LogicalFB, zigos: *ZigOS, line: u16, column: u16) void {
    
    // _ = zigos;
    //_ = column;
    // _ = fb;    

    // -------------------------------------------------------------------------------
    // Top border part
    // -------------------------------------------------------------------------------

    // Open top border and use top buffer to fill the space
    if(line == 0 and column == 40) {

        Console.log("opening top border!", .{});
        zigos.setResolution(Resolution.truecolor);
    }

    // Open left border and use left buffer to fill the space
    if(line < 40) {
        if(column == 0) {
            zigos.setResolution(Resolution.truecolor);

            // copy left buffer to framebuffer
            // Console.log("Copy left buffer to visible space in left border at line: {} and column {}", .{ line, column });
            var i: usize = 0;
            const left_offset = line * 40;
            const fb_offset = line * WIDTH;

            while(i < 40) : (i += 1) {
                fb.fb[fb_offset + i] = left_b[left_offset + i];
            }   

            // mark the end of the left border
            fb.setFrameBufferHBLHandler(40, handler_back); 
        }

        // Close left border
        if(column == 40) {

            var i: u16 = line * WIDTH;
            while(i < (line + 1) * WIDTH) : (i += 1) {
                fb.fb[i] = top_b[i];
            }   

            // set the mark to open the next border
            fb.setFrameBufferHBLHandler(0, handler_back); 
        }
    }

    // -------------------------------------------------------------------------------
    // Middle part
    // -------------------------------------------------------------------------------

    if(line == 40) {
        var i: usize = 0;
        while(i < WIDTH * 40) : (i += 1) {
            fb.fb[i] = center_b[i];
        }
    }    

    // Open left border and use left buffer to fill the space
    if(line >= 40 and line < 240) {
        if(column == 0) {
            zigos.setResolution(Resolution.truecolor);

            // copy left buffer to framebuffer
            // Console.log("Copy left buffer to visible space in left border at line: {} and column {}", .{ line, column });
            var i: usize = 0;
            const left_offset = line * 40;
            const fb_offset = (line - 40) * WIDTH;

            while(i < 40) : (i += 1) {
                fb.fb[fb_offset + i] = left_b[left_offset + i];
            }   

            // mark the end of the left border
            fb.setFrameBufferHBLHandler(40, handler_back); 
        }

        // Close left border
        if(column == 40) {

            var i: u16 = 0;
            const fb_offset: u16 = (line-40) * WIDTH;

            // Console.log("reset FB after left border at l: {} c: {} from @{} ", .{ line, column, fb_offset });
            while(i < 40) : (i += 1) {
                fb.fb[fb_offset + i] = center_b[fb_offset + i];
            }  

            // set the mark to open the next border
            fb.setFrameBufferHBLHandler(0, handler_back); 
        }
    }

    // -------------------------------------------------------------------------------
    // Bottom border part
    // -------------------------------------------------------------------------------

    // Open low border
    if(line == 240 and column == 40) {

        Console.log("Opening bottom border!", .{});
        zigos.setResolution(Resolution.truecolor);
    }

    // Open left border and use left buffer to fill the space
    if(line >= 240 and line < 279) {
        if(column == 0) {
            zigos.setResolution(Resolution.truecolor);

            // copy left buffer to framebuffer
            // Console.log("Copy left buffer to visible space in left border at line: {} and column {}", .{ line, column });
            var i: usize = 0;
            const left_offset = line * 40;
            const fb_offset = (line - 80) * WIDTH;

            while(i < 40) : (i += 1) {
                fb.fb[fb_offset + i] = left_b[left_offset + i];
            }   

            // mark the end of the left border
            fb.setFrameBufferHBLHandler(40, handler_back); 
        }

        // Close left border
        if(column == 40) {

            var i: u16 = 0;
            const fb_offset: u16 =  (line - 80) * WIDTH; 
            const bottom_offset: u16 = (line - 240) * WIDTH;

            while(i < WIDTH) : (i += 1) {
                fb.fb[i + fb_offset] = bottom_b[i + bottom_offset];
            }   

            // set the mark to open the next border
            fb.setFrameBufferHBLHandler(0, handler_back); 
        }
    }

    // -------------------------------------------------------------------------------
    // End of VBL part (restore for next frame)
    // -------------------------------------------------------------------------------

    if (line == 279) {
        // reset handler 
        Console.log("Reset handler", .{});
        fb.setFrameBufferHBLHandler(40, handler_back); 

        // reset low fb
        // var i: u16 = 0;
        // const fb_offset: u16 =  160 * WIDTH; 

        // while(i < 40 * WIDTH) : (i += 1) {
        //     fb.fb[i + fb_offset] = center_b[i + fb_offset];
        // }   
    }

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
        fb.setFrameBufferHBLHandler(40, handler_back); 
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

        var fb = &zigos.lfbs[0];
        for(center_b) |pal_entry, idx| {
            fb.fb[idx] = pal_entry;
        }

        // _ = zigos;
        _ = elapsed_time;
        _ = self;
    }
};
