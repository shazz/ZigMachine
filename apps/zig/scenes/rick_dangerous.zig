// --------------------------------------------------------------------------
// RICK DANGEROUS -- Core Design / Firebird 1989, the Atari ST game. The whole
// game, playable: the four levels (South America, Egypt, Schwarzendumpf
// Castle, the Missile Base), the title, the hall of fame and its name entry.
//
// A PORT OF THE PROGRAM, NOT A REMAKE. The machine state is the game's own
// memory -- the ST's first 512 KB, the tables, sprites and maps cut from the
// decrypted RICKST.PRG's entry image (tools/rick_dangerous/extract_assets.py)
// at the addresses the 68000 code reads them -- and every routine is a
// transcription of the reference model (prototypes/rick_re/model: a Python
// model of the 68000 code that matches the original on 98,706 recorded calls
// byte for byte): rick_dangerous/*.zig, one module per part of the program
// (rick_* Rick, enemy*/trap/actors the actors, world*/spawn/exit_call the
// world, draw/hud/screen/title/select/intro/hof/gameover the presentation,
// sound/player/music the sound driver).
//
// PACING. The loop is VBL-locked: a frame is the flip's VBL and the wait's,
// 25 Hz; the long calls (redraws, scrolls, the level end, GAME OVER, the
// title) take the VBLs the original's cycles take (clock.zig). The game runs
// on the ST's 50.053 Hz VBL clock, derived from the host's elapsed time, and
// stops at each VBL wait the host's time has not reached (game.zig).
//
// CONTROLS. The joystick: the arrow keys (or W A S D), fire = Enter (or 0).
// The ST keyboard as the game reads it: P pauses (P again resumes), Space
// swaps to the grey palette on the title, Escape restarts to the title
// during a game and leaves the cart on the title.
//
// SOUND. Every screen's music is an SNDH: rick_dangerous.sndh
// (apps/zig/assets/screens/rick_dangerous/sound.s) is the game's OWN sound
// driver (play_sound $34750, the tick $3488E, the Timer A digis) around Ben
// Daglish's player -- the archive's Rick_Dangerous.sndh bytes, Mug UK's rip,
// byte-identical to the game's RAM, extended with the front end the rip
// lacks. The tunes and the effects share that player's state, and a tune
// playing drops every effect: one image holds it all. Each play_sound the
// game makes that is not dropped requests its subtune 1 + id + 29 x v. The
// tunes: title = id 5 (the archive's subtune 5), the level 1-4 intros = ids
// 0-3 (subtunes 1-4), the completion = id 4 (tune 7, subtune 8), GAME OVER
// = id 6 (subtune 6), the timed bonus = id 7 (subtune 7).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const ram = @import("rick_dangerous/ram.zig");
const game = @import("rick_dangerous/game.zig");
const io = @import("rick_dangerous/io.zig");
const snd = @import("rick_dangerous/sound.zig");
const machine = @import("rick_dangerous/machine.zig");
const present = @import("rick_dangerous/present.zig");
const keys = @import("rick_dangerous/keys.zig");
const testapi = @import("rick_dangerous/testapi.zig");

const PLANE = 0;
const CPU_HZ: u64 = 8021247;
const VBL_CYC: u64 = 512 * 313;
/// A stalled host (a background tab) does not fast-forward the game.
const MAX_BEHIND: u64 = 6;
const MAX_FRAME_US: u64 = 250_000;

var g_demo: ?*Demo = null;

comptime {
    if (@import("../cart.zig").Cart == Demo) {
        @export(&keyUpExport, .{ .name = "keyUp" });
        @export(&testapi.buf, .{ .name = "rickTestBuf" });
        @export(&testapi.load, .{ .name = "rickTestLoad" });
        @export(&testapi.frame, .{ .name = "rickTestFrame" });
        @export(&testapi.val, .{ .name = "rickTestVal" });
        @export(&testapi.poke, .{ .name = "rickTestPoke" });
        @export(&testapi.irq, .{ .name = "rickTestIrq" });
        @export(&testapi.refuse, .{ .name = "rickTestRefuse" });
        @export(&testapi.sndBegin, .{ .name = "rickTestSndBegin" });
        @export(&testapi.sndTick, .{ .name = "rickTestSndTick" });
        @export(&testapi.sndPlay, .{ .name = "rickTestSndPlay" });
        @export(&testapi.memPtr, .{ .name = "rickTestMemPtr" });
        @export(&testapi.palPtr, .{ .name = "rickTestPalPtr" });
        @export(&testapi.vbase, .{ .name = "rickTestVbase" });
    }
}

fn keyUpExport(cp: u32) callconv(.c) void {
    const d = g_demo orelse return;
    d.keyUp(cp);
}

pub const Demo = struct {
    clock_us: u64,
    /// VBLs the host let pass without running (stalls).
    skipped: u64,
    pad: keys.Pad,
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.clock_us = 0;
        self.skipped = 0;
        self.pad = .{};
        self.wants_quit = false;
        ram.alloc(); // once per cart load
        machine.reset();
        g_demo = self;
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.clearFrameBuffer(0);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        if (io.lockstep or self.wants_quit) return;
        if (std.math.isFinite(dt) and dt > 0) {
            const us: u64 = @intFromFloat(@min(@as(f64, dt) * 1000.0, @as(f64, MAX_FRAME_US)));
            self.clock_us += us;
        }
        var limit: u64 = @intCast(@as(u128, self.clock_us) * CPU_HZ / (VBL_CYC * 1_000_000));
        limit -|= self.skipped;
        if (limit > game.vbls + MAX_BEHIND) {
            self.skipped += limit - (game.vbls + MAX_BEHIND);
            limit = game.vbls + MAX_BEHIND;
        }
        machine.run(limit);
        snd.log_n = 0;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = dt;
        present.present(&zigos.lfbs[PLANE]);
    }

    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    /// The arrows arrive as directions, even for a cart that owns the keyboard.
    pub fn input(self: *Demo, dir: u8) void {
        self.pad.arrow(dir, true);
    }
    pub fn inputRelease(self: *Demo, dir: u8) void {
        self.pad.arrow(dir, false);
    }

    pub fn key(self: *Demo, cp: u32) void {
        const on_title = machine.onTitle();
        const fresh = self.pad.key(cp, true);
        if (cp == keys.K_ESC and fresh and on_title) {
            self.wants_quit = true;
            zg.stopSong();
        }
    }

    pub fn keyUp(self: *Demo, cp: u32) void {
        _ = self.pad.key(cp, false);
    }
};
