// --------------------------------------------------------------------------
// DMA INTRO 2 -- "LARCOCIEL" (DMA, 1990), the olivierh59500 Go/Ebitengine
// re-creation github.com/olivierh59500/go-larcociel2, ported to the ZigMachine.
//
// The Go is a 320x200 palette-index picture at 50 TPS built by a single
// "palette shader" over three textures, and this cart is that shader played
// out on the ST's own hardware:
//
//   * background -- 36 full-screen index planes, one per tick, rolled
//                   (clock.Tick-1+36)%36. Only rows 143..199 animate; rows
//                   0..142 are the same in every frame, so those are stored
//                   once and the 57-row band 36 times (see assets.zig).
//   * balls      -- six 32x32 sprites projected from the accelerating trail
//                   clock (geometry.ProjectWordPoint: 205 scale, 205 depth
//                   bias, centre 160,80, zero depth hidden). Slot k samples
//                   History[k*11]; its atlas sprite is picked by Z>>5.
//   * scrolltext -- DCK's scrolling slice stream: 36 eight-pixel slots at
//                   x = 16+8i, each an 8-pixel column of a 32-wide atlas glyph.
//
// The Go's shader, verbatim, is exactly this decomposition (i = background):
//   ball.a>0 -> i = (i/4)*4 + ball;  text.a>0 -> i = i%8 + 8
//   i==8 && y<16 -> Raster[y/2];  i==4 && 49<=y<93 -> Raster[9+(y-49)/4];
//   else Palette[i]
// The two Raster rules are a colour register rewritten per scanline -- a REAL
// raster, not a fake one (CLAUDE.md) -- so `planeHbl` rewrites entry 8 on lines
// 0..15 and entry 4 on lines 49..92 (on the lines whose colour changes), and
// restores both below them.
//
// The plane is written incrementally (larcociel2/present.zig): a 50 Hz tick
// stores only the band words that changed, the old balls' boxes and the text
// rows; a host frame without a tick stores nothing. The full redraw it
// replaced (reference.zig) is pinned against it on every tick by
// present_test.zig.
//
// MUSIC (CLAUDE.md: an SNDH, not a YM dump). The Go's music.ym is a 1999 YM6
// recording (LeOnArD) of the intro playing David Whittaker's "Dogs of War"
// (1989): the real DMA_2.PRG (fujiology DMA_CONC/DMA_2.ZIP) holds the same
// replay and song bytes as Whittaker_David/Dogs_of_War.sndh (51% of its
// 16-byte chunks; the next file 26%), and subtune 1 reproduces the YM6's
// registers 0..10 EXACTLY on every one of 6000 frames (2 minutes; a 4-frame
// start offset), the other subtunes 0%. docs/music/dogs_of_war.sndh is that
// file. The 68000 replay runs on the sound CPU (BARD on the board), not on the
// cart CPU. (The Go also lets the arrow keys move the projection centre;
// that is an interactive extra, not part of the captured demo, so it is not
// reproduced.)
//
// The Go quits on Space or Escape; this cart hands the screen back to the menu
// on either (demo_main's pollCart contract).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const assets = @import("larcociel2/assets.zig");
const clockmod = @import("larcociel2/clock.zig");
const textmod = @import("larcociel2/text.zig");
const presentmod = @import("larcociel2/present.zig");

const PLANE = 0;

/// One 50 Hz frame. dt arrives in MILLISECONDS from the host.
const TICK_MS: f32 = 20.0;
/// A stalled tab steps at most this many 50 Hz ticks in one host frame.
const MAX_TICKS: u32 = 2;

const MUSIC = "dogs_of_war.sndh";
const MUSIC_TUNE: u8 = 1;

const K_ESC: u32 = 0xE012;
const K_SPACE: u32 = 32;

// --- module-scope state (the harness's window into the very words drawn) ----
pub var clock: clockmod.Clock = undefined;
pub var stream: textmod.Stream = undefined;
/// False only for the boot frame (the Go's tick 0: no balls, no text).
pub var shown_live: bool = false;
/// What the plane holds, and whether a tick has moved anything since.
var presenter: presentmod.Presenter = .{};
var pending: bool = false;

pub var static_pal: [16]u32 = undefined; // the 16 ST words, Color.toRGBA order
pub var rast: [20]u32 = undefined; // Raster[0..19], the two per-line ramps

// --------------------------------------------------------------------------
// The plane HBL -- the shader's per-line colour selection, on real hardware.
// Logical lines 0..199 on a normal plane (copper.zig's contract).
// --------------------------------------------------------------------------
fn planeHbl(fb: *zg.LogicalFB, zigos: *ZigOS, line: u16, x: u16) void {
    _ = zigos;
    _ = x;
    const y: usize = line;
    // i==8 && y<16 -> Raster[y/2], on entry 8.
    // Each ramp word holds 2 (entry 8) or 4 (entry 4) lines: the register is
    // written on the line its colour changes, never with the value it holds.
    if (y < 16) {
        if (y & 1 == 0) fb.palette[8] = rast[y >> 1];
    } else if (y == 16) {
        fb.palette[8] = static_pal[8];
    }
    // i==4 && 49<=y<93 -> Raster[9+(y-49)/4], on entry 4.
    if (y >= 49 and y < 93) {
        if ((y - 49) & 3 == 0) fb.palette[4] = rast[9 + ((y - 49) >> 2)];
    } else if (y == 93) {
        fb.palette[4] = static_pal[4];
    }
}

pub const Projection = presentmod.Projection;

/// The projected pose of ball slot `i` from the live clock (the harness's door).
pub fn slotInfo(i: usize) Projection {
    const p = clock.history[(i % 6) * 11];
    return presentmod.project(p[0], p[1], p[2]);
}

fn planeWords(zigos: *ZigOS) [*]u32 {
    return @ptrCast(@alignCast(zigos.lfbs[PLANE].fb));
}

// --------------------------------------------------------------------------
pub const Demo = struct {
    acc: f32,
    ok: bool,
    /// Space/Escape hand the screen back to the menu (the Go terminates on them).
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.acc = 0;
        self.ok = false;
        self.wants_quit = false;

        for (0..16) |i| static_pal[i] = assets.rgbw(assets.beWord(assets.palette_words, i * 2));
        for (0..20) |i| rast[i] = assets.rgbw(assets.beWord(assets.raster_words, i * 2));
        clock = clockmod.Clock.init();
        stream.init();
        shown_live = false;

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        for (0..16) |i| fb.palette[i] = static_pal[i];
        for (16..256) |i| fb.palette[i] = 0; // unused: transparent, never shown
        zigos.setBackgroundColor(Color.fromRGBA(static_pal[0]));
        fb.setFrameBufferHBLHandler(0, planeHbl);

        presenter.full(planeWords(zigos), &clock, &stream, false);
        pending = false;
        zg.requestSongTune(MUSIC, MUSIC_TUNE);
        self.ok = true;
    }

    fn tick50(self: *Demo) void {
        _ = self;
        clock.step();
        stream.step();
        shown_live = true;
        pending = true;
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
        if (!pending) return; // no tick since the last present: the plane is current
        presenter.update(planeWords(zigos), &clock, &stream, shown_live);
        pending = false;
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
        _ = @import("larcociel2/testapi.zig");
    }
}
