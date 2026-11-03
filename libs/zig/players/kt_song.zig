// --------------------------------------------------------------------------
// The klystrack (.kt) song, as klystron's music.h holds it after a load: the
// instruments, patterns, sequences, FX buses and wavetable entries that the
// BARD .kt player (kt.zig) sequences. Field widths are upstream's, because the
// player is bit-exact against upstream (kt_ref: apps/ports/klystrack/kt_ref):
// a Uint16 note that wraps must wrap here too.
// The arrays live in song RAM, after the file image (kt_load.zig places them).
// --------------------------------------------------------------------------

pub const VERSION_MAX: u8 = 27; // MUS_VERSION
pub const VERSION_MIN: u8 = 8; // packed patterns; older songs are refused
pub const MAX_CH: usize = 16; // channels played (upstream: 32); more is refused
pub const MAX_FX: usize = 8; // CYD_MAX_FX_CHANNELS
pub const MAX_WAVES: usize = 128; // CYD_WAVE_MAX_ENTRIES
pub const PROG_LEN: usize = 32; // MUS_PROG_LEN
pub const RVB_TAPS: usize = 16; // CYDRVB_TAPS
pub const MAX_VOLUME: u32 = 128;
pub const MIDDLE_C: u16 = 12 * 4;
pub const FREQ_TAB_SIZE: u16 = 96;

pub const NOTE_NONE: u8 = 0xff;
pub const NOTE_RELEASE: u8 = 0xfe;
pub const NO_INSTRUMENT: u8 = 0xff;
pub const NO_VOLUME: u8 = 0xff;

// MusInstrument.flags
pub const INST_PROG_SPEED_ABSOLUTE: u32 = 1;
pub const INST_DRUM: u32 = 2;
pub const INST_INVERT_VIBRATO_BIT: u32 = 4;
pub const INST_LOCK_NOTE: u32 = 8;
pub const INST_SET_PW: u32 = 16;
pub const INST_SET_CUTOFF: u32 = 32;
pub const INST_YM_BUZZ: u32 = 64;
pub const INST_RELATIVE_VOLUME: u32 = 128;
pub const INST_QUARTER_FREQ: u32 = 256;
pub const INST_WAVE_LOCK_NOTE: u32 = 512;
pub const INST_NO_PROG_RESTART: u32 = 1024;
pub const INST_MULTIOSC: u32 = 2048;

// MusStep.ctrl
pub const CTRL_LEGATO: u8 = 1;
pub const CTRL_SLIDE: u8 = 2;
pub const CTRL_VIB: u8 = 4;

// MusSong.flags
pub const SONG_ENABLE_MULTIPLEX: u32 = 4;

// CydFxSerialized.flags
pub const FX_REVERB: u32 = 1;
pub const FX_CRUSH: u32 = 2;
pub const FX_CHORUS: u32 = 4;
pub const FX_CRUSH_DITHER: u32 = 8;

// CydWavetableEntry.flags
pub const WAVE_LOOP: u32 = 1;
pub const WAVE_PINGPONG: u32 = 2;
pub const WAVE_NO_INTERPOLATION: u32 = 4;

pub const Adsr4 = extern struct { a: u8 = 0, d: u8 = 0, s: u8 = 0, r: u8 = 0 };

pub const Instrument = struct {
    flags: u32,
    cydflags: u32,
    adsr: Adsr4,
    sync_source: u8,
    ring_mod: u8,
    pw: u16,
    volume: u8,
    program: [PROG_LEN]u16,
    prog_period: u8,
    vibrato_speed: u8,
    vibrato_depth: u8,
    slide_speed: u8,
    pwm_speed: u8,
    pwm_depth: u8,
    base_note: u8,
    cutoff: u16,
    resonance: u8,
    flttype: u8,
    ym_env_shape: u8,
    buzz_offset: i16,
    fx_bus: u8,
    vib_shape: u8,
    vib_delay: u8,
    pwm_shape: u8,
    wavetable_entry: u8,
    lfsr_type: u8,
    finetune: i8,
    fm_flags: u32,
    fm_modulation: u8,
    fm_feedback: u8,
    fm_wave: u8,
    fm_harmonic: u8,
    fm_adsr: Adsr4,
    fm_attack_start: u8,
};

pub const Step = struct { note: u8, instrument: u8, ctrl: u8, volume: u8, command: u16 };

pub const Pattern = struct { steps: []Step };

pub const SeqEntry = struct { position: u16, pattern: u16, note_offset: i8 };

pub const RvbTap = struct { delay: u16 = 0, gain: i16 = 0, panning: u8 = 0, flags: u8 = 0 };

/// CydFxSerialized: what a song's FX bus is set to (mus_set_fx -> cydfx_set).
pub const FxDef = struct {
    flags: u32 = 0,
    bit_drop: u8 = 0,
    chr_rate: u8 = 0,
    chr_min_delay: u8 = 0,
    chr_max_delay: u8 = 0,
    chr_sep: u8 = 0,
    taps: [RVB_TAPS]RvbTap = [_]RvbTap{.{}} ** RVB_TAPS,
    downsample: u8 = 0,
    crush_gain: u8 = 0,
};

pub const WaveEntry = struct {
    flags: u32 = 0,
    sample_rate: u32 = 0,
    samples: u32 = 0,
    loop_begin: u32 = 0,
    loop_end: u32 = 0,
    base_note: u16 = 0,
    data: ?[*]const i16 = null,
    // The FM's modulus, the loop in phase units ((loop_end - loop_begin) * 2048, a Uint32 that
    // wraps as upstream's CydWaveAcc), and 2^32 / it: x % span by a multiply (kt_fm.zig).
    span: u32 = 0,
    span_inv: u32 = 0,
};

pub const Song = struct {
    num_channels: u8 = 0,
    song_length: u16 = 0,
    loop_point: u16 = 0,
    song_speed: u8 = 0, // changed by the song's own commands while it plays, as upstream's
    song_speed2: u8 = 0,
    song_rate: u8 = 0,
    flags: u32 = 0,
    multiplex_period: u8 = 0,
    pitch_inaccuracy: u8 = 0,
    master_volume: u8 = MAX_VOLUME,
    default_volume: [MAX_CH]u8 = [_]u8{MAX_VOLUME} ** MAX_CH,
    default_panning: [MAX_CH]i8 = [_]i8{0} ** MAX_CH,
    fx: [MAX_FX]FxDef = [_]FxDef{.{}} ** MAX_FX,
    instruments: []Instrument = &.{},
    patterns: []Pattern = &.{},
    sequences: [MAX_CH][]SeqEntry = [_][]SeqEntry{&.{}} ** MAX_CH,
    waves: []WaveEntry = &.{}, // MAX_WAVES entries (unused ones empty)
};
