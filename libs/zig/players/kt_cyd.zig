// --------------------------------------------------------------------------
// klystron's synth (cyd) as state: one CydChannel per song channel, with its
// three sub-oscillators, envelope, filter and FM modulator. The constants are
// cyddefs.h's with STEREOOUTPUT, LOWRESWAVETABLE and no oversampling (the
// klystrack cart's build, apps/ports/klystrack). Widths are upstream's: the
// player is bit-exact against it (kt_ref), so a Uint32 that wraps wraps here.
// Behaviour lives in kt_cyd_set.zig (setters), kt_adsr.zig, kt_osc.zig,
// kt_wave.zig, kt_fm.zig, kt_filter.zig and kt_synth.zig (a sample).
// --------------------------------------------------------------------------
const song = @import("kt_song.zig");

pub const OUTPUT_BITS = 16;
pub const ACC_BITS = 25; // 23 + MAX_OVERSAMPLE
pub const ACC_LENGTH: u32 = 1 << (ACC_BITS - 1);
pub const YM_LENGTH: u32 = ACC_LENGTH;
pub const WAVE_AMP: i32 = 1 << OUTPUT_BITS;
pub const WAVETABLE_RESOLUTION: u32 = 2048; // LOWRESWAVETABLE
pub const ENVELOPE_SCALE: u32 = 2;
pub const CYD_BASE_FREQ: u32 = 22050;
pub const RANDOM_SEED: u32 = 0xf31782ce;
pub const STEREO_GAIN: i32 = 2048;
pub const PAN_CENTER: u8 = 64;
pub const PAN_RIGHT: u8 = 128;
pub const SUB_OSCS = 3;

// CydChannel.flags (cyd.h)
pub const NOISE: u32 = 1;
pub const PULSE: u32 = 2;
pub const TRIANGLE: u32 = 4;
pub const SAW: u32 = 8;
pub const SYNC: u32 = 16;
pub const GATE: u32 = 32;
pub const KEY_SYNC: u32 = 64;
pub const METAL: u32 = 128;
pub const RING_MODULATION: u32 = 256;
pub const FILTER: u32 = 512;
pub const FX: u32 = 1024;
pub const YM_ENV: u32 = 2048;
pub const WAVE: u32 = 4096;
pub const WAVE_OVERRIDE_ENV: u32 = 8192;
pub const LFSR: u32 = 16384;
pub const FM: u32 = 32768;
pub const WAVEFORMS: u32 = NOISE | PULSE | TRIANGLE | SAW | WAVE | LFSR;

// CydAdsr.envelope_state
pub const ATTACK: u8 = 0;
pub const DECAY: u8 = 1;
pub const SUSTAIN: u8 = 2;
pub const RELEASE: u8 = 3;
pub const DONE: u8 = 4;

pub const YM_ENV_ATT: u8 = 1;
pub const YM_ENV_ALT: u8 = 2;

pub const FLT_LP: u8 = 0;
pub const FLT_HP: u8 = 1;
pub const FLT_BP: u8 = 2;

pub const Adsr = struct {
    volume: u8 = 0,
    envelope: u32 = 0,
    env_speed: u32 = 0,
    state: u8 = ATTACK,
    a: u8 = 0,
    d: u8 = 0,
    s: u8 = 0,
    r: u8 = 0,
};

pub const WaveState = struct {
    direction: u1 = 0, // 0 forward, 1 backward
    playing: bool = false,
    acc: u32 = 0,
    frequency: u32 = 0,
};

pub const Osc = struct {
    frequency: u32 = 0,
    accumulator: u32 = 0,
    random: u32 = RANDOM_SEED,
    lfsr: u32 = 0,
    lfsr_period: u32 = 0,
    lfsr_ctr: u32 = 0,
    lfsr_acc: u32 = 0,
    reg4: u32 = 1,
    reg5: u32 = 1,
    reg9: u32 = 1,
    wave: WaveState = .{},
};

pub const Filter = struct {
    f: i32 = 0,
    q: i32 = 0,
    p: i32 = 0,
    b0: i32 = 0,
    b1: i32 = 0,
    b2: i32 = 0,
    b3: i32 = 0,
    b4: i32 = 0,
};

pub const Fm = struct {
    flags: u32 = 0,
    feedback: u8 = 0,
    harmonic: u8 = 0,
    adsr: Adsr = .{},
    period: u32 = 0,
    accumulator: u32 = 0,
    wave_entry: ?*const song.WaveEntry = null,
    wave: WaveState = .{},
    fb1: u32 = 0,
    fb2: u32 = 0,
    env_output: u32 = 0,
    current_modulation: u32 = 0,
    attack_start: u8 = 0,
};

pub const Channel = struct {
    flags: u32 = 0,
    pw: u16 = 0x400,
    sync_source: u8 = 0,
    ring_mod: u8 = 0,
    flttype: u8 = 0,
    adsr: Adsr = .{},
    ym_env_shape: u8 = 0,
    panning: u8 = 0,
    gain_left: i32 = 0,
    gain_right: i32 = 0,
    sync_bit: u32 = 0,
    lfsr_type: u32 = 0,
    wave_entry: ?*const song.WaveEntry = null,
    subosc: [SUB_OSCS]Osc = [_]Osc{.{}} ** SUB_OSCS,
    flt: Filter = .{},
    fx_bus: u8 = 0,
    fm: Fm = .{},
};
