// Jochen Hippel's Amiga modules (.hip), played the way UADE plays them: the
// module's OWN 68000 replay routine, run on the SNDH player's Musashi, poking
// an emulated Paula (paula.zig) that drives the machine's four sample channels.
//
// A .hip as modland distributes it is a complete Amiga replay: the player code
// first, then the song ("TFMX" tag) and the instruments and samples. The code
// is position-independent (PC-relative throughout), so it runs wherever it is
// put; it writes Paula's registers directly ($DFF0A0..$DFF0DF, DMACON at
// $DFF096) and the CIA-A filter bit ($BFE001), and uses no interrupts (its init
// DISABLES the audio ones, INTENA = $0780). Its jump table:
//
//   +0  bra INIT    d0 = the song, from 1 (d0 = 0 sets the chip up and plays nothing)
//   +2  bra PLAY    once per vertical blank: 50 Hz on a PAL Amiga
//
// That is all the eagleplayer needs to know, and all this does. Why not a native
// replayer: the format's variants differ per game (Hippel rewrote his player for
// each), and running the game's own code is exact by construction.
const audio = @import("audio_hw");
const cpu = @import("sndh_player.zig");
const paula = @import("paula.zig");

const INIT: u32 = 0;
const PLAY: u32 = 2;
/// Samples between two PLAY calls: 44,100 / 50 Hz (the PAL Amiga's VBL).
const SAMPLES_PER_FRAME: u32 = 882;

fn staged(len: u32) []const u8 {
    const p: [*]const u8 = @ptrFromInt(audio.SONG_BASE);
    return p[0..len];
}

pub const recognise = @import("hip_format.zig").recognise;

pub const HipPlayer = struct {
    active: bool = false,
    loaded: bool = false,
    tune: u8 = 1,
    frame_acc: u32 = 0,
    /// Replay frames played since `start`: the tune's own clock.
    frames_played: u32 = 0,

    /// The file is staged at the start of song RAM (the 68000's RAM): check it
    /// is a Hippel module, then move it up to the image base, as an SNDH is.
    pub fn load(self: *HipPlayer, len: u32) bool {
        self.* = .{};
        paula.reset(false);
        if (!recognise(staged(len))) return false;
        if (!cpu.placeForeignImage(len)) return false;
        self.loaded = true;
        return true;
    }

    /// Start song `tune` (from 1; 0 = the first).
    pub fn start(self: *HipPlayer, tune: u8) void {
        if (!self.loaded) return;
        self.tune = if (tune == 0) 1 else tune;
        paula.reset(true);
        paula.clock = &cpu.cyclesIntoCall; // INIT and each PLAY start at the vertical blank
        self.active = cpu.callImage(INIT, self.tune, true);
        if (!self.active) paula.reset(false);
        self.frame_acc = 0;
        self.frames_played = 0;
    }

    /// Stop: every voice off. (The module's d0 = 0 INIT would do the same, but
    /// the voices must stop even when the code is no longer there.)
    pub fn stop(self: *HipPlayer) void {
        self.abandon();
    }

    /// Another file was staged over the image, or another player starts: stop
    /// without running any of the module's code.
    pub fn abandon(self: *HipPlayer) void {
        if (self.active or self.loaded) paula.reset(false);
        self.active = false;
        self.loaded = false;
    }

    pub fn positionMs(self: *const HipPlayer) u32 {
        return self.frames_played *% 20;
    }

    /// Render a block: PLAY every 882 samples, and the sub-blocks cut where a
    /// voice re-latches its pointer (paula.zig).
    pub fn renderStereo(self: *HipPlayer, frames: usize) void {
        const n: u32 = @intCast(@min(frames, audio.MAX_FRAMES));
        audio.machineClear(n);
        var off: u32 = 0;
        while (off < n) {
            if (self.frame_acc == 0) {
                if (!cpu.callImage(PLAY, 0, false)) {
                    self.abandon(); // ran away: stopped, not left to eat the audio thread
                    break;
                }
                self.frames_played +%= 1;
                self.frame_acc = SAMPLES_PER_FRAME;
            }
            const block = paula.samplesToLatch(@min(n - off, self.frame_acc));
            audio.machineMixPaula(off, block);
            paula.advance(block);
            self.frame_acc -= block;
            off += block;
        }
        audio.machineClamp(n);
    }
};
