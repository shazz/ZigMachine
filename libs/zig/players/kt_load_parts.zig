// --------------------------------------------------------------------------
// The parts of a .kt song music.c loads one at a time: an instrument
// (mus_load_instrument_RW), an FX bus (inner_load_fx) and a wavetable entry
// (load_wavetable_entry), field by field and version by version as upstream.
// --------------------------------------------------------------------------
const s = @import("kt_song.zig");
const rd = @import("kt_read.zig");
const Arena = @import("kt_arena.zig").Arena;
const bits = @import("kt_bits.zig");

/// mus_get_default_instrument.
fn defaults() s.Instrument {
    var i: s.Instrument = undefined;
    @memset(@as([*]u8, @ptrCast(&i))[0..@sizeOf(s.Instrument)], 0);
    i.flags = s.INST_DRUM | s.INST_SET_PW | s.INST_SET_CUTOFF;
    i.pw = 0x600;
    i.cydflags = 4; // CYD_CHN_ENABLE_TRIANGLE
    i.adsr = .{ .a = 2, .d = 24 };
    i.volume = s.MAX_VOLUME;
    i.base_note = s.MIDDLE_C;
    i.prog_period = 2;
    i.cutoff = 2047;
    i.slide_speed = 0x80;
    i.vibrato_speed = 0x20;
    i.vibrato_depth = 0x20;
    @memset(&i.program, 0xfffe); // MUS_FX_NOP
    return i;
}

fn adsr(r: *rd.Reader) rd.Error!s.Adsr4 {
    const b = try r.bytes(4);
    return .{ .a = b[0], .d = b[1], .s = b[2], .r = b[3] };
}

pub fn instrument(r: *rd.Reader) rd.Error!s.Instrument {
    var i = defaults();
    i.flags = try r.u32_();
    i.cydflags = try r.u32_();
    i.adsr = try adsr(r);
    i.sync_source = try r.u8_();
    i.ring_mod = try r.u8_();
    i.pw = try r.u16_();
    i.volume = try r.u8_();
    const steps = try r.u8_();
    if (steps > s.PROG_LEN) return error.BadSong; // upstream would write past program[]
    for (0..steps) |k| i.program[k] = try r.u16_();
    i.prog_period = try r.u8_();
    i.vibrato_speed = try r.u8_();
    i.vibrato_depth = try r.u8_();
    i.pwm_speed = try r.u8_();
    i.pwm_depth = try r.u8_();
    i.slide_speed = try r.u8_();
    i.base_note = try r.u8_();
    if (r.has(20)) i.finetune = try r.i8_();
    const name_len: u8 = if (r.has(11)) try r.u8_() else 16;
    if (name_len != 0) try r.skip(@min(name_len, 33));
    i.cutoff = try r.u16_();
    i.resonance = try r.u8_();
    i.flttype = try r.u8_();
    if (r.has(7)) {
        i.ym_env_shape = try r.u8_();
        i.buzz_offset = try r.i16_();
    }
    if (r.has(10)) i.fx_bus = try r.u8_();
    if (r.has(11)) {
        i.vib_shape = try r.u8_();
        i.vib_delay = try r.u8_();
        i.pwm_shape = try r.u8_();
    }
    if (r.has(18)) i.lfsr_type = try r.u8_();
    if (r.has(12)) i.wavetable_entry = try r.u8_();
    if (r.has(23)) {
        i.fm_flags = try r.u32_();
        i.fm_modulation = try r.u8_();
        i.fm_feedback = try r.u8_();
        i.fm_harmonic = try r.u8_();
        i.fm_adsr = try adsr(r);
    }
    if (r.has(25)) i.fm_attack_start = try r.u8_();
    if (r.has(23)) i.fm_wave = try r.u8_();
    if (!r.has(26)) { // ENVELOPE_SCALE: Uint8 arithmetic, wrapping as upstream's
        i.adsr.a *%= 2;
        i.adsr.d *%= 2;
        i.adsr.r *%= 2;
        i.fm_adsr.a *%= 2;
        i.fm_adsr.d *%= 2;
        i.fm_adsr.r *%= 2;
    }
    return i;
}

pub fn fx(r: *rd.Reader, f: *s.FxDef) rd.Error!void {
    f.* = .{};
    if (r.has(22)) {
        const len = try r.u8_();
        if (len != 0) try r.skip(@min(len, 33));
    }
    f.flags = try r.u32_();
    f.bit_drop = try r.u8_();
    f.chr_rate = try r.u8_();
    f.chr_min_delay = try r.u8_();
    f.chr_max_delay = try r.u8_();
    f.chr_sep = try r.u8_();
    const spread: u8 = if (!r.has(27)) try r.u8_() else 0;
    if (!r.has(21)) try r.skip(1); // padding
    const taps: usize = if (r.has(27)) s.RVB_TAPS else 8;
    for (f.taps[0..taps]) |*t| {
        t.delay = try r.u16_();
        t.gain = try r.i16_();
        if (r.has(27)) {
            t.panning = try r.u8_();
            t.flags = try r.u8_();
        } else {
            t.flags = 1;
            t.panning = if (spread > 0) 0 else 64; // CYD_PAN_LEFT : CYD_PAN_CENTER
        }
    }
    if (!r.has(27)) for (8..s.RVB_TAPS) |k| {
        const t = &f.taps[k];
        if (spread == 0) {
            t.* = .{ .flags = 0, .delay = 1000, .gain = @intCast(@import("kt_tables.zig").rvb_low_limit) };
        } else {
            const d: u32 = f.taps[k - 8].delay;
            t.* = .{ .flags = 1, .panning = 128, .delay = @intCast(@min(2000, d + d * spread / 2000)), .gain = f.taps[k - 8].gain };
        }
    };
    f.downsample = try r.u8_();
    f.crush_gain = if (r.has(19)) try r.u8_() else 128;
}

/// load_wavetable_entry: the entry's header, then its samples (raw before
/// version 15, bit-packed from 15) into the arena.
pub fn wave(r: *rd.Reader, e: *s.WaveEntry, arena: *Arena) rd.Error!void {
    e.flags = try r.u32_();
    e.sample_rate = try r.u32_();
    e.samples = try r.u32_();
    e.loop_begin = try r.u32_();
    e.loop_end = try r.u32_();
    e.base_note = try r.u16_();
    e.data = null;
    e.span = (e.loop_end -% e.loop_begin) *% 2048; // WAVETABLE_RESOLUTION
    e.span_inv = if (e.span > 1) @intCast((@as(u64, 1) << 32) / e.span) else 0;
    if (e.samples == 0) return;
    if (e.samples > 1 << 20) return error.BadWave;
    const out = arena.alloc(i16, e.samples) catch return error.TooLarge;
    if (!r.has(15)) {
        for (out) |*v| v.* = try r.i16_();
    } else {
        const size_bits = try r.u32_();
        const packed_bytes = try r.bytes((@as(usize, size_bits) + 7) / 8);
        // A stream that does not unpack leaves the entry with samples and no data, as upstream.
        if (!bits.unpack(packed_bytes, size_bits, out, (e.flags >> 3) & 3)) return;
    }
    e.data = out.ptr;
}
