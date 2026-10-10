// --------------------------------------------------------------------------
// The SNDH player's native replays (digi.zig) and its three modes, which a
// screen picks with zg.requestSndhMode:
//
//   1  st      the tune's own 68000 code on Musashi
//   2  native  the recognised driver's routines in Zig: the same YM writes,
//              write for write (fpga/tests/test_sndh_native.py). The default.
//   3  pcm     native, with the samples on a PCM channel at the timer's rate
//              instead of through the YM's volume table: the "HQ" version.
//
// All three keep the tune's state where the 68000 keeps it, in its RAM, and
// share the SNDH player's clock and MFP: in mode 3 the timer interrupt still
// runs and still moves the sample pointer, only its three YM writes are left
// out. So a switch, either way and at any moment, carries on from the same
// sample. A tune with no native driver plays in mode 1 whatever is asked.
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const digi = @import("digi.zig");
const sndh = @import("sndh.zig");
const Driver = digi.beat_dis.Driver;

extern fn m68k_read_memory_8(address: c_uint) c_uint;
extern fn m68k_write_memory_8(address: c_uint, value: c_uint) void;
extern fn m68k_write_memory_16(address: c_uint, value: c_uint) void;

pub const Mode = enum(u32) { st = 1, native = 2, pcm = 3 };

/// Off: every tune on Musashi (the oracle's reference run, audioSndhNativeEnable).
pub var enabled: bool = true;
/// What the last load found (digi.Status), for the host to report.
pub var status: digi.Status = .musashi;
/// A deliberately wrong native replay, for the oracle to prove it would catch
/// one: 1 = the segment's end checked every interrupt, not every VBL. Test only.
pub var mutant: u32 = 0;

var driver: ?Driver = null; // what the image is, whatever the mode
var mode: Mode = .st;

/// The 68000's bus, for the native routines: the same functions Musashi calls.
const Bus68 = struct {
    pub inline fn read8(a: u32) u8 {
        return @truncate(m68k_read_memory_8(a));
    }
    pub inline fn write8(a: u32, v: u8) void {
        m68k_write_memory_8(a, v);
    }
    pub inline fn write16(a: u32, v: u16) void {
        m68k_write_memory_16(a, v);
    }
};

/// A tune was just loaded at 68000 address `base`: which driver, and the mode.
pub fn recognise(image: []const u8, base: u32) void {
    pcmStop();
    const r = digi.recognise(image, base);
    status = r.status;
    driver = r.driver;
    mode = if (driver != null and enabled) .native else .st;
    if (driver != null and !enabled) status = .disabled;
}

/// No tune: a refused load must not leave the last one's driver armed.
pub fn forget() void {
    pcmStop();
    driver = null;
    status = .musashi;
    mode = .st;
}

/// One of INIT / EXIT / PLAY, natively if the mode says so. False: Musashi's.
pub fn call(entry: u32) bool {
    const d = driver orelse return false;
    if (mode == .st) return false;
    const was = digi.Access(Bus68).rd32(d.base + 0x2A);
    digi.beat_dis.call(Bus68, d, entry); // its INIT ignores d0
    if (entry == sndh.EXIT) {
        pcmStop();
    } else if (mode == .pcm and (entry == sndh.INIT or digi.Access(Bus68).rd32(d.base + 0x2A) != was)) {
        pcmStart(d); // a new segment
    }
    return true;
}

/// A timer interrupt to `handler`, natively if it is the driver's. False: Musashi's.
pub fn interrupt(handler: u32) bool {
    const d = driver orelse return false;
    if (mode == .st or handler != d.handler.addr) return false;
    if (mode == .pcm) {
        digi.handler.skip(Bus68, d.handler);
    } else {
        digi.handler.irq(Bus68, d.handler);
    }
    if (mutant == 1) digi.beat_dis.call(Bus68, d, sndh.PLAY);
    return true;
}

/// zg.requestSndhMode: the mode now in force, or 0 for a mode that does not
/// exist (refused: nothing changes). A tune with no native driver stays in 1.
pub fn setMode(m: u32) u32 {
    const want = if (m >= 1 and m <= 3) @as(Mode, @enumFromInt(m)) else return 0;
    const d = driver orelse return @intFromEnum(Mode.st);
    if (want == mode) return m;
    if (mode == .pcm) pcmStop();
    mode = want;
    if (want == .pcm) {
        for ([_]u16{ 8, 9, 10 }) |reg| { // the YM's volumes off: the channel plays instead
            Bus68.write16(0xFF8800, reg << 8);
            Bus68.write16(0xFF8802, 0);
        }
        pcmStart(d);
    }
    return m;
}

pub fn current() u32 {
    return @intFromEnum(mode);
}

// --- mode 3: the samples on a PCM channel ------------------------------------
const CH: u32 = 0; // ste_dma.zig's left channel: a digi tune does not use the DMA chip
const OVERSHOOT: u32 = 320; // the handler plays past `end` until the next 50 Hz play: <= 316 bytes
const TIMER_HZ: f32 = 2457600.0 / 4.0 / 39.0; // the driver's Timer A
const RAM_SIZE: u32 = @intCast(audio.SONG_CAP);

/// Play from the sample pointer to the segment's end and on as far as the
/// handler would, at the timer's rate; play() starts the next segment.
fn pcmStart(d: Driver) void {
    const m = digi.Access(Bus68);
    const pos = m.rd32(d.base + 0x2A) & 0xFF_FFFF;
    const end = m.rd32(d.base + 0x2E) & 0xFF_FFFF;
    if (pos >= RAM_SIZE) return pcmStop();
    const len = @min(@max(end + 1, pos) - pos + OVERSHOOT, RAM_SIZE - pos);
    audio.machinePaulaTrigger(CH, audio.songAddr(pos), len, 0, 0, 0.0);
    audio.machinePaulaSetStep(CH, @intFromFloat(TIMER_HZ / audio.SAMPLE_RATE * audio.FRAC_ONE));
    audio.machinePaulaSetVolume(CH, PCM_VOLUME);
}

fn pcmStop() void {
    audio.machinePaulaSetActive(CH, 0);
}

/// The PCM channel's level against the YM's: Beat Dis's first 20 s measure RMS
/// 3898 in mode 2 and 11164 in mode 3 at 1.0, so 0.35, here as 90/256 (the audio
/// core's volume grid, host/audio_regs.h zma_vol).
const PCM_VOLUME: f32 = 90.0 / 256.0;
