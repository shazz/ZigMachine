const waveforms = @import("./waveforms.zig");

extern fn print(text: [*:0]const u8, length: usize) void;
fn print_(text: [:0]const u8) void {
    print(text, text.len);
}

export fn u8ArrayToF32Array(u8Array: [*]u8, u8ArrayLength: usize, f32Array: [*]f32, f32ArrayLength: usize) void {
    const size = @min(u8ArrayLength, f32ArrayLength);
    for (u8Array[0..size]) |b, i| f32Array[i] = @intToFloat(f32, b) / 128.0 - 1;
}

/// generates 3 periods of each note starting near middle c (256hz, 0xf7)
/// each time it generates 3 periods, it increases the hz until it loops
export fn sfxBuffer(u8Array: [*]u8, u8ArrayLength: usize) void {
    
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

    print_("Generating array");
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

