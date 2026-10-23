// --------------------------------------------------------------------------
// CHONCHON 2 -- the olivierh59500 Go/Ebitengine re-creation
// github.com/olivierh59500/go-chonchon2, ported to the ZigMachine.
//
// The Go is a 320x200 palette-index picture at 50 TPS:
//
//   Screen <- Background                       (clock.Step)
//   Screen <- ribbon rows + sliding panels     (clock.Step)
//   Screen <- music meters                     (Update)
//   4-bit index <- Screen                      (clock.Pixels)
//   index <- sprite-a / sprite-b rows          (ImageSlots, opaque)
//   colour <- index==0 ? Background[y] :
//             index==2 ? Foreground[y] : Palette[index]   (the shader)
//
// This cart runs that on the ST's own hardware:
//   * clock.zig is the production's authored motion, statement for statement;
//   * meter.zig sets the meter cells' plane-0/1 words exactly where the Go does;
//   * compose.zig draws all of it in the chunky domain with CHISEL (BG and WORK
//     planes, one copy to the shown plane a tick); the planar screen lives on
//     only as the reference (reference.zig, the harness's screen exports);
//   * raster.zig rebuilds the two 200-word tables each tick, and the plane HBL
//     rewrites palette entries 0 and 2 on every one of the 200 visible lines --
//     a REAL raster, not a static palette;
//   * sprite-a.idx / sprite-b.idx are laid down as 80-pixel rows after the
//     screen decode, index 0 included, because every source pixel is opaque.
//
// MUSIC: the production ships seven replacement YM dumps (Mad Max / Jochen
// Hippel). Tracks 1..3 were matched register-for-register against SNDHs in
// docs/music (Jinks #1, lockbuster2_rollout #1/#2), and so was track 4,
// "Eliminator": so_watt_no_crew.sndh #1 equals its registers 0..10 on every one
// of 6000 frames. Track 7 is titled "Union Demo MENU" in its YM header, which is
// Mad Max's Alloy Run, the tune union_demo plays as union/alloy_run.sndh (the
// archive's Union_Demo/SID version; Matt's rule for Union Demo tunes is to pick
// them by name -- the dump's volumes equal the C64-Conversions Alloy_Run.sndh
// #1 on all 1500 frames compared, its periods 67-81% of audible frames).
// Tracks 5 ("Great Giana Sisters (ingame2)") and 6 (untitled, 2 digidrums)
// have NO SNDH in the archive: an exact-register scan of all 5897 files, every
// subtune, scores best 5.7% (Great_Giana_Sisters.sndh #5) and 1.7%
// (Wings_Of_Death.sndh #1), so they stay the last-resort .ymraw dumps
// (chonchon2_music-5/6.ymraw). The host player owns the chip in every
// case, so the cart advances its own embedded delta mirror for the meters and
// never calls zg.ymWrite.
//
// Space or Escape ends the intro, as the Go's Update returns Termination.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const assets = @import("assets.zig");
const clockmod = @import("clock.zig");
const compose = @import("compose.zig");
const gpu = @import("../chonchon/gpu.zig");
const rastermod = @import("raster.zig");
const ymod = @import("ym.zig");

const PLANE = 0;
const W: usize = zg.WIDTH; // 320
const H: usize = zg.HEIGHT; // 200

/// One 50 Hz frame. dt arrives in MILLISECONDS from the host.
const TICK_MS: f32 = 20.0;
/// A stalled tab steps at most this many 50 Hz ticks in one host frame.
const MAX_TICKS: u32 = 2;

const K_ESC: u32 = 0xE012;
const K_SPACE: u32 = 32;

const Track = struct { file: []const u8, tune: u8 };
/// F1..F7. Five SNDHs; the two tunes with no SNDH anywhere are requested as
/// .ymraw (see the header).
const TRACKS = [7]Track{
    .{ .file = "Jinks.sndh", .tune = 1 },
    .{ .file = "lockbuster2_rollout.sndh", .tune = 1 },
    .{ .file = "lockbuster2_rollout.sndh", .tune = 2 },
    .{ .file = "so_watt_no_crew.sndh", .tune = 1 },
    .{ .file = "chonchon2_music-5.ymraw", .tune = 0 },
    .{ .file = "chonchon2_music-6.ymraw", .tune = 0 },
    .{ .file = "union/alloy_run.sndh", .tune = 1 },
};

// --- module-scope state (the harness's window into the very words drawn) ----
pub var clock: clockmod.Live = undefined;
var g_gpu: gpu.Chisel = undefined;
pub var ym: ymod.Stream = undefined;
pub var meters: [3]u8 = .{ 0, 0, 0 };
pub var static_pal: [16]u32 = undefined; // the 16 ST words, Color.toRGBA order
pub var track: usize = 0;

// --------------------------------------------------------------------------
// The plane HBL -- the shader's per-line colour selection, on real hardware.
// Logical lines 0..199 on a normal plane: index 0 takes Background[y], index 2
// takes Foreground[y], every other index the static Palette[index].
// --------------------------------------------------------------------------
fn planeHbl(fb: *zg.LogicalFB, zigos: *ZigOS, line: u16, x: u16) void {
    _ = zigos;
    _ = x;
    const y: usize = line;
    if (y >= H) return;
    if (y == 0) {
        var i: usize = 0;
        while (i < 16) : (i += 1) fb.palette[i] = static_pal[i];
    }
    fb.palette[0] = rastermod.bg[y];
    fb.palette[2] = rastermod.fg[y];
}

// --------------------------------------------------------------------------
pub const Demo = struct {
    acc: f32,
    ok: bool,
    drawn: bool, // false only for the Go's never-drawn pre-first-Update state
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
        clock = clockmod.Live.init();
        ym.init();
        track = 0;
        meters = .{ 0, 0, 0 };
        rastermod.update(clock.tick, clock.old_y);

        const fb = &zigos.lfbs[PLANE];
        zigos.lfbs[gpu.BG].is_enabled = false; // surfaces: drawn, never composited
        zigos.lfbs[gpu.WORK].is_enabled = false;
        g_gpu.init(.{ fb, &zigos.lfbs[gpu.BG], &zigos.lfbs[gpu.WORK] });
        compose.initSurfaces(gpu.Chisel, &g_gpu);
        fb.is_enabled = true;
        for (0..16) |i| fb.palette[i] = static_pal[i];
        for (16..256) |i| fb.palette[i] = 0; // unused: transparent, never shown
        zigos.setBackgroundColor(Color.fromRGBA(static_pal[0]));
        fb.setFrameBufferHBLHandler(0, planeHbl);
        g_gpu.fill(gpu.SHOWN, 0, 0, W, H, 0); // nothing shown before the first Update

        zg.requestSongTune(TRACKS[0].file, TRACKS[0].tune);
        self.ok = true;
    }

    fn tick50(self: *Demo) void {
        clock.step();
        rastermod.update(clock.tick, clock.old_y);
        ym.step();
        meters = .{ ym.regs[8] & 15, ym.regs[9] & 15, ym.regs[10] & 15 };
        self.drawn = true;
        self.fresh = true;
    }

    pub fn selectTrack(self: *Demo, i: usize) void {
        _ = self;
        if (i >= TRACKS.len) return;
        track = i;
        ym.select(i);
        meters = .{ 0, 0, 0 };
        zg.requestSongTune(TRACKS[i].file, TRACKS[i].tune);
    }

    pub fn update(self: *Demo, _: *ZigOS, dt_ms: f32) void {
        if (!self.ok) return;
        // dt is HOST MILLISECONDS: keep it fractional (16.67 ms at 60 Hz) and
        // accumulate, or a 60 Hz host would run the 50 Hz demo slow.
        if (dt_ms > 0) self.acc = @min(self.acc + @min(dt_ms, 200.0), TICK_MS * @as(f32, @floatFromInt(MAX_TICKS)));
        var n: u32 = 0;
        while (self.acc >= TICK_MS and n < MAX_TICKS) {
            self.acc -= TICK_MS;
            n += 1;
            self.tick50();
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, _: f32) void {
        if (!self.ok) return;
        _ = zigos;
        // Before the first tick SHOWN keeps init's empty plane; after it, only
        // a tick changes the picture (a track switch zeroes the YM mirror, and
        // volume 0 is meter cell 0, which every frame already shows).
        if (!self.drawn or !self.fresh) return;
        compose.render(gpu.Chisel, &g_gpu, &clock, ym.regs);
        self.fresh = false;
    }

    pub fn key(self: *Demo, cp: u32) void {
        switch (cp) {
            K_ESC, K_SPACE => self.wants_quit = true,
            K_F1...K_F7 => self.selectTrack(cp - K_F1),
            else => {},
        }
    }

    pub fn pollCart(self: *Demo) i32 {
        return if (self.wants_quit) -1 else 0;
    }
};

const K_F1: u32 = 0xE001;
const K_F7: u32 = 0xE007;
