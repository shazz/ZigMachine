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

const Direction = enum(u8) {
    Up = 0,
    Down = 1,
    Left = 2,
    Right = 3,
    Null = 4,
};

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
// Convert u8 to f32 buffer
// --------------------------------------------------------------------------
export fn u8ArrayToF32Array(u8Array: [*]u8, u8ArrayLength: usize, f32Array: [*]f32, f32ArrayLength: usize) void {
    const size = @min(u8ArrayLength, f32ArrayLength);
    for (u8Array[0..size]) |b, i| f32Array[i] = @intToFloat(f32, b) / 128.0 - 1;
}

// --------------------------------------------------------------------------
// generate a frame of audio
// --------------------------------------------------------------------------
export fn generateAudio(u8Array: [*]u8, u8ArrayLength: usize) void {

    // set sample rate
    const sampleRate = 44100;

    const u4Tou8WaveTransformConstant: f32 = 255.0 / 15.0;
    const Note = struct {
        waveform: *[32]u4,
        hz: u16,
    };

    // retrieve Note data
    const note: Note = Note{
        .waveform = &waveforms.SineWave,
        .hz = 440,
    };

    // Set previous amplitude to mid amplitude (0 signed I guess)
    var previous_note_amplitude: i32 = 0;
    var note_period: u8 = 0;
    var samples_per_wave = sampleRate / note.hz;

    var array_idx: usize = 0;
    while (array_idx < u8ArrayLength) {
        const period_or_end = @min(u8ArrayLength, array_idx + samples_per_wave);
        var period_idx: usize = array_idx;

        // Generating 1 period as defined by the note frequency and sampling rate
        while (period_idx < period_or_end) {

            // one period == the 32 amplitude values of the waveform
            const samples_per_note_slice = samples_per_wave / note.waveform.len;
            var samples_idx: i32 = 0;

            // Get waveform amplitude
            const note_amplitude: i32 = note.waveform[note_period];

            // convert each waveform value and fill the buffer
            while (period_idx < period_or_end and samples_idx < samples_per_note_slice) : (period_idx += 1) {

                // sample value = previous amp + (delta(current, previous)*index / nb_samples)
                const wave_as_u4 = @intToFloat(f32, previous_note_amplitude) +
                    (@intToFloat(f32, (note_amplitude - previous_note_amplitude) * samples_idx) /
                    @intToFloat(f32, samples_per_note_slice));

                u8Array[period_idx] = @floatToInt(u8, wave_as_u4 * u4Tou8WaveTransformConstant);
                samples_idx += 1;
            }

            // get next index of amplitude
            note_period = (note_period + 1) % @intCast(u8, note.waveform.len);

            // memorize last amplitude
            previous_note_amplitude = note_amplitude;
        }

        // Advance in buffer of 1 period (44100 samples)
        array_idx += samples_per_wave;
    }
}
