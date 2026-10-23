// --------------------------------------------------------------------------
// CHONCHON -- the olivierh59500 Go/Ebitengine re-creation
// github.com/olivierh59500/go-chonchon (a Chon-Chon / DMA intro), ported to the
// ZigMachine.
//
// The Go is a 320x200 palette-index picture at 50 TPS, built by a single
// "shader" over an index image and a palette:
//
//   Screen  <- Background                       (clock.Step)
//   Screen  <- stars | scroll ring | logo rows  (clock.Step)
//   Screen  <- Screen | meters                  (Update, plane-3 mask off meter-raw)
//   i       <- 4-plane decode of Screen         (Pixels)
//   i       <- logo-bank index where opaque     (ImageSlots over the index image)
//   colour  <- i>=8 && y>=144 ? Raster[(y-144)/2] : Palette[i]
//
// This cart plays that out on the ST's own hardware:
//
//   * the native motion (background + 100 authored star paths + the two-bank
//     ring scroller + the 63-row warped chrome logo) is `clock.zig`;
//   * the three music meters OR plane-3 bits into the screen (meter.zig);
//   * the index image is composed in the chunky domain with CHISEL
//     (chonchon/compose.zig: the background plane, only the planar groups a
//     tick changed, the logo rows as keyed blits, one copy to plane 0 a
//     tick; chonchon/chunky_test.zig proves it equals the per-pixel decode
//     of the planar screen on every tick), and the final colour
//     rule is a REAL per-scanline palette rewrite -- the shader's Raster on
//     lines 144..199 is entries 8..15 rewritten per line (CLAUDE.md: not a fake
//     raster), which is why the window carries more than the 16 static words.
//
// MUSIC (CLAUDE.md: an SNDH, not a YM dump). The production's music.ym is an
// LHa archive holding ROLLOUT2.YM, a YM6 dump of Jochen Hippel's (= Mad Max's)
// "Rollout" tune 2. The archive's Mad_Max/Games/Rollout.sndh subtune 2 plays
// the same tune: its tone periods over the first 1500 frames are the dump's 79
// distinct periods exactly (subtune 1: 0.30). docs/music/rollout.sndh is that
// file (md5 0e9aa3d6), already shipped for tcb_weirddream. The 68000 replay
// runs on the sound CPU (BARD on the board), not on the cart CPU. The three
// meters read the machine's live YM mirror (zigos.ym_regs), as gen4_3615's VU
// meters do.
//
// The Go quits on Space or Escape; this cart hands the screen back to the menu
// on either (demo_main's pollCart contract).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const assets = @import("chonchon/assets.zig");
const clockmod = @import("chonchon/clock.zig");
const metermod = @import("chonchon/meter.zig");
const compose = @import("chonchon/compose.zig");
const dirty = @import("chonchon/dirty.zig");
const gpu = @import("chonchon/gpu.zig");

const PLANE = 0;
const W: usize = zg.WIDTH; // 320
const H: usize = zg.HEIGHT; // 200

/// One 50 Hz frame. dt arrives in MILLISECONDS from the host.
const TICK_MS: f32 = 20.0;
/// A stalled tab steps at most this many 50 Hz ticks in one host frame.
const MAX_TICKS: u32 = 2;

const MUSIC = "rollout.sndh";
const MUSIC_TUNE: u8 = 2;

const K_ESC: u32 = 0xE012;
const K_SPACE: u32 = 32;

// --- module-scope state (the harness's window into the very words drawn) ----
pub var clock: clockmod.Clock = undefined;
/// The YM registers the meters read on the last tick (the harness pins them).
pub var ym_regs: [14]u8 = [_]u8{0} ** 14;
pub var meters: [3]u8 = .{ 0, 0, 0 };
/// The bar heights the last tick drew (its dirty meter groups).
var meter_h: [3]u8 = .{ 0, 0, 0 };
var g_gpu: gpu.Chisel = undefined;

var static_pal: [16]u32 = undefined; // the 16 ST words, Color.toRGBA order
var rast: [28]u32 = undefined; // Raster[(y-144)/2] for lines 144..199

// --------------------------------------------------------------------------
// The plane HBL -- the shader's per-line colour selection, on real hardware.
// Logical lines 0..199 on a normal plane (larcociel5's contract): entries 0..7
// stay the static palette, entries 8..15 become the Raster word for the line,
// so any pixel with i>=8 on rows 144..199 shows the raster colour.
// --------------------------------------------------------------------------
fn planeHbl(fb: *zg.LogicalFB, zigos: *ZigOS, line: u16, x: u16) void {
    _ = zigos;
    _ = x;
    const y: usize = line;
    // Only writes that change a register: entries 0..7 never change after
    // init, 8..15 go back to the static words on line 0, and a raster word
    // holds for two lines.
    if (y == 0) {
        var i: usize = 8;
        while (i < 16) : (i += 1) fb.palette[i] = static_pal[i];
    }
    if (y >= 144 and y < 200 and (y - 144) % 2 == 0) {
        const row = (y - 144) / 2;
        var i: usize = 8;
        while (i < 16) : (i += 1) fb.palette[i] = rast[row];
    }
}

// --------------------------------------------------------------------------
pub const Demo = struct {
    acc: f32,
    ok: bool,
    drawn: bool, // false only for the Go's empty boot frame
    /// A tick moved the picture since the last render (render composes then).
    fresh: bool,
    /// Space/Escape hand the screen back to the menu (the Go terminates on them).
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.acc = 0;
        self.ok = false;
        self.drawn = false;
        self.fresh = false;
        self.wants_quit = false;

        for (0..16) |i| static_pal[i] = assets.rgbw(assets.beWord(assets.palette_words, i * 2));
        for (0..28) |i| rast[i] = assets.rgbw(assets.beWord(assets.raster_words, i * 2));
        clock = clockmod.Clock.init();
        ym_regs = [_]u8{0} ** 14;
        meters = .{ 0, 0, 0 };
        meter_h = .{ 0, 0, 0 };

        const fb = &zigos.lfbs[PLANE];
        zigos.lfbs[gpu.BG].is_enabled = false; // surfaces: drawn, never composited
        zigos.lfbs[gpu.WORK].is_enabled = false;
        g_gpu.init(.{ fb, &zigos.lfbs[gpu.BG], &zigos.lfbs[gpu.WORK] });
        compose.initBackground(gpu.Chisel, &g_gpu);
        fb.is_enabled = true;
        for (0..16) |i| fb.palette[i] = static_pal[i];
        for (16..256) |i| fb.palette[i] = 0; // unused: transparent, never shown
        zigos.setBackgroundColor(Color.fromRGBA(static_pal[0]));
        fb.setFrameBufferHBLHandler(0, planeHbl);

        g_gpu.fill(gpu.SHOWN, 0, 0, W, H, 0); // the Go's boot frame: the index image is empty
        zg.requestSongTune(MUSIC, MUSIC_TUNE);
        self.ok = true;
    }

    fn tick50(self: *Demo, zigos: *const ZigOS) void {
        ym_regs = zigos.ym_regs[0..14].*;
        compose.tick(&clock, meter_h, ym_regs, metermod.apply);
        meter_h = dirty.meterHeights(ym_regs);
        self.fresh = true;
        meters = .{ ym_regs[8] & 15, ym_regs[9] & 15, ym_regs[10] & 15 };
        self.drawn = true;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt_ms: f32) void {
        if (!self.ok) return;
        // dt is HOST MILLISECONDS: keep it fractional (16.67 ms at 60 Hz) and
        // accumulate, or a 60 Hz host would run the 50 Hz demo slow.
        if (dt_ms > 0) self.acc = @min(self.acc + @min(dt_ms, 200.0), TICK_MS * @as(f32, @floatFromInt(MAX_TICKS)));
        var n: u32 = 0;
        while (self.acc >= TICK_MS and n < MAX_TICKS) {
            self.acc -= TICK_MS;
            n += 1;
            self.tick50(zigos);
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, _: f32) void {
        if (!self.ok) return;
        _ = zigos;
        // Before the first tick SHOWN keeps init's empty index image (Go frame
        // 0); after it, only a tick changes the picture.
        if (!self.drawn or !self.fresh) return;
        compose.render(gpu.Chisel, &g_gpu, &clock, meter_h);
        self.fresh = false;
    }

    pub fn key(self: *Demo, cp: u32) void {
        switch (cp) {
            K_ESC, K_SPACE => self.wants_quit = true,
            else => {},
        }
    }

    pub fn pollCart(self: *Demo) i32 {
        return if (self.wants_quit) -1 else 0;
    }
};

// The harness's exports exist only when this scene IS the registered cart.
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("chonchon/testapi.zig");
    }
}
