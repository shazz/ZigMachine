// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const ZigOS = @import("zigos.zig").ZigOS;
const LogicalFB = @import("zigos.zig").LogicalFB;
const Console = @import("utils/debug.zig").Console;
const waveforms = @import("sound/waveforms.zig");

const Demo = @import("floppy.zig").Demo;
// --------------------------------------------------------------------------
// Types
// --------------------------------------------------------------------------
const Resolution = @import("zigos.zig").Resolution;
const Color = @import("zigos.zig").Color;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const PHYSICAL_WIDTH: usize = @import("zigos.zig").PHYSICAL_WIDTH;
const PHYSICAL_HEIGHT: usize = @import("zigos.zig").PHYSICAL_HEIGHT;
const WIDTH: usize = @import("zigos.zig").WIDTH;
const HEIGHT: usize = @import("zigos.zig").HEIGHT;
const NB_PLANES: u8 = @import("zigos.zig").NB_PLANES;
const HORIZONTAL_BORDERS_WIDTH: u16 = @import("zigos.zig").HORIZONTAL_BORDERS_WIDTH;
const VERTICAL_BORDERS_HEIGHT: u16 = @import("zigos.zig").VERTICAL_BORDERS_HEIGHT;
const VERSION = "0.1";
const AUDIO_BUFFER_SIZE = 256;

const Direction = enum(u8) {
    Up = 0,
    Down = 1,
    Left = 2,
    Right = 3,
    Null = 4,
};

// --------------------------------------------------------------------------
// Audio
// --------------------------------------------------------------------------
const wave_b = @embedFile("assets/audio/therehegoes_i8_10026.smp");
const gen_wave: bool = false;
var wav_index: u32 = 0;

// Declare an enum.
const SamplingFrequency = enum(u32) {
    f_8K = 8820,
    f_11K = 11025,
    f_22K = 22050,
    f_44K = 44100
};
const sampling_freq = SamplingFrequency.f_11K;
var sound_left_buffer: [AUDIO_BUFFER_SIZE]f32 = std.mem.zeroes([AUDIO_BUFFER_SIZE]f32);
var sound_right_buffer: [AUDIO_BUFFER_SIZE]f32 = std.mem.zeroes([AUDIO_BUFFER_SIZE]f32);

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
export fn frame(elapsed_time: f32) void {
    demo.update(&zigos, elapsed_time);
    demo.render(&zigos, elapsed_time);
}

// --------------------------------------------------------------------------
//
// --------------------------------------------------------------------------
export fn getPlanesNumber() u8 {
    return NB_PLANES;
}

// --------------------------------------------------------------------------
//
// --------------------------------------------------------------------------
export fn isPlaneEnabled(id: u8) bool {
    return (&zigos).lfbs[id].is_enabled;
}

// --------------------------------------------------------------------------
//
// --------------------------------------------------------------------------
export fn getPhysicalFrameBufferWidth() usize {
    return PHYSICAL_WIDTH;
}

// --------------------------------------------------------------------------
//
// --------------------------------------------------------------------------
export fn getPhysicalFrameBufferHeight() usize {
    return PHYSICAL_HEIGHT;
}

// --------------------------------------------------------------------------
// The returned pointer will be used as an offset integer to the wasm memory
// --------------------------------------------------------------------------
export fn getPhysicalFrameBufferPointer() [*]u8 {
    return @ptrCast([*]u8, &zigos.physical_framebuffer);
}

// --------------------------------------------------------------------------
// The returned pointer will be used as an offset integer to the wasm memory
// --------------------------------------------------------------------------
export fn getLeftSoundBufferPointer() [*]f32 {
    return @ptrCast([*]f32, &sound_left_buffer);
}

export fn getRightSoundBufferPointer() [*]f32 {
    return @ptrCast([*]f32, &sound_right_buffer);
}

// --------------------------------------------------------------------------
// Get Audio buffer size
// --------------------------------------------------------------------------
export fn getAudioBufferSize() u32 {
    return AUDIO_BUFFER_SIZE;
}



// --------------------------------------------------------------------------
// generate render buffer
// --------------------------------------------------------------------------
export fn renderPhysicalFrameBuffer(fb_id: u8) void {
    if (zigos.resolution == Resolution.planes) {

        // get logical framebuffer
        var s_fb: *LogicalFB = &zigos.lfbs[fb_id];

        if (s_fb.is_enabled) {
            const palfb: *[WIDTH * HEIGHT]u8 = &s_fb.fb;
            const palette: *[256]Color = &s_fb.palette;

            var fb_index: u32 = 0;
            var vertical_border_opened: bool = false;
            var horizontal_border_opened: bool = false;

            // can call a VBL handler here
            for (zigos.physical_framebuffer) |*row, y| {

                switch (y) {
                    0...(VERTICAL_BORDERS_HEIGHT - 1) => {
                        // that's the trick, if the hbl handler changed the resolution to tc, the top border is now open

                        for (row) |*pixel, x| {
                                // within left border

                            // Check if a handler is defined for this logical FB
                            if (s_fb.fb_hbl_handler) |handler| {
                                if(x == s_fb.fb_hbl_handler_position) handler(s_fb, &zigos, @intCast(u16, y), @intCast(u16, x));
                            }

                            // open top border
                            if(y == 0 and x >= HORIZONTAL_BORDERS_WIDTH and zigos.resolution == Resolution.truecolor and !vertical_border_opened) {
                                vertical_border_opened = true;
                                zigos.resolution = Resolution.planes;
                                // Console.log("Top border opened!", .{});
                            }

                            // open left or right border
                            if( (x == 0 or x == (WIDTH + HORIZONTAL_BORDERS_WIDTH) ) and zigos.resolution == Resolution.truecolor) {

                                if(vertical_border_opened) {
                                    horizontal_border_opened = true;
                                    // Console.log("Top Left or Right border opened! at {}", .{x});
                                } 
                                zigos.resolution = Resolution.planes;
                            }                               

                            if(vertical_border_opened) {                            

                                switch (x) {
                                    0...HORIZONTAL_BORDERS_WIDTH - 1 => {

                                        // top left border
                                        if(horizontal_border_opened) {

                                            const pal_entry: u8 = palfb[fb_index];
                                            const color: Color = palette[pal_entry];
                                            pixel.* = color.toRGBA();
                                            fb_index += 1;

                                            if(x == HORIZONTAL_BORDERS_WIDTH - 1) fb_index -= HORIZONTAL_BORDERS_WIDTH;
                                        }
                                    },
                                    HORIZONTAL_BORDERS_WIDTH...(PHYSICAL_WIDTH - HORIZONTAL_BORDERS_WIDTH - 1) => {
                                        
                                        // top middle border
                                        if( x == HORIZONTAL_BORDERS_WIDTH) {
                                            zigos.resolution = Resolution.planes;
                                            horizontal_border_opened = false;
                                        }

                                        const pal_entry: u8 = palfb[fb_index];
                                        const color: Color = palette[pal_entry];
                                        pixel.* = color.toRGBA();
                                        fb_index += 1;
                                    },
                                    (PHYSICAL_WIDTH - HORIZONTAL_BORDERS_WIDTH)...PHYSICAL_WIDTH - 1 => {
         
                                        // top right border
                                        if(horizontal_border_opened) {

                                            if(x == PHYSICAL_WIDTH - HORIZONTAL_BORDERS_WIDTH) {
                                                fb_index -= HORIZONTAL_BORDERS_WIDTH;
                                                // Console.log("Reset fb_index to {} on line {}", .{fb_index, y});
                                            }
                          
                                            const pal_entry: u8 = palfb[fb_index];
                                            const color: Color = palette[pal_entry];
                                            pixel.* = color.toRGBA();
                                            fb_index += 1;

                                            if(x == PHYSICAL_WIDTH - 1) horizontal_border_opened = false;                                   
                                        }
                                    },                                    
                                    else => {},
                                }
                            }
                        }
                    },
                    VERTICAL_BORDERS_HEIGHT...(PHYSICAL_HEIGHT - VERTICAL_BORDERS_HEIGHT) - 1 => {

                        // reset the fb index and reolsution mode if the borders trick was used
                        if (y == VERTICAL_BORDERS_HEIGHT) {
                            vertical_border_opened = false;
                            fb_index = 0;
                        }
                        for (row) |*pixel, x| {

                            // Check if a handler is defined for this logical FB
                            if (s_fb.fb_hbl_handler) |handler| {
                                if(x == s_fb.fb_hbl_handler_position) handler(s_fb, &zigos, @intCast(u16, y), @intCast(u16, x));
                            }
                          
                            // open left and right border
                            if( (x == 0 or x == (WIDTH + HORIZONTAL_BORDERS_WIDTH) ) and zigos.resolution == Resolution.truecolor) {
                                horizontal_border_opened = true;
                                zigos.resolution = Resolution.planes;
                                // Console.log("Middle Left or Right border opened!", .{});
                            }                                   

                            switch (x) {
                                 0...HORIZONTAL_BORDERS_WIDTH - 1 => {

                                    // middle left border
                                    if(horizontal_border_opened) {

                                        const pal_entry: u8 = palfb[fb_index];
                                        const color: Color = palette[pal_entry];
                                        pixel.* = color.toRGBA();
                                        fb_index += 1;

                                        if(x == HORIZONTAL_BORDERS_WIDTH - 1) {
                                            fb_index -= HORIZONTAL_BORDERS_WIDTH;
                                            zigos.resolution = Resolution.planes;
                                            horizontal_border_opened = false;
                                        }
                                    }
                                },                                
                                HORIZONTAL_BORDERS_WIDTH...(PHYSICAL_WIDTH - HORIZONTAL_BORDERS_WIDTH - 1) => {

                                    // visible screen
                                    const pal_entry: u8 = palfb[fb_index];
                                    const color: Color = palette[pal_entry];
                                    pixel.* = color.toRGBA();

                                    fb_index += 1;
                                },
                                (PHYSICAL_WIDTH - HORIZONTAL_BORDERS_WIDTH)...PHYSICAL_WIDTH - 1 => {
         
                                    // middle right border
                                    if(horizontal_border_opened) {

                                        if(x == PHYSICAL_WIDTH - HORIZONTAL_BORDERS_WIDTH) fb_index -= HORIZONTAL_BORDERS_WIDTH;
                        
                                        const pal_entry: u8 = palfb[fb_index];
                                        const color: Color = palette[pal_entry];
                                        pixel.* = color.toRGBA();
                                        fb_index += 1;

                                        if(x == PHYSICAL_WIDTH - 1) {
                                            horizontal_border_opened = false;    
                                            zigos.resolution = Resolution.planes;
                                        }                               
                                    }
                                },  
                                else => {},
                            }
                        }
                    },
                    (PHYSICAL_HEIGHT - VERTICAL_BORDERS_HEIGHT)...(PHYSICAL_HEIGHT - 1) => {

                         // Console.log("Bottom border opened at index {} and row {} vs {}", .{fb_index, y, palfb.len} );
                        for (row) |*pixel, x| {

                            // Check if a handler is defined for this logical FB
                            if (s_fb.fb_hbl_handler) |handler| {
                                if(x == s_fb.fb_hbl_handler_position) handler(s_fb, &zigos, @intCast(u16, y), @intCast(u16, x));
                            }

                            // open low border
                            if(y == (PHYSICAL_HEIGHT - VERTICAL_BORDERS_HEIGHT) and x >= HORIZONTAL_BORDERS_WIDTH and zigos.resolution == Resolution.truecolor and !vertical_border_opened) {
                                fb_index -= VERTICAL_BORDERS_HEIGHT * WIDTH;
                                vertical_border_opened = true;
                                zigos.resolution = Resolution.planes;
                                // Console.log("Bottom border opened!", .{});
                            }

                            // open left and right border
                            if(vertical_border_opened) {

                                if( (x == 0 or x == (WIDTH + HORIZONTAL_BORDERS_WIDTH) ) and zigos.resolution == Resolution.truecolor) {

                                    horizontal_border_opened = true;
                                    zigos.resolution = Resolution.planes;
                                    // Console.log("Bottom Left border opened!", .{});
                                }                        

                                // within left border
                                switch (x) {
                                    0...HORIZONTAL_BORDERS_WIDTH - 1 => {
       
                                        if(horizontal_border_opened) {

                                            // Console.log("filling low left border from fb at {} on line  {}", .{fb_index, y});

                                            const pal_entry: u8 = palfb[fb_index];
                                            const color: Color = palette[pal_entry];
                                            pixel.* = color.toRGBA();
                                            fb_index += 1;

                                            if(x == (HORIZONTAL_BORDERS_WIDTH - 1) ) {
                                                fb_index -= HORIZONTAL_BORDERS_WIDTH;
                                                zigos.resolution = Resolution.planes;
                                                horizontal_border_opened = false;
                                            }
                                        }
                                    },                                                                    
                                    HORIZONTAL_BORDERS_WIDTH...(PHYSICAL_WIDTH - HORIZONTAL_BORDERS_WIDTH - 1) => {
                                        // visible screen

                                        const pal_entry: u8 = palfb[fb_index];
                                        const color: Color = palette[pal_entry];
                                        pixel.* = color.toRGBA();

                                        fb_index += 1;
                                    },
                                    (PHYSICAL_WIDTH - HORIZONTAL_BORDERS_WIDTH)...PHYSICAL_WIDTH - 1 => { 

                                        if(horizontal_border_opened) {

                                            if(x == (PHYSICAL_WIDTH - HORIZONTAL_BORDERS_WIDTH) ) 
                                                fb_index -= HORIZONTAL_BORDERS_WIDTH;
                          
                                            const pal_entry: u8 = palfb[fb_index];
                                            const color: Color = palette[pal_entry];
                                            pixel.* = color.toRGBA();

                                            fb_index += 1;

                                            if(x == (PHYSICAL_WIDTH - 1) ) {
                                                horizontal_border_opened = false;   
                                                zigos.resolution = Resolution.planes;
                                            }                                
                                        }
                                    },                                       
                                    else => {},
                                }
                            }

                            // disable border tricks at the end of the VBL
                            if(y == PHYSICAL_HEIGHT - 1) {
                                zigos.resolution = Resolution.planes;
                                vertical_border_opened = false;
                                horizontal_border_opened = false;
                            }
                        }
                    },                    
                    else => {},
                }
            }
        }
        // else {
        //     Console.log("This is TrueColor!", .{});
        // }
    }
}

export fn clearPhysicalFrameBuffer() void {

    // can call a VBL handler here
    for (zigos.physical_framebuffer) |*row, y| {
        if (zigos.hbl_handler) |handler| {
            handler(&zigos, @intCast(u16, y));
        }

        // Clear fb with background color
        const color: Color = zigos.getBackgroundColor();
        for (row) |*pixel| {
            pixel.* = color.toRGBA();
        }
    }
}

// --------------------------------------------------------------------------
//
// --------------------------------------------------------------------------
export fn input(dir: Direction) void {
    if (dir == .Up)
        Console.log("up", .{});
    if (dir == .Down)
        Console.log("down", .{});
    if (dir == .Left)
        Console.log("left", .{});
    if (dir == .Right)
        Console.log("right", .{});
}

// --------------------------------------------------------------------------
// generate a frame of audio
// --------------------------------------------------------------------------
export fn generateAudio() void {

    const resample_multiplier: u32 = @enumToInt(SamplingFrequency.f_44K) / @enumToInt(sampling_freq);

    var array_idx: usize = 0;
    var resample_index: usize = 0;
    while (array_idx < AUDIO_BUFFER_SIZE) {
        
        var val: u8 = 0;
        if(resample_index + wav_index < wave_b.len) {
            val = wave_b[resample_index + wav_index] + 127;
        }

        var i: u32 = 0;
        while(i < resample_multiplier) {
            sound_left_buffer[array_idx + i] = @intToFloat(f32, val) / 128.0 - 1;

            i += 1;
        }
        array_idx += resample_multiplier;
        resample_index += 1;
    }
    
    wav_index += AUDIO_BUFFER_SIZE/4;
    if(wav_index > wave_b.len)
        wav_index = 0;
}
