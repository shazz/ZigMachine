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
//   * meter.zig ORs planes 2/3 into the screen exactly where the Go does;
//   * raster.zig rebuilds the two 200-word tables each tick, and the plane HBL
//     rewrites palette entries 0 and 2 on every one of the 200 visible lines --
//     a REAL raster, not a static palette;
//   * sprite-a.idx / sprite-b.idx are laid down as 80-pixel rows after the
//     screen decode, index 0 included, because every source pixel is opaque.
//
// MUSIC: the production ships seven replacement YM dumps (Mad Max / Jochen
// Hippel). Tracks 1..3 were matched register-for-register against SNDHs in
// docs/music (Jinks #1, lockbuster2_rollout #1/#2) and are requested by name.
// Tracks 4..7 have no SNDH match and request the production's own unpacked YM
// dumps (chonchon2_music-4..7.ymraw). The host player owns the chip in every
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
const metermod = @import("meter.zig");
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
/// F1..F7. The three matched SNDHs first; the four remaining production dumps
/// are requested as .ymraw (see the header).
const TRACKS = [7]Track{
    .{ .file = "Jinks.sndh", .tune = 1 },
    .{ .file = "lockbuster2_rollout.sndh", .tune = 1 },
    .{ .file = "lockbuster2_rollout.sndh", .tune = 2 },
    .{ .file = "chonchon2_music-4.ymraw", .tune = 0 },
    .{ .file = "chonchon2_music-5.ymraw", .tune = 0 },
    .{ .file = "chonchon2_music-6.ymraw", .tune = 0 },
    .{ .file = "chonchon2_music-7.ymraw", .tune = 0 },
};

// --- module-scope state (the harness's window into the very words drawn) ----
pub var clock: clockmod.Clock = undefined;
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
// The 4-plane decode of clock.screen (the Go's Pixels), then the two opaque
// 80-wide sprite rectangles (the Go's ImageSlots).
// --------------------------------------------------------------------------
fn present(fb: *zg.LogicalFB, live: bool) void {
    if (live) metermod.apply(clock.screen[0..], ym.regs);
    const px = fb.fb[0 .. W * H];
    const scr = clock.screen[0..];
    var group: usize = 0;
    while (group < 4000) : (group += 1) {
        const at = group * 8;
        const p0 = assets.beWord(scr, at);
        const p1 = assets.beWord(scr, at + 2);
        const p2 = assets.beWord(scr, at + 4);
        const p3 = assets.beWord(scr, at + 6);
        var x: usize = 0;
        while (x < 16) : (x += 1) {
            const shift: u4 = @intCast(15 - x);
            const v: u8 = @intCast(((p0 >> shift) & 1) |
                (((p1 >> shift) & 1) << 1) |
                (((p2 >> shift) & 1) << 2) |
                (((p3 >> shift) & 1) << 3));
            px[group * 16 + x] = v;
        }
    }
    if (!live) return;
    drawSprite(px, assets.sprite_a, assets.sprite_a_w, assets.sprite_a_h, clock.poses[0], clock.tick, false);
    drawSprite(px, assets.sprite_b, assets.sprite_b_w, assets.sprite_b_h, clock.poses[1], clock.tick, true);
}

fn drawSprite(px: []u8, image: []const u8, w: usize, h: usize, pose: clockmod.Pose, tick: u32, wrap: bool) void {
    var row: usize = 0;
    while (row < h) : (row += 1) {
        const source_y = if (wrap and row >= 2 and row < 32)
            2 + (tick + @as(u32, @intCast(row)) - 2) % 192
        else
            row;
        const y = pose.y + @as(i32, @intCast(row));
        if (y < 0 or y >= H) continue;
        var dx: usize = 0;
        while (dx < w) : (dx += 1) {
            const x = pose.x + @as(i32, @intCast(dx));
            if (x < 0 or x >= W) continue;
            px[@as(usize, @intCast(y)) * W + @as(usize, @intCast(x))] = image[source_y * w + dx];
        }
    }
}

// --------------------------------------------------------------------------
pub const Demo = struct {
    acc: f32,
    ok: bool,
    drawn: bool, // false only for the Go's never-drawn pre-first-Update state
    /// Space/Escape hand the screen back to the menu (the Go terminates on them).
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.acc = 0;
        self.ok = false;
        self.drawn = false;
        self.wants_quit = false;

        for (0..16) |i| static_pal[i] = assets.rgbw(assets.beWord(assets.palette_words, i * 2));
        clock = clockmod.Clock.init();
        ym.init();
        track = 0;
        meters = .{ 0, 0, 0 };
        rastermod.update(clock.tick, clock.old_y);

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        for (0..16) |i| fb.palette[i] = static_pal[i];
        for (16..256) |i| fb.palette[i] = 0; // unused: transparent, never shown
        zigos.setBackgroundColor(Color.fromRGBA(static_pal[0]));
        fb.setFrameBufferHBLHandler(0, planeHbl);
        @memset(fb.fb[0 .. W * H], 0); // nothing shown before the first Update

        zg.requestSongTune(TRACKS[0].file, TRACKS[0].tune);
        self.ok = true;
    }

    fn tick50(self: *Demo) void {
        clock.step();
        rastermod.update(clock.tick, clock.old_y);
        ym.step();
        metermod.apply(clock.screen[0..], ym.regs);
        meters = .{ ym.regs[8] & 15, ym.regs[9] & 15, ym.regs[10] & 15 };
        self.drawn = true;
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
        const fb = &zigos.lfbs[PLANE];
        if (!self.drawn) {
            @memset(fb.fb[0 .. W * H], 0);
            return;
        }
        present(fb, true);
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
