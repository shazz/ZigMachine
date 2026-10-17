// --------------------------------------------------------------------------
// REPLICANTS — "Double Dragon II" cracktro.
//
// Ported from the CODEF HTML5 remake by NoNameNo (wab.com screen 515, MIT),
// which is itself a remake of the Atari ST original: code and graphics by
// FURY of the Replicants, music by Mad Max (Jochen Hippel).
//
// Reference kept at prototypes/codef/515/ (tools/fetch_codef.py 515).
//
// What the screen is, from the original source rather than from its look:
//
//   * ONE vertical scrolltext, rendered into a narrow 12x108 strip, drawn back
//     to the screen THREE times per scanline — a centre copy stretched
//     horizontally per row by LGLINE (107px at the ends, 24px at the waist:
//     an hourglass pinch), and a left and a right copy at 1:1 that wobble
//     horizontally on a sine, the right one mirrored.
//   * The vertical axis is distorted too: SCLINE says how many screen rows
//     each strip row occupies (3 at the ends, 1 at the waist). Its 109 entries
//     sum to exactly 200 — the whole screen height, which is what proves the
//     table is per-ST-row and not per-canvas-row.
//   * An 11-point Lissajous "snake" of connected lines, filled with a vertical
//     colour gradient. The original draws the lines into an offscreen, then
//     composites the gradient INTO them with 'source-in' — a mask, not a
//     texture — so here each snake pixel simply takes the gradient entry for
//     its own screen row, which is the same result without the offscreen.
//   * The logo is an OVERLAY, not a backdrop: 92% transparent, carrying the two
//     vertical REPLICANTS wordmarks that frame the scrollers.
//
// ONE PLANE. The original composites all three layers onto a single canvas and
// so does this port: the sealed host pays a full 800x280 RGBA copy, an upload
// and one more composited canvas layer for every ENABLED plane every frame, so
// a layer that can be painted in the right order onto one plane should be.
// tools/reps5_assets.py therefore emits a single shared palette for the font,
// the logo and the snake's gradient together — they come to 167 of the 256
// entries a plane has, so nothing had to be quantised or subsampled.
//
// COMPOSITING ORDER: scrollers, then the logo, then the snake ON TOP — the
// original's order. `myimage.draw()` runs BEFORE the snake's offscreen is
// composited, so on wab.com the snake passes OVER the wordmarks. The port had it
// the other way round (logo last) until Matt confirmed the original's order;
// they overlap only at the wordmarks' inner edges, so the difference is subtle
// but real.
//
// GEOMETRY DECISION (worth a second opinion): the remake's canvas is 640x480,
// i.e. 320x240 doubled — 40 rows taller than an ST can show. It places the logo
// at y=20 and the distorter at y=48 (ST-equivalent), so on a real 200-line
// screen the bottom of the hourglass would fall off. This port anchors both to
// the screen instead: the logo fills 0..199 (it is exactly 320x200 after
// halving) and the distorter's 200 rows map to rows 0..199, so the full pinch
// is visible and symmetric. Nothing else was rescaled.
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

// The same two as usize, for indexing — keeping the u16 forms for the ZigOS
// calls that take them and never mixing the two silently.
const SCREEN_W: usize = WIDTH;
const SCREEN_H: usize = HEIGHT;
const SCREEN_PIXELS: usize = SCREEN_W * SCREEN_H;

// music — the screen's own tune, played by its own 68000 (docs/music/).
// Mad Max, "S.O.S." from the So Watt demo (1989) — the same file the CODEF
// remake loads (screens/515/S_O_S.sndh), already on the shelf for LEONARD.
const MUSIC = "sos.sndh";

// One plane, one palette: scrollers, then the logo, then the snake on top.
const PLANE = 0;

// font: 60 glyphs of 12x14 stacked vertically, first char 32 (space).
// NOT halved with the rest of the geometry — the side copies draw the strip at
// 1:1, so 12x14 already IS the ST glyph.
const GLYPH_W: usize = 12;
const GLYPH_H: usize = 14;
const FIRST_CHAR: u8 = 32;
const NB_GLYPHS: usize = 60;

// the vertical scroll strip: 12 wide, 14*8-4 tall, as the original sizes it.
const STRIP_W: usize = 12;
const STRIP_H: usize = 108;
const SCROLL_SPEED: usize = 1; // scrolltext_vertical init(..., 1) — 1px per frame

// The three copies: centre x of each, and the amplitude of the sides' wobble.
// (Original: 320, 80 - sin*40 and 640-80 - sin(-)*40 on a 640-wide canvas.)
const CENTRE_X: i32 = 160;
const SIDE_L_X: f32 = 40.0;
const SIDE_R_X: f32 = 280.0;
const SIDE_AMP: f32 = 20.0;
const SINUS_INC: f32 = 0.058; // per strip row, straight from the original

// The snake. Amplitudes are already in 320-space in the original (it draws into
// a 320x240 offscreen), so they are NOT halved; only the centre moves, 120 -> 100.
const SNAKE_POINTS: usize = 11;
const SNAKE_CX: i32 = 160;
const SNAKE_CY: i32 = 100;
const AMP_BIG: i32 = 64;
const AMP_SMALL: i32 = 16;
const P1: f32 = 45.0;
const P2: f32 = 23.0;
const P3: f32 = 62.0;
const P4: f32 = 35.0;
// per-POINT advance (spreads the 11 points along the curve)
const DW1: f32 = 0.3 * 1.3;
const DW2: f32 = 0.9 * 1.3;
const DW3: f32 = 0.4 * 1.3;
const DW4: f32 = 0.7 * 1.3;
// per-FRAME advance (moves the whole curve, much slower)
const FW1: f32 = 0.03 / 1.2;
const FW2: f32 = 0.09 / 1.2;
const FW3: f32 = 0.04 / 1.2;
const FW4: f32 = 0.07 / 1.2;

// The same phases as fixtrig angles (u32 turns), folded at compile time
// (float is fine there): the snake costs table lookups, not soft-float cos.
const A_P = [4]trig.Angle{ trig.angle(P1), trig.angle(P2), trig.angle(P3), trig.angle(P4) };
const A_DW = [4]trig.Angle{ trig.angle(DW1), trig.angle(DW2), trig.angle(DW3), trig.angle(DW4) };
const A_FW = [4]trig.Angle{ trig.angle(FW1), trig.angle(FW2), trig.angle(FW3), trig.angle(FW4) };

// The side copies' wobble depends on the strip row only, so the whole x
// table is built here once (f32 maths exactly as the original ran it).
const SIDE_X: [SCLINE_N][2]i32 = blk: {
    @setEvalBranchQuota(100_000);
    var t: [SCLINE_N][2]i32 = undefined;
    var sinus: f32 = 0;
    for (&t) |*e| {
        const wobble = @sin(sinus) * SIDE_AMP;
        e.* = .{ @intFromFloat(SIDE_L_X - wobble), @intFromFloat(SIDE_R_X + wobble) };
        sinus += SINUS_INC;
    }
    break :blk t;
};

// Which points are joined. Straight from the original's eleven line() calls.
const SNAKE_EDGES = [_][2]u8{
    .{ 0, 1 }, .{ 0, 2 }, .{ 1, 3 }, .{ 2, 4 }, .{ 3, 5 }, .{ 4, 6 },
    .{ 5, 7 }, .{ 6, 8 }, .{ 7, 9 }, .{ 8, 10 }, .{ 9, 10 },
};

// The characters the font actually carries, in order from FIRST_CHAR.
const SCROLL_TEXT =
    "                    REPLICANTS PRESENT DOUBLE DRAGON II ... " ++
    "ORIGINAL SCREEN CODED AND DRAWN BY FURY, MUSIC BY MAD MAX ... " ++
    "HTML5 REMAKE BY NONAMENO USING CODEF ... " ++
    "NOW RUNNING ON THE ZIGMACHINE, A FANTASY CONSOLE IN ZIG AND WEBASSEMBLY ... " ++
    "GREETINGS TO EVERYONE STILL KEEPING THE ATARI ST ALIVE ...        ";

// --------------------------------------------------------------------------
// Assets — all three index the ONE palette built by tools/reps5_assets.py.
// --------------------------------------------------------------------------
const screen_pal = convertU8ArraytoColors(@embedFile("../assets/screens/reps5/screen_pal.dat"));
const logo_b = @embedFile("../assets/screens/reps5/logo.raw");
const font_b = @embedFile("../assets/screens/reps5/font.raw");
// The snake's fill: one palette index per screen row (see the header note).
const gradient_row = @embedFile("../assets/screens/reps5/gradient_idx.dat");

comptime {
    if (logo_b.len != SCREEN_PIXELS) @compileError("logo.raw is not 320x200");
    if (font_b.len != NB_GLYPHS * GLYPH_H * GLYPH_W) @compileError("font.raw is not 60 12x14 glyphs");
    if (gradient_row.len != SCREEN_H) @compileError("gradient_idx.dat is not one entry per screen row");
}

/// The logo overlay as comptime runs of ink. The logo is 92% transparent (4942
/// of 64000 pixels are ink), so walking it as runs turns the per-frame overlay
/// into ~500 copies instead of 64000 per-pixel transparency tests.
const logo_runs = zg.spans.build(logo_b, SCREEN_W, 0);

// --------------------------------------------------------------------------
// The distortion tables (extracted verbatim from the original source).
//
// SCLINE[i] = how many screen rows strip row i occupies. 109 entries, summing
// to exactly 200. LGLINE[row] = the centre copy's width on that screen row.
// --------------------------------------------------------------------------
const SCLINE_N = 109;
const SCLINE = [_]u8{
    3, 3, 3, 2, 2, 3, 3, 2, 2, 2, 3, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 1, 1, 2, 2,
    1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 2, 2, 1,
    1, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 3, 2, 2, 2, 3, 3, 2, 2, 3, 3, 3,
};

const LGLINE = [_]u8{
    107, 107, 107, 107, 107, 107, 105, 105, 105, 105, 103, 103, 103, 101, 101, 99,
    99, 97, 97, 95, 95, 93, 93, 91, 91, 89, 89, 87, 87, 85, 85, 83,
    83, 81, 81, 79, 79, 77, 77, 75, 75, 73, 73, 71, 71, 69, 68, 68,
    66, 66, 64, 64, 62, 62, 60, 60, 58, 58, 56, 56, 54, 54, 52, 52,
    50, 50, 48, 48, 46, 46, 44, 44, 42, 42, 40, 40, 38, 38, 36, 36,
    34, 34, 32, 32, 30, 30, 28, 28, 26, 26, 24, 24, 24, 24, 24, 24,
    24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 26, 26,
    28, 28, 30, 30, 32, 32, 34, 34, 36, 36, 38, 38, 40, 40, 42, 42,
    44, 44, 46, 46, 48, 48, 50, 50, 52, 52, 54, 54, 56, 56, 58, 58,
    60, 60, 62, 62, 64, 64, 66, 66, 68, 68, 69, 71, 71, 73, 73, 75,
    75, 77, 77, 79, 79, 81, 81, 83, 83, 85, 85, 87, 87, 89, 89, 91,
    91, 93, 93, 95, 95, 97, 97, 99, 99, 101, 101, 103, 103, 103, 105, 105,
    105, 105, 107, 107, 107, 107, 107, 107,
};

comptime {
    var rows: usize = 0;
    for (SCLINE) |n| rows += n;
    if (rows != SCREEN_H) @compileError("SCLINE does not sum to the screen height");
    if (LGLINE.len != SCREEN_H) @compileError("LGLINE is not one width per screen row");
}

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    // the vertical scroll strip, as palette indices
    strip: [STRIP_H][STRIP_W]u8,
    // which character sits at the top of the strip, and how far into it
    top_char: usize,
    top_row: usize,

    // the snake's Lissajous phases (see the per-frame vs per-point note above)
    w: [4]trig.Angle,
    sx: [SNAKE_POINTS]i32, // ST pixels
    sy: [SNAKE_POINTS]i32,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSongTune(MUSIC, 0);

        const fb: *LogicalFB = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setPalette(screen_pal);
        // Load-bearing for all three layers: index 0 is the cleared screen, the
        // font's dropped-out field and the logo's 92% transparency.
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        // The cart's Demo is `undefined` memory — struct field defaults are
        // never applied, so every field has to be set here or the scene picks
        // up whatever the previous cart left behind.
        self.top_char = 0;
        self.top_row = 0;
        self.w = .{ 0, 0, 0, 0 };
        @memset(&self.sx, 0);
        @memset(&self.sy, 0);

        self.fillStrip();
    }

    /// Repaint the whole strip from the text at the current scroll position.
    /// Cheap enough at 12x108 to do outright, and it keeps the scroll state to
    /// two integers instead of a shifting buffer that can drift out of step.
    fn fillStrip(self: *Demo) void {
        for (&self.strip, 0..) |*dst, r| {
            const global = self.top_row + r;
            const ch_index = (self.top_char + global / GLYPH_H) % SCROLL_TEXT.len;
            const row_in_glyph = global % GLYPH_H;

            const c = SCROLL_TEXT[ch_index];
            const glyph: usize = if (c < FIRST_CHAR or c >= FIRST_CHAR + NB_GLYPHS)
                0 // anything the font does not carry shows as a space
            else
                c - FIRST_CHAR;

            const src = (glyph * GLYPH_H + row_in_glyph) * GLYPH_W;
            dst.* = font_b[src..][0..STRIP_W].*;
        }
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;

        // Scroll the text up one pixel per frame (speed 1 in the original).
        self.top_row += SCROLL_SPEED;
        while (self.top_row >= GLYPH_H) {
            self.top_row -= GLYPH_H;
            self.top_char = (self.top_char + 1) % SCROLL_TEXT.len;
        }
        self.fillStrip();

        // The snake: eleven points spread along the curve by the per-POINT
        // advance, then the phases rewound to their per-FRAME advance, so the
        // shape crawls slowly while its points stay spread out. Reproducing that
        // two-speed trick is the whole character of the movement.
        var w = self.w;
        for (&self.sx, &self.sy) |*px, *py| {
            const x = AMP_BIG * trig.cos(w[0] +% A_P[0]) + AMP_SMALL * trig.cos(w[1] +% A_P[1]);
            const y = AMP_BIG * trig.cos(w[2] +% A_P[2]) + AMP_SMALL * trig.cos(w[3] +% A_P[3]);
            // centre + offset is positive, so the shift truncates like the float cast
            px.* = (SNAKE_CX * trig.ONE + x) >> 16;
            py.* = (SNAKE_CY * trig.ONE + y) >> 16;
            for (&w, A_DW) |*q, d| q.* +%= d;
        }
        for (&self.w, A_FW) |*q, d| q.* +%= d;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb: *LogicalFB = &zigos.lfbs[PLANE];

        // The compositing order, onto one plane (see the header note).
        @memset(fb.fb[0..SCREEN_PIXELS], 0);
        self.drawScrollers(fb);
        drawLogo(fb);
        self.drawSnake(fb);
    }

    /// The distorter: walk the strip rows, and for each one emit SCLINE[row]
    /// screen rows carrying three copies of it.
    fn drawScrollers(self: *Demo, fb: *LogicalFB) void {
        var y: usize = 0;
        for (SCLINE, 0..) |repeat, strip_row| {
            const src = &self.strip[@min(strip_row, STRIP_H - 1)];
            const xs = SIDE_X[strip_row];

            for (0..repeat) |_| {
                if (y >= SCREEN_H) break;
                const row = fb.fb[y * SCREEN_W ..][0..SCREEN_W];

                // centre copy — stretched to this row's width, pinched at the waist
                stretchRow(row, src, LGLINE[y]);
                // left and right copies at 1:1, wobbling in opposite directions;
                // the right one mirrored (the original's negative x scale)
                copyRow(row, src, xs[0], false);
                copyRow(row, src, xs[1], true);
                y += 1;
            }
        }
    }

    fn drawSnake(self: *Demo, fb: *LogicalFB) void {
        for (SNAKE_EDGES) |e| {
            const a = e[0];
            const b = e[1];
            line(fb, self.sx[a], self.sy[a], self.sx[b], self.sy[b]);
        }
    }
};

/// The centre copy: the 12-pixel strip row stretched to `width` px, centred on
/// CENTRE_X. Source column `sx` covers destination pixels `i` where
/// `i * STRIP_W / width == sx`, which is a contiguous run — so each source
/// pixel is one fill rather than `width` separate per-pixel writes.
fn stretchRow(row: *[SCREEN_W]u8, src: *const [STRIP_W]u8, width: usize) void {
    if (width == 0) return;
    const left = CENTRE_X - @as(i32, @intCast(width / 2));

    for (src, 0..) |v, sx| {
        if (v == 0) continue; // the font's dropped-out field
        // ceil(sx*width/STRIP_W) .. ceil((sx+1)*width/STRIP_W), the exact
        // inverse of the nearest-neighbour mapping above.
        const run_start = (sx * width + STRIP_W - 1) / STRIP_W;
        const run_end = @min(((sx + 1) * width + STRIP_W - 1) / STRIP_W, width);

        const x0 = @max(left + @as(i32, @intCast(run_start)), 0);
        const x1 = @min(left + @as(i32, @intCast(run_end)), @as(i32, SCREEN_W));
        if (x1 > x0) @memset(row[@intCast(x0)..@intCast(x1)], v);
    }
}

/// A side copy: the strip row at 1:1, centred on `cx`, optionally mirrored
/// (the original's negative horizontal scale on the right-hand copy).
fn copyRow(row: *[SCREEN_W]u8, src: *const [STRIP_W]u8, cx: i32, mirror: bool) void {
    const left = cx - @as(i32, STRIP_W / 2);

    for (0..STRIP_W) |i| {
        const x = left + @as(i32, @intCast(i));
        if (x < 0 or x >= SCREEN_W) continue;
        const v = src[if (mirror) STRIP_W - 1 - i else i];
        if (v != 0) row[@intCast(x)] = v;
    }
}

/// The logo overlay, as precomputed runs of ink. Drawn over the scrollers but
/// UNDER the snake, which is the original's order (see the header).
fn drawLogo(fb: *LogicalFB) void {
    for (0..SCREEN_H) |y| {
        const row = y * SCREEN_W;
        for (logo_runs.row(y)) |s| {
            @memcpy(fb.fb[row + s.x0 .. row + s.x1], logo_b[row + s.x0 .. row + s.x1]);
        }
    }
}

/// Bresenham, colouring each pixel with the gradient entry for its own row —
/// which is what the original's 'source-in' composite amounts to.
fn line(fb: *LogicalFB, ax: i32, ay: i32, x1: i32, y1: i32) void {
    var x0 = ax;
    var y0 = ay;

    const dx: i32 = @intCast(@abs(x1 - x0));
    const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
    const sx: i32 = if (x0 < x1) 1 else -1;
    const sy: i32 = if (y0 < y1) 1 else -1;
    var err = dx + dy;

    while (true) {
        if (x0 >= 0 and x0 < WIDTH and y0 >= 0 and y0 < HEIGHT) {
            const y: usize = @intCast(y0);
            fb.fb[y * SCREEN_W + @as(usize, @intCast(x0))] = gradient_row[y];
        }
        if (x0 == x1 and y0 == y1) break;
        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}
