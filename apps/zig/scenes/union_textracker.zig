// --------------------------------------------------------------------------
// The Union Demo (1989) HIDDEN SCREEN — TEX's "Sample-Mon ST" tracker — ported
// from shazz's melonJS "Union Demo HTML5 Remake" 0.9.8, screens/textracker/
// (screen.js, loader.js). Artwork by Hexagon, mice by ES, program by 6719,
// "Feed Me" by Mad Max: all The Union's.
//
// What the screen does (screen.js:80-125), each frame:
//   - rastCnt steps through Borgzor's 84-colour raster table;
//   - the mouse position is pushed onto a 33-deep history (unshift + pop);
//   - draw: a quad at (326,92)-(626,118) in the raster colour, the menu picture
//     over it (its index 255 is transparent: the "Sample-Mon" logo's holes);
//     mouse tiles 3, 2, 1 at the positions 24, 16 and 8 frames old; an 8x8 quad
//     in the raster colour at the newest position; tile 0 over it at alpha 0.9.
//
// Geometry: 640x400 canvas, both PNGs pixel-doubled on the (0,0) grid, so
// everything halves exactly onto one normal 320x200 plane.
//
// As palette work on ONE plane:
//   - the quad is hidden by the opaque menu everywhere but the logo's holes, so
//     it IS palette entry RASTER, which the menu's holes are converted to;
//   - tile 0's alpha 0.9 lands only on the 13 fixed colours (black, the menu's
//     ten, the mouse outline, the raster), so every (tile colour, colour under
//     it) pair is its own blended entry. Only the pairs over RASTER change per
//     frame.
//
// The TEX loader panel (loader.js) is not drawn here: the screen's data arrives
// ZX0-packed and depacks through zx0.Fx.tex_loader with the panel's own text.
//
// Music: the remake plays zik_feedme3.ogg, a recording of Mad Max's "Feed Me Max"
// as the Sample-Mon ST played it. Matt named its SNDH: Mad_Max/Demos/
// Thalion_Forever.sndh ("Thalion Forever", Mad Max 1989, one tune, FLAG ~ay).
// Measured against the ogg over 30 s, allowing a 0-30 s offset: centred chroma
// 0.374 (reversed-ogg null 0.152), where four other Mad Max SNDHs score 0.017
// (Level 16), 0.061 (Cybernoid), 0.065 (Pandora) and 0.091 (Thundercats). Its
// 'a' is not STE DMA here: the file never addresses $FF8900-$FF8920 and plays
// its samples through the YM's volume DAC (tone registers still, all three
// volume registers moving ~1300 times in 30 s at 60 Hz sampling). It never goes
// silent and loops on its own after about 182 s, as playTrack looped the ogg.
//
// ESC or SPACE (the remake's "exit"/"enter") go back to the Union Demo menu.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const hw = @import("hardware");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;
const DepackFx = @import("depackers").depack_fx.Runner(zg, null);

const W: usize = zg.WIDTH;
const H: usize = zg.HEIGHT;
const TILE: usize = 16; // initTile(32,32), halved
const SHEET_W: usize = 4 * TILE; // sprites.png 128x32, halved
const SCREEN_LEN: usize = W * H + SHEET_W * TILE; // screen.raw: menu, then the sheet

// The packed screen depacks in about 116 frames at 2 bytes a physical line: the
// remake's panel lands its last letter after 99 frames (13,820 ms at 140 ms a
// frame, loader.js:184).
const DEPACK_BYTES_PER_LINE = 2;
var depack: DepackFx = undefined;

// Palette (tools/private_tools/union_textracker_assets.py): 0 black, 1..10 the
// menu's colours, 11 the mouse outline #010101, 12 the raster.
const palette = zg.convertU8ArraytoColors(@embedFile("../assets/screens/union_textracker/pal.dat"));
const FIXED = 13;
const RASTER: u8 = 12;
/// The sheet's colours, each given a row of FIXED blended entries.
const INK = [_]u8{ 1, 2, 5, 6, 7, 8, 9, 10, 11 };
const BLEND_BASE: u8 = FIXED;
const ink_row: [256]u8 = blk: {
    var t = [_]u8{0} ** 256;
    for (INK, 0..) |c, i| t[c] = @intCast(i);
    break :blk t;
};
comptime {
    std.debug.assert(BLEND_BASE + INK.len * FIXED <= 256);
}

/// screen.js:28-39, "thanks Borgzor for the raster table": #RGB words.
const RASTER_COLORS = [_]u12{
    0xF00, 0xF10, 0xF20, 0xF30, 0xF40, 0xF50, 0xF60, 0xF70,
    0xF80, 0xF90, 0xFA0, 0xFB0, 0xFC0, 0xFD0, 0xFE0, 0xFF0,
    0xDF0, 0xDF0, 0xBF0, 0xBF0, 0x9F0, 0x9F0, 0x7F0, 0x7F0,
    0x4F0, 0x4F0, 0x2F0, 0x2F0, 0x0F0, 0x0F0, 0x0F2, 0x0F2,
    0x0F4, 0x0F4, 0x0F7, 0x0F7, 0x0F9, 0x0F9, 0x0FB, 0x0FB,
    0x0FD, 0x0FD, 0x0FF, 0x0FF, 0x0DF, 0x0DF, 0x0BF, 0x0BF,
    0x09F, 0x09F, 0x07F, 0x07F, 0x04F, 0x04F, 0x02F, 0x02F,
    0x00F, 0x00F, 0x20F, 0x20F, 0x40F, 0x40F, 0x70F, 0x70F,
    0x90F, 0x90F, 0xB0F, 0xB0F, 0xD0F, 0xD0F, 0xF0F, 0xF0F,
    0xF0D, 0xF0D, 0xF0B, 0xF0B, 0xF09, 0xF09, 0xF07, 0xF07,
    0xF04, 0xF04, 0xF02, 0xF02,
};

/// mousePosX/Y: indices 0..4*8 (screen.js:46), newest first.
const HISTORY = 4 * 8 + 1;
const TRAIL_STEP = 8; // tile i sits at the position i*8 frames old
const QUAD = 4; // the 8x8 quad under tile 0, halved
const TILE0_ALPHA = 0.9;

const MUSIC = "union/thalion_forever.sndh"; // Feed Me Max (see the header)
const MUSIC_TUNE = 1;
const HOME_TAG = "union_demo";
const K_ESC: u32 = 0xE012;
const K_SPACE: u32 = ' ';

const Point = struct { x: i32, y: i32 };

pub const Demo = struct {
    depacking: bool,
    screen: []const u8,
    raster: u8, // rastCnt
    mouse: Point, // currentPosX/Y
    history: [HISTORY]Point,
    newest: u8, // history[newest] = mousePos[0]
    leaving: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.depacking = false;
        self.screen = &.{};
        self.raster = 0;
        self.mouse = .{ .x = 0, .y = 0 };
        self.history = [_]Point{.{ .x = 0, .y = 0 }} ** HISTORY;
        self.newest = 0;
        self.leaving = false;

        const buf = freeRam(SCREEN_LEN) orelse return self.abandon("no free RAM to depack into");
        if (!depack.start(zigos, @import("packed_assets").union_textracker, buf, DEPACK_BYTES_PER_LINE))
            return self.abandon("packed screen unreadable");
        self.screen = buf;
        self.depacking = true;
    }

    /// Without its picture there is no screen to show: say why and go back.
    fn abandon(self: *Demo, why: []const u8) void {
        zg.Console.log("union_textracker: {s}, back to the menu", .{why});
        self.depacking = false;
        self.screen = &.{};
        self.leaving = true;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.leaving) return;
        if (self.depacking) {
            switch (depack.frame(zigos)) {
                .more => return,
                .failed => return self.abandon("depack failed"),
                .done => {
                    self.depacking = false;
                    startScreen(zigos);
                },
            }
        }
        // screen.js update(): the raster steps, the mouse history shifts.
        self.raster = @intCast((@as(usize, self.raster) + 1) % RASTER_COLORS.len);
        self.newest = @intCast((@as(usize, self.newest) + HISTORY - 1) % HISTORY);
        self.history[self.newest] = self.mouse;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.depacking or self.screen.len != SCREEN_LEN) return;
        const fb = &zigos.lfbs[0];
        setRaster(fb, RASTER_COLORS[self.raster]);
        const dst = blit.Dst.plane(fb);
        const sheet = blit.Image.init(self.screen[W * H ..], SHEET_W);
        blit.blit(dst, blit.Image.init(self.screen[0 .. W * H], W), null, 0, 0, null, .copy);
        for ([_]usize{ 3, 2, 1 }) |tile| { // for (i=3; i>0; i--), oldest underneath
            const p = self.ago(tile * TRAIL_STEP);
            blit.blit(dst, sheet, tileRect(tile), p.x, p.y, 0, .copy);
        }
        const p = self.ago(0);
        const quad = [_]u8{RASTER} ** (QUAD * QUAD);
        blit.blit(dst, blit.Image.init(&quad, QUAD), null, p.x, p.y, null, .copy);
        drawBlended(dst, sheet, p);
    }

    /// mousePos[frames]: the position `frames` updates old.
    fn ago(self: *const Demo, frames: usize) Point {
        return self.history[(self.newest + frames) % HISTORY];
    }

    fn startScreen(zigos: *ZigOS) void {
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(palette);
        for (INK, 0..) |ink, row| for (0..RASTER) |under| {
            const e = BLEND_BASE + @as(u8, @intCast(row * FIXED + under));
            fb.setPaletteEntry(e, blend(palette[ink], palette[under]));
        };
        zg.requestSongTune(MUSIC, MUSIC_TUNE); // onResetEvent: me.audio.playTrack("zik_feedMe3")
    }

    // The mousemove listener (screen.js:52-57): canvas coordinates, so the
    // position never leaves the picture.
    pub fn pointer(self: *Demo, x: i32, y: i32, buttons: u32) void {
        _ = buttons;
        self.mouse = .{ .x = std.math.clamp(x, 0, @as(i32, W - 1)), .y = std.math.clamp(y, 0, @as(i32, H - 1)) };
    }

    // Host input ids: 5 fire (Space/Enter), 6 back.
    pub fn input(self: *Demo, dir: u8) void {
        if (dir == 5 or dir == 6) self.leave();
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC or cp == K_SPACE) self.leave();
    }

    fn leave(self: *Demo) void {
        self.leaving = true;
    }

    /// me.state.change(MENU_LOADER): load the Union Demo menu's disk.
    pub fn pollCart(self: *Demo) i32 {
        return if (self.leaving) 1 else 0;
    }

    pub fn cartTag(self: *Demo) []const u8 {
        _ = self;
        return HOME_TAG;
    }
};

fn tileRect(n: usize) blit.Rect {
    return .{ .x = n * TILE, .y = 0, .w = TILE, .h = TILE };
}

/// Tile 0 at globalAlpha 0.9: each ink pixel becomes the entry blending its
/// colour over the one beneath (always one of the FIXED entries here).
fn drawBlended(dst: blit.Dst, sheet: blit.Image, p: Point) void {
    const x0: usize = @intCast(p.x);
    const y0: usize = @intCast(p.y);
    const w = @min(TILE, dst.w - x0);
    const h = @min(TILE, dst.h - y0);
    for (0..h) |ty| {
        const src = sheet.data[ty * SHEET_W ..][0..w];
        const row = dst.buf[(y0 + ty) * dst.stride + x0 ..][0..w];
        for (src, row) |s, *d| {
            if (s != 0) d.* = BLEND_BASE + ink_row[s] * FIXED + d.*;
        }
    }
}

/// The frame's raster colour, and tile 0's blends over it.
fn setRaster(fb: *zg.LogicalFB, word: u12) void {
    const c = Color{ .r = nibble(word >> 8), .g = nibble(word >> 4), .b = nibble(word), .a = 255 };
    fb.setPaletteEntry(RASTER, c);
    for (INK, 0..) |ink, row| {
        const e = BLEND_BASE + @as(u8, @intCast(row * FIXED + RASTER));
        fb.setPaletteEntry(e, blend(palette[ink], c));
    }
}

/// CSS #RGB: each digit times 17.
fn nibble(v: u12) u8 {
    return @as(u8, @intCast(v & 0xF)) * 17;
}

/// Canvas source-over of an opaque pixel at TILE0_ALPHA onto an opaque one.
fn blend(src: Color, dst: Color) Color {
    return .{ .r = mix(src.r, dst.r), .g = mix(src.g, dst.g), .b = mix(src.b, dst.b), .a = 255 };
}

/// Chrome's (Skia's) 8-bit blend, measured against the remake running in Chrome:
/// alpha 0.9 becomes 230, the source scales by 230+1 and the destination by
/// 256-230, each truncated. Rounding 0.9*s + 0.1*d instead is off by 1-2 on
/// most of tile 0's pixels.
const ALPHA8: u16 = @round(TILE0_ALPHA * 255);
fn mix(s: u8, d: u8) u8 {
    return @intCast(((@as(u16, s) * (ALPHA8 + 1)) >> 8) + ((@as(u16, d) * (256 - ALPHA8)) >> 8));
}

/// `len` bytes of the cart's RAM window above its statics and stack.
fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}
