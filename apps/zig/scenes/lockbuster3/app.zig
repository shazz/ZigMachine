// --------------------------------------------------------------------------
// LOCKBUSTER 3 -- the third Lockbuster intro, "Lockbuster DMA" (1989), ported
// from github.com/olivierh59500/go-lockbuster3, the Go/Ebitengine re-creation
// of the native ST executable.
//
// The Go production composes a 320x240 INDEX canvas at 50 Hz:
//
//   background  <- artwork rows 35..74 tiled five times (rows 0..199);
//                  the lower 40 rows start black (the music meters live there)
//   buffer      <- background, the three letters (d, m, a) on their signed
//                  word paths, one of 60 panel frames, and three 32x25 meters
//   text        <- two 40-slot glyph lanes whose 8x20 cells are either the
//                  artwork's own bitplane-0 strips or a 1-bit font glyph
//   colour      <- Palette[i]; rows 160..199 replace bit 0 with the text bit;
//                  indices 12/14 on rows 159..197 take Rasters[row-159]
//
// This cart plays that out on the ST's own hardware. Rows 0..199 are the normal
// 320x200 window; rows 200..239 (the Go's whole lower band, meters included)
// are shown by opening the BOTTOM border and keeping the top and sides closed.
// The Raster is a REAL per-scanline rewrite of palette entries 12 and 14 in the
// plane's HBL -- never a pre-coloured image. Text's LSB replacement happens
// while the index row is copied into the overscan buffer, in the same order as
// the shader (text first, raster selection afterwards).
//
// MUSIC: the Go streams assets/original/music.ym, an LHA holding ROLLOUT2.YM
// ("Rollout tune 2", Jochen Hippel / Mad Max, YM6, 10650 frames). The matching
// subtune 2 of docs/music/lockbuster2_rollout.sndh is requested; the meters
// visualise the host audio thread's YM mirror (`zigos.ym_regs`), exactly the
// registers the Go read from its decoder each 960-sample block.
//
// CONTROLS: Escape or Space leaves (the Go terminates on either).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const assets = @import("assets.zig");

const W: usize = 320; // the Go's Width
const H: usize = 240; // the Go's Height (320x240, not 320x200)
const VISIBLE: usize = 200; // the machine's window
const PLANE = 0;
const PHYS_W: usize = 400;
const PHYS_H: usize = 280;
const BORDER_X: usize = 40;
const BORDER_Y: usize = 40;
const RASTER_ROW: usize = 159; // shader RasterRange.x
pub const RASTER_LINES: usize = 39;
const TEXT_ROW: usize = 160; // shader's text band

const TICK_MS: f32 = 20.0;
const MAX_TICKS: u32 = 2;

const K_ESC: u32 = 0xE012;
const K_SPACE: u32 = 32;

const MUSIC = "lockbuster2_rollout.sndh";
const MUSIC_TUNE: u8 = 2;

const Rect = struct {
    x: i32,
    y: i32,
};

const ScrollColumn = struct {
    font: u8 = 0,
    glyph: u8 = 0,
    column: u8 = 0,
    initial: u8 = 0,
    row: u8 = 0,
    slot: u8 = 0,
};

const PanelPose = struct {
    cell: u8 = 0,
    bank: u8 = 0,
    frame: u8 = 0,
};

const PanelState = struct {
    order: [64]u32 = undefined,
    cursor: i32 = 0,
    direction: i32 = 1,
    cycle: i32 = 5,
    step_n: i32 = 0,
    offset: i32 = 0,
    base: i32 = 0,
    mode: i32 = 0,
    down: bool = false,
    peak: bool = false,
    pose: PanelPose = .{},
    draw: bool = false,
    commit: bool = false,
};

const ScrollState = struct {
    fonts: [assets.message.len]u8 = undefined,
    columns: [2][40]ScrollColumn = undefined,
    glyph: usize = 0,
    column: usize = 0,
    row: usize = 0,
    changes: usize = 0,
    remaining: usize = 0,
};

// --- state the harness reads (module scope, like chonchon) -----------------
pub var bg: []u8 = &.{};
pub var buffers: [2][]u8 = .{ &.{}, &.{} };
pub var text_bits: []u8 = &.{};
pub var front: u2 = 1;
pub var tick: u32 = 0;
pub var volumes: [3]u8 = .{ 0, 0, 0 };
pub var letters: [3][8]i16 = undefined;
pub var history: [2][3]Rect = undefined;
pub var panel: PanelState = .{};
pub var scroll: ScrollState = .{};
pub var palette_words: [16]u16 = undefined;
pub var raster_words: [RASTER_LINES]u16 = undefined;
pub var ready = false;

fn fail(why: []const u8) void {
    zg.Console.log("lockbuster3: {s}", .{why});
}

fn restoreRect(dst: []u8, r: Rect) void {
    // Go's restore is a SourceOver blit of the background subimage whose rect
    // is (x &^ 15, y, 64, 35). Clip to the canvas on both sides.
    var sy: i32 = r.y;
    var dy: usize = 0;
    var n: usize = 35;
    if (sy < 0) {
        dy = @intCast(-sy);
        n -= dy;
        sy = 0;
    }
    if (sy + @as(i32, @intCast(n)) > H) n = H - @as(usize, @intCast(sy));
    var sx: i32 = r.x;
    var dx: usize = 0;
    var w: usize = 64;
    if (sx < 0) {
        dx = @intCast(-sx);
        w -= dx;
        sx = 0;
    }
    if (sx + @as(i32, @intCast(w)) > W) w = W - @as(usize, @intCast(sx));
    if (n == 0 or w == 0) return;
    const yy: usize = @intCast(sy);
    const xx: usize = @intCast(sx);
    for (0..n) |row| {
        @memcpy(dst[(yy + row) * W + xx ..][0..w], bg[(yy + row) * W + xx ..][0..w]);
    }
}

fn drawLetter(dst: []u8, which: usize, x: i32, y: i32) void {
    const src = assets.letters[which * 48 * 35 ..][0 .. 48 * 35];
    for (0..35) |sy| {
        const ty = y + @as(i32, @intCast(sy));
        if (ty < 0 or ty >= H) continue;
        for (0..48) |sx| {
            const v = src[sy * 48 + sx];
            if (v == 0) continue; // alpha 0: transparent
            const tx = x + @as(i32, @intCast(sx));
            if (tx < 0 or tx >= W) continue;
            dst[@as(usize, @intCast(ty)) * W + @as(usize, @intCast(tx))] = v;
        }
    }
}

fn panelPixel(bank: usize, frame: usize, sx: usize, sy: usize) u8 {
    const fx = frame % 5 * 64 + sx;
    const fy = frame / 5 * 40 + sy;
    const at = fy * 320 + fx;
    const b = assets.panels[bank & 3][at >> 1];
    return if ((at & 1) == 0) b >> 4 else b & 15;
}

/// Copy one 64x40 authored panel frame (the Go's ImageSlot blit) at (x, y).
fn drawPanel(dst: []u8, bank: usize, frame: usize, x: i32, y: i32) void {
    for (0..40) |sy| {
        const ty = y + @as(i32, @intCast(sy));
        if (ty < 0 or ty >= H) continue;
        for (0..64) |sx| {
            const tx = x + @as(i32, @intCast(sx));
            if (tx < 0 or tx >= W) continue;
            dst[@as(usize, @intCast(ty)) * W + @as(usize, @intCast(tx))] =
                panelPixel(bank, frame, sx, sy);
        }
    }
}

fn drawBars(dst: []u8) void {
    for (volumes, 0..) |v0, i| {
        const v: usize = v0;
        const sx = if (v < 10) v * 32 else (v - 10) * 32;
        const sy: usize = if (v < 10) 0 else 25;
        const x = 80 + i * 64;
        for (0..25) |dy| {
            @memcpy(dst[(210 + dy) * W + x ..][0..32], assets.bars[(sy + dy) * 320 + sx ..][0..32]);
        }
    }
}

fn drawLetters(target: usize) void {
    const dst = buffers[target];
    for (0..3) |i| {
        const x: i32 = letters[i][0];
        const y: i32 = letters[i][1];
        drawLetter(dst, i, x, y);
        history[target][i] = .{ .x = x & ~@as(i32, 15), .y = y };
    }
}

fn initialBit(lane: usize, slot: usize, dx: usize, dy: usize) u8 {
    return assets.background[(lane * 20 + dy) * W + slot * 8 + dx] & 1;
}

fn fontBit(bank: usize, glyph: usize, column: usize, dx: usize, dy: usize) u8 {
    const x = glyph % 16 * 32 + column * 8 + dx;
    const y = glyph / 16 * 20 + dy;
    const b = assets.fonts[bank & 1][y * 64 + (x >> 3)];
    return (b >> @intCast(7 - (x & 7))) & 1;
}

/// Go's drawText(): both lanes of 40 glyph cells, IdentityState, End 40,
/// Y = 160 + lane*20. The layer is cleared first, so every pixel outside the
/// glyphs is a 0 bit (it CLEARS bit 0 when composited).
fn drawText() void {
    @memset(text_bits, 0);
    for (0..2) |lane| {
        for (0..40) |slot| {
            const c = scroll.columns[lane][slot];
            for (0..20) |dy| {
                for (0..8) |dx| {
                    const bit = if (c.initial != 0)
                        initialBit(lane, slot, dx, dy)
                    else
                        fontBit(c.font, c.glyph, c.column, dx, dy);
                    text_bits[(lane * 20 + dy) * W + slot * 8 + dx] = bit;
                }
            }
        }
    }
}

fn readLetters() void {
    for (0..3) |i| {
        for (0..8) |j| {
            letters[i][j] = assets.sWord(assets.motion, i * 16 + j * 2);
        }
    }
}

fn stepLetter(l: *[8]i16) void {
    l[0] +%= l[2];
    l[1] +%= l[3];
    l[2] +%= l[4];
    l[3] +%= l[5];
    if (l[2] == l[6] or l[2] == -%l[6]) l[4] = -%l[4];
    if (l[3] == l[7] or l[3] == -%l[7]) l[5] = -%l[5];
}

fn panelStep(p: *PanelState) void {
    p.draw = false;
    p.commit = false;
    const entry = p.order[@intCast(p.cursor)];
    switch (entry) {
        250 => {
            p.direction = 1;
            p.cursor = 1;
            p.cycle = 5;
            p.step_n = 0;
            p.offset = 0;
            p.base = 0;
            p.down = false;
            p.peak = false;
            return;
        },
        253 => {
            p.mode ^= 1;
            p.direction = -1;
            p.cursor -= 1;
            p.offset = 25600;
            p.base = 25600;
            p.step_n = 0;
            p.down = false;
            return;
        },
        254 => {
            p.cursor += p.direction;
            p.offset = 51200;
            p.base = 51200;
            p.step_n = 0;
            p.down = false;
            return;
        },
        255 => {
            p.cursor += p.direction;
            p.mode ^= 1;
            p.offset = p.mode * 25600;
            p.base = p.offset;
            p.step_n = 0;
            p.down = false;
            return;
        },
        else => {},
    }
    const x: i32 = @intCast(@mod(entry, 6400) / 32);
    const y: i32 = @intCast(entry / 6400);
    const local: i32 = @mod(p.offset, 25600);
    p.pose = .{
        .cell = @intCast(y * 5 + x),
        .bank = @intCast(@divTrunc(p.offset, 25600)),
        .frame = @intCast(@divTrunc(local, 6400) * 5 + @divTrunc(@mod(local, 6400), 32)),
    };
    p.draw = true;
    if (p.peak) {
        p.peak = false;
        p.commit = true;
        p.cursor += p.direction;
        return;
    }
    if (p.down) {
        p.step_n -= 1;
        if (p.step_n == 0) {
            p.cycle = 5;
            p.down = false;
            return;
        }
        p.cycle -= 1;
        if (p.cycle == 0) {
            p.cycle = 5;
            p.offset -= 6240;
        }
        p.offset -= 32;
        return;
    }
    p.step_n += 1;
    if (p.step_n == 20) {
        p.cycle = 5;
        p.down = true;
        p.peak = true;
        return;
    }
    p.cycle -= 1;
    if (p.cycle == 0) {
        p.cycle = 5;
        p.offset += 6240;
    }
    p.offset += 32;
}

fn scrollStep(s: *ScrollState) void {
    const wanted: usize = s.fonts[s.glyph];
    if (wanted != s.row) {
        s.row = wanted;
        if (wanted == 0) s.remaining = assets.message.len - s.glyph;
        s.changes += 1;
        return; // the original copies the held row once at each handoff
    }
    const r = assets.message[s.glyph];
    var glyph: u8 = r -% 32;
    if (r == ' ') glyph = 3;
    for (0..39) |i| s.columns[s.row][i] = s.columns[s.row][i + 1];
    s.columns[s.row][39] = .{
        .font = @intCast(wanted),
        .glyph = glyph,
        .column = @intCast(s.column),
        .initial = 0,
        .row = @intCast(s.row),
        .slot = 39,
    };
    s.column += 1;
    if (s.column == 4) {
        s.column = 0;
        s.glyph += 1;
        if (s.row == 0) s.remaining -= 1;
        if (s.glyph == assets.message.len) {
            s.glyph = 0;
            s.remaining = assets.message.len;
        } else if (s.row == 1 and s.fonts[s.glyph] == 0) {
            s.remaining = assets.message.len - s.glyph;
        }
    }
}

fn initBackground() void {
    @memset(bg, 0);
    for (0..5) |tile| {
        for (0..40) |y| {
            @memcpy(bg[(tile * 40 + y) * W ..][0..W], assets.background[y * W ..][0..W]);
        }
    }
}

fn step(zigos: *ZigOS) void {
    tick +%= 1;
    for (0..3) |i| volumes[i] = zigos.ym_regs[8 + i] & 15;

    const target: usize = 1 - @as(usize, front);
    for (0..3) |i| restoreRect(buffers[target], history[target][i]);

    panelStep(&panel);
    if (panel.draw) {
        const px = panel.pose;
        const x: i32 = @as(i32, @intCast(px.cell % 5)) * 64;
        const y: i32 = @as(i32, @intCast(px.cell / 5)) * 40;
        drawPanel(buffers[target], px.bank, px.frame, x, y);
        if (panel.commit) {
            drawPanel(bg, @intCast(@divTrunc(panel.base, 25600)), 19, x, y);
        }
    }

    for (0..3) |i| stepLetter(&letters[i]);
    drawLetters(target);

    scrollStep(&scroll);
    drawText();
    drawBars(buffers[target]);
    front = @intCast(target);
}

fn planeHbl(fb: *zg.LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    if (line >= BORDER_Y + VISIBLE) fb.flickerBorder(); // open the bottom band only
    if (line == 0) {
        for (palette_words, 0..) |w, i| fb.palette[i] = assets.wordColor(w).toRGBA();
    }
    var c12: u16 = palette_words[12];
    var c14: u16 = palette_words[14];
    if (line >= BORDER_Y + RASTER_ROW and line < BORDER_Y + RASTER_ROW + RASTER_LINES) {
        const w = raster_words[line - (BORDER_Y + RASTER_ROW)];
        c12 = w;
        c14 = w;
    }
    fb.palette[12] = assets.wordColor(c12).toRGBA();
    fb.palette[14] = assets.wordColor(c14).toRGBA();
}

/// Compose the Go 320x240 index canvas into the 400x280 overscan buffer:
/// rows 0..199 at physical 40..239 (sides closed), rows 200..239 at physical
/// 240..279 (the opened bottom border, black in its own 40-column sides).
fn compose(fb: *zg.LogicalFB) void {
    const dst = fb.fb[0 .. PHYS_H * PHYS_W];
    const src = buffers[front];
    for (0..H) |gy| {
        const drow = dst[(BORDER_Y + gy) * PHYS_W + BORDER_X ..][0..W];
        const srow = src[gy * W ..][0..W];
        if (gy >= TEXT_ROW and gy < VISIBLE) {
            const trow = text_bits[(gy - TEXT_ROW) * W ..][0..W];
            for (0..W) |x| drow[x] = (srow[x] & 0xFE) | trow[x];
        } else {
            @memcpy(drow, srow);
        }
    }
}

pub const Demo = struct {
    acc: f32,
    ok: bool,
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.acc = 0;
        self.ok = false;
        self.wants_quit = false;
        ready = false;
        tick = 0;
        front = 1;
        volumes = .{ 0, 0, 0 };

        bg = zg.mem.mustAlloc(u8, W * H);
        buffers[0] = zg.mem.mustAlloc(u8, W * H);
        buffers[1] = zg.mem.mustAlloc(u8, W * H);
        text_bits = zg.mem.mustAlloc(u8, W * 40);

        for (0..16) |i| palette_words[i] = assets.beWord(assets.palette, i * 2);
        for (0..RASTER_LINES) |i| raster_words[i] = assets.beWord(assets.raster, i * 2);

        initBackground();
        readLetters();
        for (0..2) |i| {
            @memcpy(buffers[i], bg);
            for (0..3) |j| stepLetter(&letters[j]);
            drawLetters(i);
        }

        for (0..panel.order.len) |i| panel.order[i] = assets.beLong(assets.panel_order, i * 4);
        panel.cursor = 0;
        panel.direction = 1;
        panel.cycle = 5;
        panel.step_n = 0;
        panel.offset = 0;
        panel.base = 0;
        panel.mode = 0;
        panel.down = false;
        panel.peak = false;
        panel.pose = .{};
        panel.draw = false;
        panel.commit = false;

        var bank: u8 = 0;
        for (assets.message, 0..) |r, i| {
            if (r == 5) bank = 1 else if (r == 6) bank = 0;
            scroll.fonts[i] = bank;
        }
        for (0..2) |lane| {
            for (0..40) |slot| {
                scroll.columns[lane][slot] = .{ .initial = 1, .row = @intCast(lane), .slot = @intCast(slot) };
            }
        }
        scroll.glyph = 0;
        scroll.column = 0;
        scroll.row = 0;
        scroll.changes = 0;
        scroll.remaining = assets.message.len;
        drawText();

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setOverscanBuffer();
        @memset(fb.fb[0 .. PHYS_H * PHYS_W], 0);
        for (0..16) |i| fb.palette[i] = assets.wordColor(palette_words[i]).toRGBA();
        for (16..256) |i| fb.palette[i] = 0;
        zigos.setBackgroundColor(assets.wordColor(0));
        fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, planeHbl);

        zg.requestSongTune(MUSIC, MUSIC_TUNE);
        ready = true;
        self.ok = true;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt_ms: f32) void {
        if (!self.ok) return;
        if (dt_ms > 0) self.acc = @min(self.acc + @min(dt_ms, 200.0), TICK_MS * @as(f32, @floatFromInt(MAX_TICKS)));
        var n: u32 = 0;
        while (self.acc >= TICK_MS and n < MAX_TICKS) {
            self.acc -= TICK_MS;
            n += 1;
            step(zigos);
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, _: f32) void {
        if (!self.ok) return;
        compose(&zigos.lfbs[PLANE]);
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

comptime {
    if (@import("../../cart.zig").Cart == Demo) {
        _ = @import("testapi.zig");
    }
}
