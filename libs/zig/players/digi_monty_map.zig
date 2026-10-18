// --------------------------------------------------------------------------
// Where Monty's driver keeps things: offsets from the SNDH image's start (the
// file's offsets). The driver was assembled at ORIG, so an absolute address A
// in its code is image offset A - ORIG + DRV.
// --------------------------------------------------------------------------

// Grazey's wrapper
pub const FIRST: u32 = 0xAA; // word: INIT has saved and relocated
pub const SAVE: u32 = 0x1CA; // 19 MFP bytes, a pad, then the vectors $94 $110 $114 $120 $134
pub const OLD_BASE: u32 = 0x2B8; // long: where the driver was assembled, then where it is
pub const PLAY_FLAG: u32 = 0x40C; // byte: PLAY sets it ($FF)

// the driver
pub const DRV: u32 = 0x40E;
pub const ORIG: u32 = 0x46A86;
pub const DRV_LEN: u32 = 0xB90; // to SAMPLES
pub const DRUM_END: u32 = 0x444; // long
pub const DRUM_CUR: u32 = 0x448; // long
pub const HANDLER: u32 = 0x44C; // Timer D
pub const DRUM_IDLE: u32 = 0x4D4; // word: $FFFF = no drum
pub const MOVEM: u32 = 0x516; // trigger's saved d7/a0/a1
pub const DRUM_START: u32 = 0x556; // 10 longs
pub const DRUM_STOP: u32 = 0x57E; // 10 longs
pub const YM: u32 = 0x5A6; // registers 0..12, written 12 down to 0
pub const MIXER: u32 = YM + 7;
pub const PERIODS: u32 = 0x5B6; // words
pub const ARPS: u32 = 0x676; // longs: arpeggio tables, speed byte before each
pub const VOICES: u32 = 0x70C; // four of VOICE bytes
pub const VOICE: u32 = 0x40;
pub const TICK: u32 = 0x80C; // byte: frames to the next row
pub const SPEED: u32 = 0x80D;
pub const NOISE: u32 = 0x80E;
pub const NOISE_OUT: u32 = 0x80F;
pub const MIX_MASK: u32 = 0x810;
pub const PLAY_CODE: u32 = 0x814;
pub const CMDS: u32 = 0x984; // 20 longs: commands $80..$93
pub const DRUMS_ON_C: u32 = 0x9F2; // byte: 1 = the drums own channel C
pub const ENVS: u32 = 0xCD8; // long: volume envelopes
pub const TRANSPOSE: u32 = 0xCDC;
pub const RUNNING: u32 = 0xCDE; // byte: the song is set up
pub const TMP: u32 = 0xCE0; // word: play's scratch
pub const PATTERNS: u32 = 0xCE2; // long
pub const FX_CODE: u32 = 0xCE6;
pub const DRUM_NO: u32 = 0xF92; // long, its low byte set by command $91
pub const BUSY: u32 = 0xF9A; // word
pub const MUTE: u32 = 0xF9C; // word
pub const SAMPLES: u32 = 0xF9E;
pub const SAMPLES_ORIG: u32 = 0x40500;
pub const MUSIC: u32 = 0x3A9E;
pub const MUSIC_ORIG: u32 = 0x60000;
pub const MUSIC_LEN: u32 = 0x500; // what INIT relocates
pub const MUSIC_TOP: u32 = 0x60D2A; // the highest song address it relocates

// a voice: offsets into its VOICE bytes
pub const V = struct {
    pub const FLAGS = 0x00; // b1 b2 slide, b3 bend, b5 envelope, b7 bend up, b0 toggles
    pub const PATTERN = 0x02; // long
    pub const TRACK = 0x06; // long
    pub const TRACK_POS = 0x0A; // long
    pub const SLIDE = 0x0E; // word
    pub const ARP_START = 0x10; // long
    pub const ARP = 0x14; // long
    pub const SLIDE_STEP = 0x18;
    pub const SLIDE_WAIT = 0x19;
    pub const ENV_SPEED = 0x1A;
    pub const ROW_WAIT = 0x1B;
    pub const ROW_LEN = 0x1C;
    pub const NOTE = 0x1D;
    pub const VOLUME = 0x1E;
    pub const ENV_WAIT = 0x1F;
    pub const ENV_POS = 0x20; // long
    pub const ENV = 0x24; // long
    pub const ENV_LEVEL = 0x28;
    pub const VIB_DEPTH = 0x29;
    pub const VIB_STEP = 0x2A;
    pub const VIB_POS = 0x2B;
    pub const VIB_MODE = 0x2C; // b6 on, b5 rising, b7 every other frame
    pub const NOISE_SET = 0x2D;
    pub const TIE = 0x2E;
    pub const MIX = 0x2F; // the channel's mixer bits
    pub const VIB_WAIT = 0x30;
    pub const VIB_GO = 0x31;
    pub const VIB_DELAY = 0x32;
    pub const BEND = 0x33;
    pub const ARP_SPEED = 0x34;
    pub const ARP_WAIT = 0x35;
    pub const EFX = 0x36; // b1 noise sweep, b2 decay
    pub const SWEEP = 0x37;
    pub const DECAY_WAIT = 0x38;
    pub const DECAY_SPEED = 0x39;
    pub const SHIFT = 0x3E; // word: the track's transpose
};
