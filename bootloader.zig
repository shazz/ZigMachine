// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const ZigOS = @import("zigos.zig").ZigOS;
const LogicalFB = @import("zigos.zig").LogicalFB;
const Console = @import("utils/debug.zig").Console;
const waveforms = @import("sound/waveforms.zig");

const Demo = @import("demo_test.zig").Demo;
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


