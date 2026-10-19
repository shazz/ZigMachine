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
// 0..15 and entry 4 on lines 49..92, and restores both below them.
//
// MUSIC: the production's own assets/original/music.ym (YM6 by LeOnArD, 18695
// frames) replayed through the MACHINE's YM2149 via zg.ymWrite -- the faithful
// path here, because the source ships a replayable YM stream. Not samples, no
// host player. (The Go also lets the arrow keys move the projection centre;
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
const ymod = @import("larcociel2/ym.zig");

const PLANE = 0;
const W: usize = zg.WIDTH; // 320
const H: usize = zg.HEIGHT; // 200

const BAND_TOP = assets.BAND_TOP;
const BAND_ROWS = assets.BAND_ROWS;
const BAND_FRAMES = assets.BAND_FRAMES;

/// One 50 Hz frame. dt arrives in MILLISECONDS from the host.
const TICK_MS: f32 = 20.0;
/// A stalled tab steps at most this many 50 Hz ticks in one host frame, which
/// also bounds the music writes handed to the sfx queue.
const MAX_TICKS: u32 = 2;

const K_ESC: u32 = 0xE012;
const K_SPACE: u32 = 32;

// --- module-scope state (the harness's window into the very words drawn) ----
pub var clock: clockmod.Clock = undefined;
pub var stream: textmod.Stream = undefined;
pub var ym: ymod.Stream = undefined;
/// False only for the boot frame (the Go's tick 0: no balls, no text).
pub var shown_live: bool = false;

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
    if (y < 16) {
        fb.palette[8] = rast[y >> 1];
    } else if (y == 16) {
        fb.palette[8] = static_pal[8];
    }
    // i==4 && 49<=y<93 -> Raster[9+(y-49)/4], on entry 4.
    if (y >= 49 and y < 93) {
        fb.palette[4] = rast[9 + ((y - 49) >> 2)];
    } else if (y == 93) {
        fb.palette[4] = static_pal[4];
    }
}

// --------------------------------------------------------------------------
// The projected ball slots: geometry.ProjectWordPoint, word for word.
// --------------------------------------------------------------------------
pub const Projection = struct { x: i16, y: i16, image: usize, visible: bool };
fn divide(n: i32, depth: i16) i16 {
    // Go: q := int64(n)/int64(depth); out of int16 range keeps the LOW word.
    const q = @divTrunc(@as(i64, n), @as(i64, depth));
    if (q < -32768 or q > 32767) return @bitCast(@as(u16, @truncate(@as(u32, @bitCast(n)))));
    return @intCast(q);
}

fn project(hx: i16, hy: i16, hz: i16) Projection {
    const x: i32 = @as(i16, hx -% 160); // WrappedPoint X - centre
    const y: i32 = @as(i16, hy -% 80);
    const px: i32 = 205 * x; // pose.Matrix[0] = 205
    const py: i32 = 205 * y; // pose.Matrix[4] = 205
    const depth: i16 = hz +% 205; // pz(=z)>>0 + DepthBias(205) + pose.Depth(0)
    if (depth == 0) return .{ .x = 0, .y = 0, .image = 0, .visible = false };
    const a = divide(px, depth);
    const b = divide(py, depth);
    const zs: i32 = hz >> 5;
    const img: usize = @intCast(@max(0, @min(15, zs)));
    return .{
        .x = a +% 160, // Center[0]
        .y = b +% 80, // Center[1]
        .image = img,
        .visible = true,
    };
}

/// The projected pose of ball slot `i` from the live clock (the harness's door).
pub fn slotInfo(i: usize) Projection {
    const p = clock.history[(i % 6) * 11];
    return project(p[0], p[1], p[2]);
}

fn drawBall(px: []u8, slot: usize) void {
    const p = clock.history[slot * 11];
    const pr = project(p[0], p[1], p[2]);
    if (!pr.visible) return;
    const bbase = pr.image * 1024;
    var yy: usize = 0;
    while (yy < 32) : (yy += 1) {
        const sy: i32 = @as(i32, pr.y) + @as(i32, @intCast(yy));
        if (sy < 0 or sy >= H) continue;
        var xx: usize = 0;
        while (xx < 32) : (xx += 1) {
            const shade = assets.p2(assets.balls, bbase + yy * 32 + xx);
            if (shade == 0) continue;
            const sx: i32 = @as(i32, pr.x) + @as(i32, @intCast(xx));
            if (sx < 0 or sx >= W) continue;
            const o = @as(usize, @intCast(sy)) * W + @as(usize, @intCast(sx));
            px[o] = (px[o] & ~@as(u8, 3)) | shade; // i = (i/4)*4 + shade
        }
    }
}

fn drawGlyph(px: []u8, slot: usize) void {
    const s = stream.slot(slot);
    if (s.glyph < 0) return;
    const g: usize = @intCast(s.glyph);
    const x0: usize = 16 + 8 * slot;
    var yy: usize = 0;
    while (yy < 16) : (yy += 1) {
        const gbase = g * 512 + yy * 32 + @as(usize, s.index) * 8;
        var k: usize = 0;
        while (k < 8) : (k += 1) {
            if (assets.bit(assets.font, gbase + k) != 0) {
                const o = yy * W + x0 + k;
                px[o] = (px[o] & 7) | 8; // text.a>0 -> i = i%8 + 8
            }
        }
    }
}

// --------------------------------------------------------------------------
// present: the shader's index math (background, balls, text), one plane byte
// per pixel. Colour is the HBL's job.
// --------------------------------------------------------------------------
fn present(fb: *zg.LogicalFB, live: bool) void {
    const px = fb.fb[0 .. W * H];
    const frame: usize = (clock.tick + (BAND_FRAMES - 1)) % BAND_FRAMES;
    var y: usize = 0;
    while (y < H) : (y += 1) {
        const base = y * W;
        if (y < BAND_TOP) {
            var x: usize = 0;
            while (x < W) : (x += 1) px[base + x] = assets.p2(assets.bg_static, base + x) * 4;
        } else {
            const bbase = frame * (BAND_ROWS * W) + (y - BAND_TOP) * W;
            var x: usize = 0;
            while (x < W) : (x += 1) px[base + x] = assets.p2(assets.bg_band, bbase + x) * 4;
        }
    }
    if (!live) return;
    var i: usize = 0;
    while (i < 6) : (i += 1) drawBall(px, i);
    i = 0;
    while (i < textmod.CAP) : (i += 1) drawGlyph(px, i);
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
        ym.init();
        shown_live = false;

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        for (0..16) |i| fb.palette[i] = static_pal[i];
        for (16..256) |i| fb.palette[i] = 0; // unused: transparent, never shown
        zigos.setBackgroundColor(Color.fromRGBA(static_pal[0]));
        fb.setFrameBufferHBLHandler(0, planeHbl);

        present(fb, false);
        self.ok = true;
    }

    fn tick50(self: *Demo) void {
        _ = self;
        clock.step();
        stream.step();
        ym.advanceTo(clock.tick - 1);
        shown_live = true;
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
        present(&zigos.lfbs[PLANE], shown_live);
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
