// --------------------------------------------------------------------------
// LOCKBUSTER 2 -- the second Lockbuster intro, "for DMA"(1989), the Atari ST
// demo that the Go production github.com/olivierh59500/go-lockbuster2
// ("Lockbuster 2 Go / DMA / 1989") re-created from the original executable.
// This cart is that production, ported to the ZigMachine: the six native
// scroll engines (lockbuster2/engine.zig, transcribed from the Go clock and
// pinned by the Go tree's own RAM checkpoints of the REAL machine), the two
// title slides, the per-line rasters and the toggles the demo itself explains
// in its scrolltext (message-3: "PRESS: F1 GOLD TEXT, F2 METAL TEXT, F3 COLOR
// TEXT, F4 BLACK TEXT, F5 NEW HBL, F6 OLD HBL").
//
// ONE PLANE, THREE COLOUR SOURCES -- exactly the Go shader's decomposition:
//
//   1. The UP/LINE raster: the engine's nibble-0 pixels change colour every
//      OTHER line (the demo rewrote colour register 0 for 100 HBL words over
//      200 lines, which is why the Go shader reads Rasters[y/2]). ST palette
//      entry 0's copper table carries the words of raster-old/new; rows past
//      the table are 0 = black, and the LAST bank rows are black, so the
//      lower half of the screen sits behind the black glyph band. The glass
//      is REAL RASTERS not pixel bars, borders included: entry 0 IS the
//      border's colour on an ST, so the global HBL copies the same table into
//      REG_BACKGROUND per physical line (garfield's borderHbl), and the bars
//      run edge to edge without the plane ever being oversized (wex's rule:
//      the raster runs in the SAME register on both sides of the screen).
//      The background stays black where the table has no words (below line
//      200 and in the top/bottom border bands, i.e. lines 0..39 and 240..279
//      of the physical raster), so the closed border never lies about colour.
//   2. The colour-1 raster, only when ColorText (F3): the Go shader indexed
//      Rasters[row + 9] for ink pixels -- an HBL write of colour 1 nine rows
//      later than colour 0's, and the demo's own per-line ink raster. Entry
//      1 otherwise holds its static palette word (0, black: the metallic
//      glyphs' premise).
//   3. The 16 static palette words (metal vs gold), which indexes 2..15 take:
//      the copper changes NOTHING about them (they are not per line).
//
// THE ENGINE RUNS ON CHISEL (lockbuster2/chunky.zig). The original moves
// planar bytes; every one of its moves is an 8-px span of all four planes, so
// the chunky engine does the same work as ~20-80 blits a tick between two
// DISABLED planes (the ring's two buffers) and one CHISEL copy onto the shown
// plane: no per-pixel CPU stores at all (the planar expansion it replaces was
// 64,000 stores a frame, more than the board's whole frame of DDR writes).
// engine.zig stays the reference model: chunky_test.zig proves the two equal on
// every tick, and the harness re-proves it on the real machine's blitter.
// Palette, copper tables and border table are rewritten only when a toggle
// changes them.
//
// CONTROLS. F1 gold / F2 metallic text, F3 coloured / F4 black text
// background, F5 new / F6 old HBL table. Space or Escape leaves to the menu
// (the Go demo ends the app on them; a ZigMachine screen hands back to the
// menu instead).
//
// MUSIC: Mad Max's "Rollout" rolls n its own SNDH subtune 1.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const engine_mod = @import("lockbuster2/engine.zig");
const chunky = @import("lockbuster2/chunky.zig");
const colors = @import("lockbuster2/colors.zig");
const ChiselGpu = @import("lockbuster2/chisel_gpu.zig").ChiselGpu;
const reference = @import("lockbuster2/reference.zig");
const Engine = chunky.Engine(ChiselGpu);

// MUSIC (CLAUDE.md: an SNDH, not a YM dump). The production plays music.ym --
// LHA "ROLLOUT1.YM", self-titled "Rollout Tune 1" by Jochen Hippel (= Mad
// Max), YM6 by LeOnArD, 1999 rip. The archive's own Rollout.sndh is the same
// two-tune image: Mad_Max/Games/Rollout.sndh (the Games/SID/ variant is
// ~abdy STE-DMA and plays SILENCE here, the exact trap
// replicants_emlyn documented). Subtune 1 is "Tune 1", the side the demo
// carries; apps/sndh_headless.mjs PASSes both subtunes on the sealed YM.
const MUSIC = "lockbuster2_rollout.sndh";
const MUSIC_TUNE: u8 = 1;

const PLANE = 0; // the shown plane; planes 1 and 2 hold the ring, disabled

const K_ESC: u32 = 0xE012;
const K_F1: u32 = 0xE001;
const K_F2: u32 = 0xE002;
const K_F3: u32 = 0xE003;
const K_F4: u32 = 0xE004;
const K_F5: u32 = 0xE005;
const K_F6: u32 = 0xE006;
const K_SPACE: u32 = 32;

/// One host frame steps at most this many 50 Hz engine VBLs, so a stalled tab
/// never replays a minute of the intro on real time (naos_nitrowave's pacing).
/// Integer microseconds: the host's f32 dt is converted once a frame.
const VBL_US: u32 = 20_000;
const MAX_VBLS: u32 = 6;

/// The engine, its CHISEL backend, and the exports the harness holds them by.
var g_gpu: ChiselGpu = undefined;
var g_engine: Engine = undefined;
var g_plane: [*]const u8 = undefined;
var g_ready = false;

/// The shown plane: 320x200 palette indices, i.e. the original's screen
/// memory expanded (the harness packs it back to the planar bytes the Go
/// tree's checkpoints hash). 0 = not ready, never dereferenced.
fn planeExport() callconv(.c) u32 {
    if (!g_ready) return 0;
    return @intFromPtr(g_plane);
}

/// The planar reference engine at the shown engine's tick (reference.zig);
/// 0 when it cannot be had. Harness only.
fn refScreenExport() callconv(.c) u32 {
    if (!g_ready) return 0;
    const s = reference.screenAt(g_engine.tick) orelse return 0;
    return @intFromPtr(s.ptr);
}

/// phase(0..7) | gold<<19 | color_text<<20 | new_raster<<21 | tag 0x6a<<22.
fn stateExport() callconv(.c) u32 {
    if (!g_ready) return 0;
    const p: u32 = @intCast(@mod(g_engine.phase, engine_mod.MAX_PHASES));
    return p |
        (@as(u32, @intFromBool(g_engine.gold)) << 19) |
        (@as(u32, @intFromBool(g_engine.color_text)) << 20) |
        (@as(u32, @intFromBool(g_engine.new_raster)) << 21) |
        (0x6A << 22);
}

fn tickExport() callconv(.c) u32 {
    if (!g_ready) return 0;
    return @intCast(g_engine.tick);
}

comptime {
    if (@import("../cart.zig").Cart == Demo) {
        @export(&planeExport, .{ .name = "lb2Plane" });
        @export(&refScreenExport, .{ .name = "lb2RefScreen" });
        @export(&stateExport, .{ .name = "lb2State" });
        @export(&tickExport, .{ .name = "lb2Tick" });
    }
}

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    ok: bool,
    acc_us: u32,
    /// The toggles the colours were last built for (0xFF = never).
    shown: u8,
    /// demo_main polls this to hand the screen back to the menu (Space/Escape).
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // A cart's Demo arrives zeroed: every field set here, never by default.
        self.ok = false;
        self.acc_us = 0;
        self.shown = 0xFF;
        self.wants_quit = false;

        const fb = &zigos.lfbs[PLANE];
        zigos.lfbs[1].is_enabled = false; // the ring: drawn, never composited
        zigos.lfbs[2].is_enabled = false;
        g_gpu.init(.{ fb, &zigos.lfbs[1], &zigos.lfbs[2] });
        g_engine.init(&g_gpu); // zeroes all three surfaces with CHISEL fills
        g_plane = fb.fb;
        g_ready = true;

        zigos.setBackgroundColor(colors.BLACK);
        fb.is_enabled = true;
        colors.install(zigos, fb);
        zg.requestSongTune(MUSIC, MUSIC_TUNE);
        self.ok = true;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        _ = self;
        // The engine steps in render(), with the tables it drives: update()
        // owns nothing of its own state (the demo moves only on its VBLs).
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        if (!self.ok) return;
        const dt_us: u32 = @intFromFloat(std.math.clamp(dt, 0, 1000) * 1000);
        self.acc_us = @min(self.acc_us + dt_us, VBL_US * MAX_VBLS);
        var stepped = false;
        while (self.acc_us >= VBL_US) : (self.acc_us -= VBL_US) {
            g_engine.step();
            stepped = true;
        }
        if (stepped) g_engine.present(); // one CHISEL copy: the front ring onto the plane
        const now = colors.toggles(g_engine.gold, g_engine.color_text, g_engine.new_raster);
        if (now != self.shown) {
            colors.refresh(&zigos.lfbs[PLANE], now, self.shown);
            self.shown = now;
        }
    }

    /// F1..F6 exactly as the demo's own scrolltext advertises them. Declaring
    /// key() owns every key, so Escape is honoured here and hands back to the
    /// menu (the contract demo_main.zig spells out); the original demo ended
    /// the program on Space too, and Space here does the same as Escape.
    pub fn key(self: *Demo, cp: u32) void {
        switch (cp) {
            K_F1 => g_engine.gold = true,
            K_F2 => g_engine.gold = false,
            K_F3 => g_engine.color_text = true,
            K_F4 => g_engine.color_text = false,
            K_F5 => g_engine.new_raster = true,
            K_F6 => g_engine.new_raster = false,
            K_ESC, K_SPACE => self.wants_quit = true,
            else => {},
        }
    }
};
