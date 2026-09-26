// --------------------------------------------------------------------------
// JOUST -- Atari Corp. 1986, adapted for the ST by The Rugby Circle, Inc.
// (the arcade game: Williams Electronics 1982). The whole game, playable, 1 or
// 2 players.
//
// A PORT OF THE PROGRAM, NOT A REMAKE. The machine state is JOUST.PRG's own
// memory (its TEXT relocated at $10000, the BSS, the ST screen at $F8000), and
// every routine is a transcription of the reference model (a Python model of
// the 68000 code that matches the real program on every frame of seven
// recorded games, RAM, screen, registers and CPU cycles): joust/*.zig, one
// module per part of the program -- riders_*/eggs* (the riders, the
// eggs), ai*/coll* (enemy steering, the joust), hazards_* (lava, flames,
// pterodactyls, the troll, the spawn pads), flow_* (input, scores, waves,
// GAME OVER, the name entry), and title/boot (the title and the start-up,
// transcribed from the 68000 in the same way). The RNG walks the program's
// own bytes, which is why the image sits where the original loaded it.
//
// PACING. JOUST has no Vsync: a frame takes as many 50 Hz VBLs as its 68000
// cycles need, ~31 fps down to ~20 fps with a full screen. Every routine
// counts its cycles and the pacer (joust/pacing.zig) adds the OS interrupts;
// the machine runs a frame when the ST's clock, derived from the host's
// elapsed time, has reached it. The original's speed, variable as it was.
//
// CONTROLS. The ST's joysticks: P1 = the arrow keys, fire = Enter (or 0);
// P2 = W A S D, fire = Space. With one player, W A S D and Space drive P1
// too. On the title: 1 or 2 (or fire). P pauses (any key resumes), R
// restarts, and the high-score name is typed on the keyboard, Return ends it.
// ^C left the original; Escape leaves here.
//
// SOUND. The game's 16 Dosound scripts and the start-up siren, played by
// joust_sfx.sndh (apps/zig/assets/screens/joust/sfx.s): each script the game
// starts requests that subtune. The game itself runs TOS's Dosound
// interpreter inside the machine, because it reads the chip back.
//
// HIGH SCORE. HIGH.SCO seeds it; a new one lives in the machine's memory for
// as long as the cart runs (the original wrote the file on ^C).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const State = @import("joust/state.zig");
const machine = @import("joust/machine.zig");
const screen = @import("joust/screen.zig");
const keys = @import("joust/keys.zig");
const testapi = @import("joust/testapi.zig");

const MUSIC = "joust_sfx.sndh";
const PLANE = 0;
/// XBIOS Random's seed at power-on: TOS's LCG as the harness seeds it.
const SEED: u32 = 0x4A0057;
/// 8021247 Hz / (512 x 313): the PAL ST's 50.053 Hz, in micro-VBLs per us.
const CPU_HZ: u64 = 8021247;
const VBL_CYC: u64 = 512 * 313;
/// A stalled host (a background tab) does not fast-forward the game.
const MAX_BEHIND: i64 = 6;
/// One host frame never counts for more than this.
const MAX_FRAME_US: u64 = 250_000;

const K_ESC: u32 = 0xE012;
const J_UP: u8 = 1;
const J_DOWN: u8 = 2;
const J_LEFT: u8 = 4;
const J_RIGHT: u8 = 8;
const J_FIRE: u8 = 0x80;

var g_demo: ?*Demo = null;

// This cart's own wasm exports: the key RELEASE (the loader calls a cart's
// keyUp when it exports one; demo_main forwards none) and the headless
// harness's door (joust/testapi.zig). cart.zig only analyses the scene its comptime index
// selects; the guard keeps the exports in JOUST's cart even if this file is
// ever imported from elsewhere.
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        @export(&keyUpExport, .{ .name = "keyUp" });
        @export(&testapi.reset, .{ .name = "joustTestReset" });
        @export(&testapi.key, .{ .name = "joustTestKey" });
        @export(&testapi.frame, .{ .name = "joustTestFrame" });
        @export(&testapi.nudge, .{ .name = "joustTestNudge" });
        @export(&testapi.hash, .{ .name = "joustTestHash" });
        @export(&testapi.val, .{ .name = "joustTestVal" });
        @export(&testapi.screenPtr, .{ .name = "joustTestScreenPtr" });
        @export(&testapi.palPtr, .{ .name = "joustTestPalPtr" });
        @export(&testapi.sfxClear, .{ .name = "joustTestSfxClear" });
    }
}

fn keyUpExport(cp: u32) callconv(.c) void {
    const d = g_demo orelse return;
    d.keyUp(cp);
}

pub const Demo = struct {
    // demo_main holds the cart as `undefined`: every field is set in init().
    m: machine.Machine,
    clock_us: u64,
    /// VBLs the host has let pass without running (stalls), subtracted
    skipped: i64,
    arrows: u8, // P1: the arrow keys
    wasd: u8, // P2: W A S D
    fire1: bool, // Enter / 0
    fire2: bool, // Space
    held: u128, // the character keys down now
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.clock_us = 0;
        self.skipped = 0;
        self.arrows = 0;
        self.wasd = 0;
        self.fire1 = false;
        self.fire2 = false;
        self.held = 0;
        self.wants_quit = false;
        self.m.reset(SEED);
        g_demo = self;
        testapi.m = &self.m;
        testapi.lockstep = false;
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.clearFrameBuffer(0);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        if (testapi.lockstep or self.wants_quit) return;
        if (std.math.isFinite(dt) and dt > 0) {
            const us: u64 = @intFromFloat(@min(@as(f64, dt) * 1000.0, @as(f64, MAX_FRAME_US)));
            self.clock_us += us;
        }
        // the ST's VBL count at this host moment
        // (in u128: clock_us x CPU_HZ passes u64 after ~26 days of uptime, and
        // a wrapped clock would stall the game for good)
        var limit: i64 = @intCast(@as(u128, self.clock_us) * CPU_HZ / (VBL_CYC * 1_000_000));
        limit -= self.skipped;
        const vbl = self.m.st.pacer.vbl;
        if (limit > vbl + MAX_BEHIND) {
            self.skipped += limit - (vbl + MAX_BEHIND);
            limit = vbl + MAX_BEHIND;
        }
        self.m.joy = self.joystick();
        self.m.run(limit, false);
        self.sounds();
        if (self.m.mode == .quit) {
            self.wants_quit = true;
            zg.stopSong();
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        screen.present(&self.m.st.pal, &zigos.lfbs[PLANE]);
    }

    /// The scripts the game started since the last host frame: the latest one
    /// is what the chip plays (its priority test already ran in the game).
    fn sounds(self: *Demo) void {
        const st = &self.m.st;
        if (st.sfx_n != 0) {
            const n = st.sfx_log[st.sfx_n - 1];
            zg.requestSongTune(MUSIC, n + 1);
            st.sfx_n = 0;
        }
    }

    /// The two joystick bytes the IKBD would report now: [P1 (port 1), P2 (port 0)].
    fn joystick(self: *Demo) [2]u8 {
        const typing = self.m.mode == .name_entry;
        const wasd: u8 = if (typing) 0 else self.wasd;
        const f1: u8 = if (self.fire1 and !typing) J_FIRE else 0;
        const f2: u8 = if (self.fire2 and !typing) J_FIRE else 0;
        var p1: u8 = self.arrows | f1;
        var p2: u8 = wasd | f2;
        if (self.m.st.g(State.V.two_player) == 0) { // one player: both sets drive P1
            p1 |= p2;
            p2 = 0;
        }
        return .{ p1, p2 };
    }

    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    /// The arrows arrive as directions, even for a cart that owns the keyboard.
    pub fn input(self: *Demo, dir: u8) void {
        self.arrows |= arrowBit(dir);
    }
    pub fn inputRelease(self: *Demo, dir: u8) void {
        self.arrows &= ~arrowBit(dir);
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) {
            self.wants_quit = true;
            zg.stopSong();
            return;
        }
        if (cp > 0x7F) return;
        const ch: u8 = @intCast(cp);
        // JOUST turns TOS's key repeat off (andi.b #$fc,$484): the host's
        // auto-repeat must not type a key twice
        const bitm = heldBit(ch);
        if (self.held & bitm != 0) return;
        self.held |= bitm;
        // the name entry and the pause read the keyboard: every key is a key there
        const typing = self.m.mode == .name_entry or self.m.mode == .pause;
        if (!typing and self.stick(ch, true)) return;
        if (typing) _ = self.stick(ch, true); // (tracked, so the release matches)
        const st = &self.m.st;
        st.pacer.addKey(st.pacer.t, keys.code(ch));
    }

    pub fn keyUp(self: *Demo, cp: u32) void {
        if (cp > 0x7F) return;
        const ch: u8 = @intCast(cp);
        self.held &= ~heldBit(ch);
        _ = self.stick(ch, false);
    }

    /// A joystick key: W A S D, Space, Enter, 0. True if it was one.
    fn stick(self: *Demo, ch: u8, down: bool) bool {
        const c = if (ch >= 'A' and ch <= 'Z') ch + 32 else ch;
        const b: u8 = switch (c) {
            'w' => J_UP,
            's' => J_DOWN,
            'a' => J_LEFT,
            'd' => J_RIGHT,
            else => 0,
        };
        if (b != 0) {
            if (down) self.wasd |= b else self.wasd &= ~b;
            return true;
        }
        switch (c) {
            ' ' => self.fire2 = down,
            13, '0' => self.fire1 = down,
            else => return false,
        }
        return true;
    }
};

/// A key's bit in `held`, one per KEY: the host reports the character, so a
/// Shift pressed or let go while the key is down releases 'W' after pressing
/// 'w'. Unfolded, the 'w' bit stayed set and every later W was dropped as a
/// repeat -- the stick went dead until the page lost focus.
fn heldBit(ch: u8) u128 {
    const c = if (ch >= 'A' and ch <= 'Z') ch + 32 else ch;
    return @as(u128, 1) << @intCast(c & 0x7F);
}

fn arrowBit(dir: u8) u8 {
    return switch (dir) {
        0 => J_UP,
        1 => J_DOWN,
        2 => J_LEFT,
        3 => J_RIGHT,
        else => 0,
    };
}
