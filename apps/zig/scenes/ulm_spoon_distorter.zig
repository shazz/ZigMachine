// --------------------------------------------------------------------------
// ULM — "Parallax Distorter", Gunstick's fullscreen screen from THE DARK SIDE OF
// THE SPOON.
//
// Ported from the CODEF HTML5 remake by Dyno (wab.com screen 287, 2014, CODEF MIT).
// Code and music sampling: Gunstick. Font: Oxar. Background: Dizzy of Tool 8.
// Sample: "You" by Boytronic (docs/music/ulm_spoon_distorter_you.raw).
//
// Reference kept at prototypes/codef/287/. Assets and the verbatim tables in
// ulm_spoon_distorter/tables.zig: tools/ulm_spoon_distorter_assets.py.
//
// What the remake does. The logical screen is 384x270 and every one of its rows
// is two copies from offscreens:
//   back:   back.png (8x168) tiled into a 392x168 canvas, row
//           (line + 150 + bounce_back) % 168, starting at column
//           floor(back_wave(wave_pos + line) / 2) % 8;
//   scroll: a 1152x20 canvas holding the scrolltext from letter letter_num,
//           row (line + 2 + bounce_front) % 20, starting at column
//           front_wave(wave_pos + line) - letter_decal, drawn over the back.
// So the 20-row text band repeats down the whole screen and every scanline
// is shifted by its own wave: that is the "fullscreen distorter".
//
// The waves are running sums of the source's delta tables (do_precalc_wave). An
// intro sequence plays once, then the main sequence repeats, each repeat
// offset by its own total (get_sum). That offset is what moves the text
// forward: nothing else scrolls it. letter_num is the first letter whose span
// holds the smallest front value on screen, so the text buffer always covers
// the widest row.
//
// Timing is the remake's useDeltaTime = 1 mode: iteration = floor(ms / 20),
// wave_pos = 5 * iteration. The bounce is |sin(iteration * 1000 / 12891.249)|
// (sample_length of you-low.wav), time-driven like the original, not locked to
// the audio.
//
// Geometry: 384x270 in the 400x280 overscan plane, centred at (8, 5). Every
// border is opened with the res-flicker trick on every line (openBorders(.all)).
// --------------------------------------------------------------------------

const std = @import("std");
const zg = @import("zigos");
const convertU8ArraytoColors = zg.convertU8ArraytoColors;
const t = @import("ulm_spoon_distorter/tables.zig");

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const blit = zg.blit;

const MUSIC = "ulm_spoon_distorter_you.raw";
const PLANE = 0;

// screen_width, screen_height, back_width, back_height, font_height
const SCREEN_W: usize = 384;
const SCREEN_H: usize = 270;
const BACK_W: usize = 8;
const BACK_H: usize = 168;
const FONT_H: usize = 20;
const BACK_CANVAS_W: usize = SCREEN_W + BACK_W; // 392
const SCROLL_W: usize = SCREEN_W * 3; // 1152
const FONT_W: usize = 320;

const PW: usize = zg.PHYSICAL_WIDTH;
const PH: usize = zg.PHYSICAL_HEIGHT;
const X0: usize = (PW - SCREEN_W) / 2; // 8
const Y0: usize = (PH - SCREEN_H) / 2; // 5

// the remake's default sample (you-low.wav / CODEF player): bounce_decal 0
const SAMPLE_LENGTH: f64 = 12891.249;
const BOUNCE_DECAL: f64 = 0;
const BOUNCE_BACK_AMP: f64 = 25;
const BOUNCE_FRONT_AMP: f64 = 10;
const BACK_ROW_OFFSET: usize = 150;
const FONT_ROW_OFFSET: usize = 2;
const MS_PER_ITERATION: f64 = 20;
const WAVE_STEP: u64 = 5;

// --------------------------------------------------------------------------
// Assets
// --------------------------------------------------------------------------
const back_b = @embedFile("../assets/screens/ulm_spoon_distorter/back.raw");
const font_b = @embedFile("../assets/screens/ulm_spoon_distorter/font.raw");
const screen_pal = convertU8ArraytoColors(@embedFile("../assets/screens/ulm_spoon_distorter/screen_pal.dat"));

comptime {
    if (back_b.len != BACK_W * BACK_H) @compileError("back.raw is not 8x168");
    if (font_b.len != FONT_W * 200) @compileError("font.raw is not 320x200");
    // every glyph lies inside the sheet (blit would clip it, silently)
    for (t.letter) |g| {
        if (@as(usize, g.x) + g.w > FONT_W or @as(usize, g.y) + FONT_H > font_b.len / FONT_W)
            @compileError("glyph outside font.raw");
    }
}

const font_img = blit.Image.init(font_b, FONT_W);

// --------------------------------------------------------------------------
// Precalc (do_precalc_wave / do_precalc_position), done at compile time
// --------------------------------------------------------------------------
fn seqLen(comptime seq: []const []const i8) usize {
    var n: usize = 0;
    for (seq) |w| n += w.len;
    return n;
}

/// Running sum over the sequence's delta tables. Every sum fits i16 (max 6941).
fn precalcWave(comptime seq: []const []const i8) [seqLen(seq)]i16 {
    @setEvalBranchQuota(10_000_000);
    var out: [seqLen(seq)]i16 = undefined;
    var count: i32 = 0;
    var x: usize = 0;
    for (seq) |w| for (w) |d| {
        count += d;
        out[x] = @intCast(count);
        x += 1;
    };
    return out;
}

const front_intro = precalcWave(&t.front_intro_wave_table);
const front_main = precalcWave(&t.front_main_wave_table);
const back_intro = precalcWave(&t.back_intro_wave_table);
const back_main = precalcWave(&t.back_main_wave_table);

/// get_wave never goes negative: the intro stays >= 0, the main table offset by
/// the intro's last value stays >= 0, and each repeat adds a positive total.
/// render()'s @intCast of back_x and buildScrollCanvas's usize letter index
/// depend on this (a negative front wave would also hang the letter search,
/// in the original too), so prove it rather than trust it.
fn assertWaveNonNegative(comptime intro: []const i16, comptime main: []const i16) void {
    const intro_last = intro[intro.len - 1];
    if (std.mem.min(i16, intro) < 0 or
        @as(i32, std.mem.min(i16, main)) + intro_last < 0 or
        main[main.len - 1] < 0)
        @compileError("wave sums go negative");
}
comptime {
    @setEvalBranchQuota(100_000);
    assertWaveNonNegative(&front_intro, &front_main);
    assertWaveNonNegative(&back_intro, &back_main);
}

/// character -> index into t.letter
const glyph_of: [256]u8 = blk: {
    @setEvalBranchQuota(100_000);
    var m = [_]u8{0xFF} ** 256;
    for (t.letter, 0..) |g, j| m[g.c] = j;
    for (t.text) |c| if (m[c] == 0xFF) @compileError("scrolltext character without a glyph");
    break :blk m;
};

/// position[i] = x just past letter i of the text
const position: [t.text.len]i32 = blk: {
    @setEvalBranchQuota(100_000);
    var out: [t.text.len]i32 = undefined;
    var count: i32 = 0;
    for (t.text, 0..) |c, i| {
        count += t.letter[glyph_of[c]].w;
        out[i] = count;
    }
    break :blk out;
};

/// get_sum: the table repeats, each repeat offset by its last value.
fn getSum(comptime T: type, array: []const T, index: u64, decal: i64) i64 {
    const n: u64 = array.len;
    const repeats: i64 = @intCast(index / n);
    const last: i64 = array[array.len - 1];
    const m: usize = @intCast(index % n);
    return decal + repeats * last + @as(i64, array[m]);
}

/// get_wave: the intro once, then the main table from the intro's last value.
fn getWave(intro: []const i16, main: []const i16, i: u64) i64 {
    if (i < intro.len) return getSum(i16, intro, i, 0);
    return getSum(i16, main, i - intro.len, intro[intro.len - 1]);
}

/// get_position: x where letter i starts
fn getPosition(i: i64) i64 {
    if (i <= 0) return 0;
    return getSum(i32, &position, @intCast(i - 1), 0);
}

// --------------------------------------------------------------------------
// Offscreens and per-row scratch (module scope: kept out of the Demo struct)
// --------------------------------------------------------------------------
var back_canvas: [BACK_CANVAS_W * BACK_H]u8 = undefined;
var scroll_canvas: [SCROLL_W * FONT_H]u8 = undefined;
var front_row: [SCREEN_H]i64 = undefined;

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    elapsed_ms: f64,
    iteration: i64,
    wave_pos: u64,
    letter_num: i64,
    letter_decal: i64,
    scroll_built_for: i64, // letter_num the scroll canvas currently holds

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // A cart's Demo arrives zeroed: every field is set here.
        self.elapsed_ms = 0;
        self.iteration = 0;
        self.wave_pos = 0;
        self.letter_num = 0;
        self.letter_decal = 0;
        self.scroll_built_for = -1;

        // back_canvas.fill('#000000') is fully covered by the 49 tiles
        for (0..BACK_H) |y| for (0..BACK_CANVAS_W) |x| {
            back_canvas[y * BACK_CANVAS_W + x] = back_b[y * BACK_W + x % BACK_W];
        };

        zg.requestSong(MUSIC);
        // the unused 8/5-pixel frame is transparent: show black behind it
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.openBorders(.all); // overscan plane; top, sides and bottom opened every line
        fb.setPalette(screen_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.clearFrameBuffer(0);
    }

    /// anim()'s "Calc decal_x" and "Calc first letter".
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt; // the clock advances at the end of render(), after drawing
        var decal_x: i64 = std.math.maxInt(i64);
        for (&front_row, 0..) |*v, line| {
            v.* = getWave(&front_intro, &front_main, self.wave_pos + line);
            decal_x = @min(decal_x, v.*);
        }

        var dir: i64 = 0;
        if (decal_x > self.letter_decal) dir = 1;
        if (decal_x < self.letter_decal) dir = -1;
        var i: i64 = 0;
        while (decal_x < getPosition(self.letter_num + i) or getPosition(self.letter_num + i + 1) <= decal_x) i += dir;
        self.letter_num += i;
        self.letter_decal = getPosition(self.letter_num);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        if (self.scroll_built_for != self.letter_num) buildScrollCanvas(self.letter_num);
        self.scroll_built_for = self.letter_num;

        const phase = BOUNCE_DECAL + @as(f64, @floatFromInt(self.iteration)) * 1000.0 / SAMPLE_LENGTH;
        const bounce_back: usize = @intFromFloat(@floor(@abs(BOUNCE_BACK_AMP * @sin(phase))));
        const bounce_front: usize = @intFromFloat(@floor(@abs(BOUNCE_FRONT_AMP * @sin(phase))));

        const fb = &zigos.lfbs[PLANE];
        const screen = fb.fb[0 .. PW * PH];
        const view = blit.Dst.plane(fb).window(X0, Y0, SCREEN_W, SCREEN_H);
        const scroll_img = blit.Image.init(&scroll_canvas, SCROLL_W);
        for (0..SCREEN_H) |line| {
            const dst = screen[(Y0 + line) * PW + X0 ..][0..SCREEN_W];

            const back_wave = getWave(&back_intro, &back_main, self.wave_pos + line);
            const back_x: usize = @intCast(@mod(@divFloor(back_wave, 2), BACK_W)); // sums are >= 0
            const back_y = (line + BACK_ROW_OFFSET + bounce_back) % BACK_H;
            @memcpy(dst, back_canvas[back_y * BACK_CANVAS_W + back_x ..][0..SCREEN_W]);

            // >= 0: letter_decal <= decal_x <= every row's front value. A start
            // past the canvas draws nothing; the canvas edge clips, as drawPart does.
            const scroll_x: usize = @intCast(front_row[line] - self.letter_decal);
            const font_y = (line + FONT_ROW_OFFSET + bounce_front) % FONT_H;
            const row = blit.Rect{ .x = scroll_x, .y = font_y, .w = SCREEN_W, .h = 1 };
            blit.blit(view, scroll_img, row, 0, @intCast(line), 0, .copy);
        }
        // anim() advances the clock AFTER drawing, so the frame just drawn used
        // the previous frame's iteration; keep that order.
        // A NaN or negative dt from the host would poison the clock for good
        // (@intFromFloat on NaN, @intCast of a negative iteration: silent
        // garbage in ReleaseSmall). `dt > 0` is false for NaN too.
        if (dt > 0) self.elapsed_ms += dt;
        self.iteration = @intFromFloat(@floor(self.elapsed_ms / MS_PER_ITERATION));
        self.wave_pos = @as(u64, @intCast(self.iteration)) * WAVE_STEP;
    }
};

/// display_text: letters from `first` until the 1152-pixel canvas is full.
fn buildScrollCanvas(first: i64) void {
    @memset(&scroll_canvas, 0);
    const canvas = blit.Dst.buffer(&scroll_canvas, SCROLL_W);
    var x: usize = 0;
    var i: usize = @intCast(first);
    while (x < SCROLL_W) : (i += 1) {
        const g = t.letter[glyph_of[t.text[i % t.text.len]]];
        // the canvas's right edge clips the last glyph
        blit.blit(canvas, font_img, .{ .x = g.x, .y = g.y, .w = g.w, .h = FONT_H }, @intCast(x), 0, 0, .copy);
        x += g.w;
    }
}
