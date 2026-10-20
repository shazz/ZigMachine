// --------------------------------------------------------------------------
// DMA INTRO 5 -- "LARCOCIEL" (DMA, 1990), the olivierh59500 Go/Ebitengine
// re-creation github.com/olivierh59500/go-larcociel5, ported to the ZigMachine.
//
// The Go is a 320x200 palette-index picture at 50 TPS built by a single
// "palette shader" over four textures, and this cart is that shader played
// out on the ST's own hardware:
//
//   * background  -- a static 320x200 index plane (background.png).
//   * body        -- an authored 112x50 ribbon of ST indices 1..3, redrawn every
//                    tick along the clock's 50-row trail (its X history), and
//                    OR'd into the background's low two plane bits.
//   * bats        -- three 64x32 1-bit "Batman" logos at the top, one per
//                    screen third, each picked by a YM2149 volume register
//                    (8/10/9) of the music the cart itself is playing.
//   * colour bank -- DCK's perspective glyph window: a 272-row stencil of ST
//                    colour words sampled into 100 rows, which the shader reads
//                    as an image. On the ST that is a colour register rewritten
//                    per scanline -- a REAL raster, not a fake one (CLAUDE.md) --
//                    so `colorbank.zig` builds the 100x16 table and the plane's
//                    HBL writes entries 1..15 on visible line 100..row. The
//                    top raster (shader Raster[y]) is the same trick on entry 4
//                    for lines 0..63.
//
// The Go's shader, verbatim, is exactly this decomposition:
//   i = bg;  ribbon.a>0 -> i=(i/4)*4+ribbon;  y<32 -> i=i%4+bat4
//   y>=100 && i>0 -> colourBank[y-100][i];  i==4 && y<64 -> Raster[y];  else Palette[i]
//
// MUSIC (CLAUDE.md: an SNDH, not a YM dump). The Go's music.ym is a 1999 YM6
// recording (LeOnArD) of the intro playing Jochen Hippel's (Mad Max's)
// "Cybernoid 2" (1989): the real DMA_5.PRG (fujiology DMA_CONC/DMA_5.ZIP) runs
// a Mad Max replay (shirazmcp identify_music, 0.82) and holds 57% of the 16-byte
// chunks of Mad_Max/Games/Cybernoid_2.sndh (the next file 26%), and subtune 1
// reproduces the YM6's registers 0..10 EXACTLY on every one of 6000 frames (2
// minutes; a 2-frame start offset), subtune 2 0%. docs/music/cybernoid2.sndh is
// that file, already shipped for equinox. The 68000 replay runs on the sound
// CPU (BARD on the board), not on the cart CPU. The Batmen read the machine's
// live YM mirror (zigos.ym_regs), as gen4_3615's VU meters do.
//
// The Go quits on Space or Escape; this cart hands the screen back to the menu
// on either (demo_main's pollCart contract).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const assets = @import("larcociel5/assets.zig");
const clockmod = @import("larcociel5/clock.zig");
const colorbank = @import("larcociel5/colorbank.zig");

const PLANE = 0;
const W: usize = zg.WIDTH; // 320
const H: usize = zg.HEIGHT; // 200

/// One 50 Hz frame. dt arrives in MILLISECONDS from the host.
const TICK_MS: f32 = 20.0;
/// A stalled tab steps at most this many 50 Hz ticks in one host frame.
const MAX_TICKS: u32 = 2;

const MUSIC = "cybernoid2.sndh";
const MUSIC_TUNE: u8 = 1;

const K_ESC: u32 = 0xE012;
const K_SPACE: u32 = 32;

// --- module-scope state (the harness's window into the very words drawn) ----
pub var clock: clockmod.Clock = undefined;
pub var bank: colorbank.Bank = undefined;
/// The YM registers the Batmen read on the last tick (the harness pins them).
pub var ym_regs: [14]u8 = [_]u8{0} ** 14;
pub var meters: [3]u8 = .{ 1, 1, 1 };
pub var shown_bats: bool = false;

// Ribbon overlay indices (0 = transparent). 64 KB, so it lives in the machine's
// RAM arena rather than the cart's data section (the zero-segment gate).
var body: []u8 = &[_]u8{};
var static_pal: [16]u32 = undefined; // the 16 ST words, Color.toRGBA order
var rast: [64]u32 = undefined; // Raster[y] for entries' lines 0..63

// --------------------------------------------------------------------------
// The plane HBL -- the shader's per-line colour selection, on real hardware.
// Logical lines 0..199 on a normal plane (copper.zig's contract).
// --------------------------------------------------------------------------
fn planeHbl(fb: *zg.LogicalFB, zigos: *ZigOS, line: u16, x: u16) void {
    _ = zigos;
    _ = x;
    const y: usize = line;
    // The shader reads Palette[i] on every line ABOVE the colour bank, but the
    // bank's 100 lines rewrite entries 1..15. Restore them at line 0, or the
    // next render/frame would show the previous bank row behind the ribbon and
    // bats (entries 1..15 are stale). Entry 4 is then re-armed by the raster.
    if (y == 0) {
        var i: usize = 1;
        while (i < 16) : (i += 1) fb.palette[i] = static_pal[i];
    }
    if (y < 64) {
        fb.palette[4] = rast[y]; // i==4 && y<64 -> Raster[y]
    } else if (y == 64) {
        fb.palette[4] = static_pal[4]; // back to the static word below the raster
    } else if (y >= 100) {
        const row = (y - 100) * 16;
        var i: usize = 1;
        while (i < 16) : (i += 1) fb.palette[i] = bank.colors[row + i];
    }
}

// --------------------------------------------------------------------------
// The ribbon body: 50 one-row sprites, row r at (History[r], Y + r).
// --------------------------------------------------------------------------
fn buildBody() void {
    const hist = clock.history;
    const y0: i32 = clock.y;
    var r: usize = 0;
    while (r < 50) : (r += 1) {
        const yy = y0 + @as(i32, @intCast(r));
        if (yy < 0 or yy >= H) continue;
        const row = r * 112;
        var x: usize = 0;
        while (x < 112) : (x += 1) {
            const v = assets.ribbon[row + x];
            if (v == 0) continue;
            const dx: i32 = @as(i32, @intCast(x)) + @as(i32, hist[r]);
            if (dx < 0 or dx >= W) continue;
            body[@as(usize, @intCast(yy)) * W + @as(usize, @intCast(dx))] = v & 3;
        }
    }
}

// --------------------------------------------------------------------------
// present: the shader's index math (background, ribbon, bats), one plane byte
// per pixel. Colour is the HBL's job.
// --------------------------------------------------------------------------
fn present(fb: *zg.LogicalFB, with_bats: bool) void {
    const px = fb.fb[0 .. W * H];
    const bg = assets.bg;
    var y: usize = 0;
    while (y < H) : (y += 1) {
        const base = y * W;
        const bat_row = y < 32;
        var x: usize = 0;
        while (x < W) : (x += 1) {
            var i: u8 = bg[base + x];
            const b = body[base + x];
            if (b != 0) i = (i & ~@as(u8, 3)) | b;
            if (bat_row) {
                var hit = false;
                if (with_bats) {
                    const rx = x & 127;
                    if (rx < 64) hit = assets.batBit(15 - meters[x >> 7], rx, y) != 0;
                }
                i = (i & 3) | (if (hit) @as(u8, 4) else 0);
            }
            px[base + x] = i;
        }
    }
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

        body = zg.mem.alloc(u8, W * H) orelse return; // counted by the machine
        for (0..16) |i| static_pal[i] = assets.rgbw(assets.beWord(assets.palette_words, i * 2));
        for (0..64) |i| {
            const w: u16 = if (i < assets.raster_words.len / 2) assets.beWord(assets.raster_words, i * 2) else 0x700;
            rast[i] = assets.rgbw(w);
        }
        clock = clockmod.Clock.init(assets.initial_motion, assets.initial_history);
        ym_regs = [_]u8{0} ** 14;
        bank.clear(); // frame 0: the Go's Update never ran, the colour bank is empty
        @memset(body, 0);
        meters = .{ 1, 1, 1 };
        shown_bats = false;

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        for (0..16) |i| fb.palette[i] = static_pal[i];
        for (16..256) |i| fb.palette[i] = 0; // unused: transparent, never shown
        zigos.setBackgroundColor(Color.fromRGBA(static_pal[0]));
        fb.setFrameBufferHBLHandler(0, planeHbl);

        present(fb, false);
        zg.requestSongTune(MUSIC, MUSIC_TUNE);
        self.ok = true;
    }

    fn tick50(self: *Demo, zigos: *const ZigOS) void {
        _ = self;
        clock.step();
        ym_regs = zigos.ym_regs[0..14].*;
        bank.build(clock.tick);
        meters = .{
            @max(1, ym_regs[8] & 15),
            @max(1, ym_regs[10] & 15),
            @max(1, ym_regs[9] & 15),
        };
        @memset(body, 0);
        buildBody();
        shown_bats = true;
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
        present(&zigos.lfbs[PLANE], shown_bats);
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
        _ = @import("larcociel5/testapi.zig");
    }
}
