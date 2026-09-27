// --------------------------------------------------------------------------
// SKYSTRIKE -- Shadow Software 1990 (game and music Aaron Fothergill,
// graphics Adam Fothergill), a STOS BASIC game, from Automation Menu Disk
// 258. The whole game, playable: the title and its credits, the difficulty
// menu, the nine missions and their briefings, the world of 51 sectors and
// its layers of sky, the enemy fighters, the ground guns, trucks and ships,
// the newspaper at the end, the hall of fame and its name entry.
//
// A PORT OF THE PROGRAM, NOT A REMAKE. The disk holds the COMPILED program
// (STRVAP, Automation-packed, "Stos basic compiler V 1.0"); its source,
// SKYSTRKE.BAS, is in the STOS sources archive, and its strings and banks
// match the disk's byte for byte (the sprite bank is taken from the compiled
// program, which differs in 367 bytes). The tokenised source was detokenised
// into prototypes/skystrike_re/SKYSTRKE.LST, and every routine here is that
// listing's lines, named by their numbers (skystrike/*.zig). What STOS itself
// does -- sprites, zones, COLLIDE, SCREEN$, UNPACK, APPEAR, RND, FADE, the
// PSG commands, Maestro's samples -- was read out of the running program's
// RAM on Hatari and transcribed (see each module).
//
// PACING. STOS runs the program flat out and draws the sprites in its VBL:
// a main-loop pass took 3 VBLs on the ST (TIMER), so the game moves at the
// compiled code's speed, which clock.zig charges; the title's scroller runs
// 6.5 passes a VBL. The 50.053 Hz VBL is derived from the host's time.
//
// CONTROLS. The joystick: the arrows (up / down turn the plane, left /
// right the throttle; FIRE is Space, which is also the right mouse button
// the game reads as "mouse key = 2"): FIRE shoots, left + FIRE a bomb,
// right + FIRE a rocket. The keyboard as the game reads it: 0-9 throttle,
// U wheels, Esc bail out (Enter the ripcord, Space land), W wings, B turbo,
// C cluster, E extinguisher, R repair, A autoland, M main base, S launch,
// T turn round, F a new plane for a landed one (it costs one, line 68),
// P pause; F2-F10 their shortcuts. Escape on the title leaves the cart.
// Z switches ORIGINAL / ZIG. In ZIG, left Ctrl fires the guns, left Shift a
// rocket and Space drops a bomb (lands the chute when bailed out): one key
// for each chord (skystrike/zig_keys.zig).
//
// ZIG MODE (the default; skystrike/zig_*.zig, docs/ports/SKYSTRIKE.md):
// fullscreen, hardware-scrolled, no pause at a new screen, tracers, key help
// at P (skystrike/zig_settings.zig). SOUND. ORIGINAL: skystrike.sndh (sound.s:
// STOS's music, NOISE / VOLUME / ENVEL, Maestro's samples; zg.sndhCall). ZIG:
// a MOD per situation (zig_music.zig), effects over it (zg.sfxPlay), the
// engine on the idle YM (zg.ymWrite); Z swaps the music. The MODs (The Mod
// Archive, unmodified; docs/music/skystrike_music_CREDITS.txt): "Explore the
// sky" BLuRry 1994, ID 167145, CC BY-SA 4.0 (this file only:
// creativecommons.org/licenses/by-sa/4.0); "The Hawk's Claw" Drozerix 2022,
// ID 197917, Public Domain; "dog75" Songerson 2019, ID 190360, CC BY 4.0.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const machine = @import("skystrike/machine.zig");
const inp = @import("skystrike/input.zig");
const flow = @import("skystrike/flow.zig");
const testapi = @import("skystrike/testapi.zig");
const zig_view = @import("skystrike/zig_view.zig");
const zig_mode = @import("skystrike/zig_mode.zig");
const zig_testapi = @import("skystrike/zig_testapi.zig");
const zig_keys = @import("skystrike/zig_keys.zig");

const PLANE = 0;
const CPU_HZ: u64 = 8021247;
const VBL_CYC: u64 = 512 * 313;
const MAX_BEHIND: u64 = 6;
const MAX_FRAME_US: u64 = 250_000;

pub const K_ESC: u32 = 0xE012;
const K_F1: u32 = 0xE001;
const K_F10: u32 = 0xE00A;

var g_demo: ?*Demo = null;

comptime {
    if (@import("../cart.zig").Cart == Demo) {
        @export(&keyUpExport, .{ .name = "keyUp" });
        @export(&testapi.reset, .{ .name = "skyTestReset" });
        @export(&testapi.vbl, .{ .name = "skyTestVbl" });
        @export(&testapi.key, .{ .name = "skyTestKey" });
        @export(&testapi.stick, .{ .name = "skyTestStick" });
        @export(&testapi.val, .{ .name = "skyTestVal" });
        @export(&testapi.poke, .{ .name = "skyTestPoke" });
        @export(&testapi.ptr, .{ .name = "skyTestPtr" });
        @export(&testapi.refuse, .{ .name = "skyTestRefuse" });
        @export(&zig_testapi.setMode, .{ .name = "skyTestMode" });
        @export(&zig_testapi.capture, .{ .name = "skyTestCapture" });
    }
}

fn keyUpExport(cp: u32) callconv(.c) void {
    const d = g_demo orelse return;
    d.keyUp(cp);
}

/// A host key as the ST's: the character and scancode into the key buffer,
/// Space also the fire button; Z switches ORIGINAL / ZIG (zig_mode.zig).
pub fn hostKey(cp: u32) void {
    if (zig_keys.down(cp)) return;
    if (cp >= K_F1 and cp <= K_F10) return inp.push(0, @intCast(59 + cp - K_F1));
    if (cp == K_ESC) return inp.push(27, 1);
    if (cp > 255) return;
    const c: u8 = @intCast(cp);
    if (zig_mode.isToggle(c)) return zig_mode.toggle();
    if (c == ' ') inp.fire_down = true;
    inp.push(c, inp.scancodeOf(c));
}

/// A host key released: Space is the fire button; ZIG's weapon keys.
pub fn hostKeyUp(cp: u32) void {
    if (cp == ' ') inp.fire_down = false;
    zig_keys.up(cp);
}

pub const Demo = struct {
    clock_us: u64,
    skipped: u64,
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.clock_us = 0;
        self.skipped = 0;
        self.wants_quit = false;
        machine.alloc();
        machine.reset();
        zig_view.init(zigos);
        zig_mode.set(@import("skystrike/zig_settings.zig").default_zig);
        g_demo = self;
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
        var limit: u64 = @intCast(@as(u128, self.clock_us) * CPU_HZ / (VBL_CYC * 1_000_000));
        limit -|= self.skipped;
        if (limit > machine.vbls + MAX_BEHIND) {
            self.skipped += limit - (machine.vbls + MAX_BEHIND);
            limit = machine.vbls + MAX_BEHIND;
        }
        machine.run(limit);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = dt;
        zig_view.render(zigos);
    }

    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    /// The arrows: the joystick.
    pub fn input(self: *Demo, dir: u8) void {
        _ = self;
        stickBit(dir, true);
    }
    pub fn inputRelease(self: *Demo, dir: u8) void {
        _ = self;
        stickBit(dir, false);
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC and onTitle()) {
            self.wants_quit = true;
            zg.stopSong();
            return;
        }
        hostKey(cp);
    }

    pub fn keyUp(self: *Demo, cp: u32) void {
        _ = self;
        hostKeyUp(cp);
    }
};

fn stickBit(dir: u8, down: bool) void {
    const b: u8 = switch (dir) {
        0 => inp.UP,
        1 => inp.DOWN,
        2 => inp.LEFT,
        3 => inp.RIGHT,
        else => 0,
    };
    if (down) inp.stick |= b else inp.stick &= ~b;
}

/// The title's scroller is on (Escape leaves the cart there).
pub fn onTitle() bool {
    return flow.pc == .l2006 or flow.pc == .l2005;
}
