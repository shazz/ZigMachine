// --------------------------------------------------------------------------
// NORTH & SOUTH ("Nord et Sud", Infogrames 1989): the BATTLE, playable.
//
// Ported from the original Atari ST program (ns.app on the game disk), through
// a Python reference model that was itself transcribed from the 68000 code and
// matches the real battle on every frame of 13 scripted battles (state, screen
// and sound). This port is a transcription of that model: the battle's state
// IS the game's own RAM (north_south/mem.zig), every routine keeps the 16-bit
// widths, wraps and RNG of the original, and apps/north_south_headless.mjs
// replays the scripts through the cart and compares every frame with it.
//
// Only the battle: the strategic map is out of scope, so a small front page
// (north_south/front.zig) picks what the map would have — the field (river,
// canyon, plain), who plays which side, the CPU level and the two armies —
// then calls the battle, shows the winner, and comes back.
//
// PACING. The original is not frame-locked: each battle frame ends by flipping
// the screen and waiting for the next VBL, so a frame lasts 2 to 9 50 Hz VBLs
// (3-4 typically) depending on what it drew and on the digi sound's interrupt
// load, and the whole battle slows down in a melee. north_south/pacing.zig is
// the model's cycle model of that; here a 50 Hz VBL counter runs off the
// host's elapsed time and a battle frame is run each time it has lasted its
// predicted number of VBLs.
//
// SOUND. Digitised samples played by a Timer A interrupt through the YM volume
// registers. A cart cannot write the YM, so docs/music/north_south_digi.sndh
// carries the original player (Timer A $417E + the VBL sequencer $49D4) and the
// bank; subtune n+1 plays sequence n, and a request cuts the current sound, as
// play_seq does (apps/zig/assets/screens/north_south/ns_digi.s).
//
// KEYS: see north_south/controls.zig. Escape is a game key (the Union's
// retreat), so F10 leaves; on the front page Escape leaves too.
//
// The game's graphics, sounds and design are Infogrames' (1989).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;

const G = @import("north_south/game.zig");
const setup = @import("north_south/setup.zig");
const front = @import("north_south/front.zig");
const controls = @import("north_south/controls.zig");
// This cart's own wasm exports: the key RELEASE (the loader calls a cart's
// keyUp when it exports one; demo_main forwards none) and the headless
// harness's door (north_south/testapi.zig). Only when this scene IS the cart:
// every cart's build analyses every scene file, and an export here would
// otherwise land in all of them.
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("north_south/testapi.zig");
        @export(&keyUp, .{ .name = "keyUp" });
    }
}

/// A key coming up (the same codes key() receives): WASD, F, Space, Z, /,
/// Escape and Backspace are HELD in the battle — the gauge fills while fire is
/// down and the shell leaves when it comes up.
fn keyUp(cp: u32) callconv(.c) void {
    keys.keyChange(cp, false);
}

pub const SOUND = "north_south_digi.sndh";
const PLANE = 0;
const K_F10: u32 = 0xE00A;

/// One ST VBL, in microseconds.
const VBL_US: u64 = 20_000;
/// A stalled tab catches up at most this many VBLs a frame.
const MAX_CATCH_UP: u64 = 10;
const MAX_FRAME_US: u64 = 1_000_000;
/// The dump's RNG state; the front page's time mixes into it (see start()).
const RNG_BASE: u32 = 0x6AED2AE2;
/// The winner stays up this long before the front page returns (VBLs).
const RESULT_VBLS: u64 = 250;

/// The battle. Module scope: its RAM image does not belong in the Demo struct.
pub var game: G.Game = undefined;
/// Module scope too, so the keyUp export can reach it without the Demo.
var keys: controls.Controls = undefined;

const Phase = enum { front, battle, result };

pub const Demo = struct {
    // demo_main holds the cart as `undefined`: every field is set in init().
    phase: Phase,
    menu: front.Front,
    clock_us: u64,
    vbls: u64, // VBLs run against that clock
    next_frame: u64, // the VBL the next battle frame starts at
    result_until: u64,
    redraw: bool,
    shown_dirty: bool,
    leave: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.phase = .front;
        self.menu.reset();
        keys.reset();
        self.clock_us = 0;
        self.vbls = 0;
        self.next_frame = 0;
        self.result_until = 0;
        self.redraw = true;
        self.shown_dirty = false;
        self.leave = false;
        zigos.setBackgroundColor(zg.Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        zigos.lfbs[PLANE].is_enabled = true;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        if (std.math.isFinite(dt) and dt > 0) {
            self.clock_us += @intFromFloat(@min(@as(f64, dt) * 1000.0, @as(f64, MAX_FRAME_US)));
        }
        const due = self.clock_us / VBL_US;
        var n: u64 = 0;
        while (self.vbls < due) : (n += 1) {
            if (n == MAX_CATCH_UP) {
                self.vbls = due;
                break;
            }
            self.vbl();
            self.vbls += 1;
        }
    }

    fn vbl(self: *Demo) void {
        switch (self.phase) {
            .front => {},
            .battle => if (self.vbls >= self.next_frame) self.battleFrame(),
            .result => if (self.vbls >= self.result_until) {
                self.phase = .front;
                self.redraw = true;
            },
        }
    }

    /// One iteration of the battle loop, then its predicted length in VBLs.
    fn battleFrame(self: *Demo) void {
        game.frame(keys.inputs(game.cfg.mode == 0));
        // One voice, and every play_seq cuts the last: the frame's last request wins.
        if (game.nevents > 0) zg.requestSongTune(SOUND, @intCast(game.events[game.nevents - 1] + 1));
        self.next_frame = self.vbls + game.pace.last_vbls;
        self.shown_dirty = true;
        if (game.result != 0) {
            self.phase = .result;
            self.result_until = self.vbls + game.pace.last_vbls + RESULT_VBLS;
            self.redraw = true;
        }
    }

    fn start(self: *Demo) void {
        // The RNG carries the map's history in the original; here the time
        // spent on the front page stands in for it.
        setup.start(&game, self.menu.options(RNG_BASE +% @as(u32, @truncate(self.vbls)) *% 2654435761));
        self.phase = .battle;
        self.next_frame = self.vbls;
        keys.reset();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        switch (self.phase) {
            .front => if (self.redraw) {
                self.menu.draw(zigos, fb);
                self.redraw = false;
            },
            .battle, .result => {
                if (self.shown_dirty) {
                    for (0..16) |i| fb.palette[i] = front.stColor(game.palette[i]);
                    front.present(game.shown(), fb);
                    self.shown_dirty = false;
                }
                if (self.phase == .result and self.redraw) {
                    banner(zigos, fb);
                    self.redraw = false;
                }
            },
        }
    }

    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_F10) {
            self.leave = true;
            return;
        }
        switch (self.phase) {
            .front => switch (cp) {
                controls.K_ESC => self.leave = true,
                ' ', controls.K_RETURN => if (self.menu.onStart()) self.start(),
                'w', 'W' => self.input(0),
                's', 'S' => self.input(1),
                'a', 'A' => self.input(2),
                'd', 'D' => self.input(3),
                else => {},
            },
            .battle => keys.keyChange(cp, true),
            .result => if (cp == ' ' or cp == controls.K_RETURN) {
                self.result_until = self.vbls;
            },
        }
    }

    /// Arrows (0 up, 1 down, 2 left, 3 right): the menu, or the Confederate stick.
    pub fn input(self: *Demo, dir: u8) void {
        switch (self.phase) {
            .front => {
                self.menu.move(dir);
                self.redraw = true;
            },
            .battle => keys.direction(dir, true),
            .result => {},
        }
    }

    pub fn inputRelease(self: *Demo, dir: u8) void {
        _ = self;
        keys.direction(dir, false);
    }

    pub fn pollCart(self: *Demo) i32 {
        if (!self.leave) return 0;
        self.leave = false;
        return -1; // back to the menu disk
    }
};

fn banner(zigos: *ZigOS, fb: *zg.LogicalFB) void {
    const text = if (game.result == 2) "  THE UNION WINS  " else "THE CONFEDERACY WINS";
    const x: i16 = @intCast(160 - @as(i32, @intCast(text.len)) * 4);
    for (84..116) |y| @memset(fb.fb[y * fb.stride + 64 ..][0..192], 0);
    zigos.printText(fb, text, x, 92, 14, 0);
    zigos.printText(fb, "SPACE: NEW BATTLE", 92, 104, 12, 0);
}
