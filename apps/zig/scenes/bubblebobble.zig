// --------------------------------------------------------------------------
// BUBBLE BOBBLE -- Taito 1986, the Atari ST version: Firebird 1987, Software
// Creations (code David J. Broadhurst, graphics Andrew R. Threlfall, music
// Tim & Mike Follin). The whole game: the title, the story, the hi-score table
// and its initials, the 100 rounds with every enemy, Baron von Blubba, the
// items, EXTEND, the secret rooms and the endings, one or two players at once.
//
// A PORT OF THE PROGRAM, NOT A REMAKE. BUBBLE.PRG's 68000 code is translated
// to Zig instruction for instruction (gen/, by tools/bubblebobble/st_recomp.py:
// 6,953 instructions, every one the program can reach) and runs on a model of
// the parts of the ST it uses (st/): the 68000's registers and flags, 512 KB
// of RAM with the game's data at the addresses it reads them (text.bin and
// the GRAPHICS\ files, tools/bubblebobble/rip_st.py), the Shifter, the MFP's
// Timer B, the IKBD, and the TOS calls it makes. prototypes/bubble_re/
// ANALYSIS.md says how the game works.
//
// PACING. The ST's 50.053 Hz frame, from the host's elapsed time: each frame
// is the VBL interrupt, the 200 lines of the picture (the game's Timer B
// rasters and its frame wait), and the game's code in between on a 68000
// cycle clock (st/frame.zig), so it runs at the speed it ran at.
//
// CONTROLS (keys.zig). Bub: the arrows, fire = Space / Enter. Bob: W A S D,
// fire = Tab / left Ctrl. 1 / 2 start one or two players, P pauses (the game's
// F1), Escape quits a game (F10) and, on the title, leaves the cart.
// Z toggles the ZIG MODE: the same game under a 24-bit copper sky (colour 0
// rewritten on every line by the plane's HBL where the game leaves it black).
//
// SOUND (sound.zig). bubble_bobble_st.sndh is the game's own driver and the
// Follins' MUSIC.DAT: each tune or effect the game's code starts is started
// on it, on the machine's 68000 SNDH player.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const k = @import("bubblebobble/st/cpu.zig");
const io = @import("bubblebobble/st/io.zig");
const tos = @import("bubblebobble/st/tos.zig");
const frame = @import("bubblebobble/st/frame.zig");
const assets = @import("bubblebobble/assets.zig");
const present = @import("bubblebobble/present.zig");
const keys = @import("bubblebobble/keys.zig");
const sound = @import("bubblebobble/sound.zig");

const PLANE = 0;
const CPU_HZ: u64 = 8021247;
/// A stalled host (a background tab) does not fast-forward the game.
const MAX_BEHIND: u64 = 6;
const MAX_FRAME_US: u64 = 250_000;

var g_demo: ?*Demo = null;

comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("bubblebobble/testapi.zig");
        @export(&keyUpExport, .{ .name = "keyUp" });
    }
}

fn keyUpExport(cp: u32) callconv(.c) void {
    const d = g_demo orelse return;
    _ = d.pad.key(cp, false);
}

/// Power-on: the game's memory, its data loaded, the 68000 at its entry.
pub fn powerOn() void {
    if (k.mem.len == 0) k.mem = zg.mem.mustAlloc(u8, k.RAM)[0..k.RAM];
    if (io.beam.len == 0) io.beam = std.mem.sliceAsBytes(zg.mem.mustAlloc(u32, 8000)[0..8000]);
    @memset(io.beam, 0);
    tos.files = &assets.files;
    sound.install();
    frame.reset(assets.text);
}

/// The title / attract loop (and the story after it), where Escape leaves the cart: the
/// title loop sets $58A on entry ($7CC6), the game clears it before its own loop ($14A).
pub fn onTitle() bool {
    return k.mem[frame.BASE + 0x58A] != 0;
}

pub const Demo = struct {
    clock_us: u64,
    skipped: u64,
    pad: keys.Pad,
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.clock_us = 0;
        self.skipped = 0;
        self.pad = .{};
        self.wants_quit = false;
        powerOn();
        g_demo = self;
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.clearFrameBuffer(0);
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
    }

    pub fn update(self: *Demo, _: *ZigOS, dt: f32) void {
        if (self.wants_quit) return;
        if (std.math.isFinite(dt) and dt > 0) { // the host's dt, once a frame: no per-pixel float
            const us: u64 = @intFromFloat(@min(@as(f64, dt) * 1000.0, @as(f64, MAX_FRAME_US)));
            self.clock_us += us;
        }
        var limit = self.hostVbls() -| self.skipped;
        if (limit > frame.frames + MAX_BEHIND) {
            self.skipped += limit - (frame.frames + MAX_BEHIND);
            limit = frame.frames + MAX_BEHIND;
        }
        var ran = false;
        while (frame.frames < limit and !tos.terminated) {
            frame.runFrame();
            sound.sync();
            ran = true;
        }
        if (ran) present.latch();
    }

    /// The host's time in the ST's 50 Hz VBLs.
    fn hostVbls(self: *const Demo) u64 {
        return @intCast(@as(u128, self.clock_us) * CPU_HZ / (io.FRAME_CYC * 1_000_000));
    }

    pub fn render(_: *Demo, zigos: *ZigOS, _: f32) void {
        present.present(&zigos.lfbs[PLANE]);
    }

    pub fn ownsKeyboard(_: *Demo) u32 {
        return 1;
    }

    pub fn input(self: *Demo, dir: u8) void {
        self.pad.arrow(dir, true);
    }
    pub fn inputRelease(self: *Demo, dir: u8) void {
        self.pad.arrow(dir, false);
    }
    pub fn input2(self: *Demo, dir: u8) void {
        self.pad.arrow2(dir, true);
    }
    pub fn inputRelease2(self: *Demo, dir: u8) void {
        self.pad.arrow2(dir, false);
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == keys.K_ESC and onTitle()) {
            self.wants_quit = true;
            sound.stop();
            return;
        }
        if (cp == 'z' or cp == 'Z') { // the ZIG mode: KESTREL's copper sky (present.zig)
            present.zig_mode = !present.zig_mode;
            return;
        }
        _ = self.pad.key(cp, true);
    }
};
