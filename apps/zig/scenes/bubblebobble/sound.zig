// --------------------------------------------------------------------------
// The game's sound, on the machine's SNDH player: bubble_bobble_st.sndh is the
// game's own driver and music (assets/.../sound.s). Every time the game's
// code calls its driver -- start tune ($A7AE, the tune in $AC06) or start
// effect ($AC12, the effect in $AC10) -- the translation tells hook() and the
// same call is made on the SNDH; the hurry flag ($AC08, tune 0 at full speed
// when Baron von Blubba comes) is followed once a frame (sync()).
//
// The first request loads the image (zg.requestSongTune); every later one is
// a zg.sndhCall on the running driver, so an effect plays over the tune as
// it did on the ST. The game's own copy of the driver keeps running in the
// cart, silent (st/io.zig drops its YM writes): the game waits on its
// end-of-jingle flag, so both copies play the same frames.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const k = @import("st/cpu.zig");
const frame = @import("st/frame.zig");

pub const SONG = "bubble_bobble_st.sndh";
const RESIDENT: u16 = 0x8000;
const OP_TUNE: u16 = 0x000;
const OP_EFFECT: u16 = 0x100;
const OP_HURRY: u16 = 0x200;
const SUBTUNE_SILENT: u8 = 10;

const START_TUNE: u32 = frame.BASE + 0xA7AE;
const START_EFFECT: u32 = frame.BASE + 0xAC12;
const TUNE: u32 = frame.BASE + 0xAC06;
const HURRY: u32 = frame.BASE + 0xAC08;
const EFFECT: u32 = frame.BASE + 0xAC10;

var loaded: bool = false;
var hurry: u8 = 0;
/// Requests made since power-on (the harness reads them).
pub var tunes: u32 = 0;
pub var effects: u32 = 0;
pub var last_tune: u8 = 0xFF;
pub var last_effect: u8 = 0;

pub fn install() void {
    loaded = false;
    hurry = 0;
    tunes = 0;
    effects = 0;
    last_tune = 0xFF;
    k.on_hook = hook;
}

fn hook(target: u32) void {
    if (target == START_TUNE) {
        const t = k.mem[TUNE];
        tunes += 1;
        last_tune = t;
        if (!loaded) {
            zg.requestSongTune(SONG, t + 1);
            loaded = true;
            hurry = 0;
            return;
        }
        _ = zg.sndhCall(SONG, RESIDENT | OP_TUNE | t);
    } else if (target == START_EFFECT) {
        const e = k.mem[EFFECT];
        effects += 1;
        last_effect = e;
        load();
        _ = zg.sndhCall(SONG, RESIDENT | OP_EFFECT | e);
    }
}

fn load() void {
    if (loaded) return;
    zg.requestSongTune(SONG, SUBTUNE_SILENT);
    loaded = true;
    hurry = 0;
}

/// After each frame: the hurry flag, when the game changed it.
pub fn sync() void {
    const h = k.mem[HURRY];
    if (h == hurry or !loaded) return;
    hurry = h;
    _ = zg.sndhCall(SONG, RESIDENT | OP_HURRY | h);
}

pub fn stop() void {
    zg.stopSong();
    loaded = false;
}
