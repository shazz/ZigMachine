// --------------------------------------------------------------------------
// Union main — the running character (efmain.js sprite). 7 frames of 32x28 on
// plane 1 (actors), fixed on screen while the world scrolls under it, with a
// 4-copy palette-dimmed ghost trail. Faithful to efmain.js: pinpinNb += 0.6,
// wraps >7 (drawn frame = floor) → a 12-frame cycle; ghosts at x-1/-2/-4/-5
// with alpha 0.7/0.5/0.3/0.1.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const gpu = @import("../union_common/gpu.zig");
const LogicalFB = zg.LogicalFB;
const box = @import("runner_box.zig");
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

pub const SW: usize = 224; // sprite sheet width
pub const FW: i16 = 32; // frame w
const FH: i16 = 28; // frame h
pub const X0: i16 = 200; // fixed top-left on the fullscreen plane (centre 216,133)
pub const Y0: i16 = 119;
pub const ROWS = .{ Y0, Y0 + FH }; // the rows the runner and its ghosts are drawn on
/// The columns they are drawn in at any speed scale s in [0, 1]: the widest ghost (g 3) spans
/// CENTER_X + GHOST_CX*s -+ FW*(1 + (GHOST_Z-1)*s)/2 = [200 - 57s, 232 + 7s], within [143, 239];
/// the runner 200..232. A margin each side (the comptime check below pins full speed).
pub const BOX = .{ 128, 256 };

pub const sprites = @embedFile("../../assets/screens/union_main/sprites.raw");
const p1_pal = convertU8ArraytoColors(@embedFile("../../assets/screens/union_main/p1.pal"));

const CENTER_X: f32 = 216; // X0 + FW/2 (the runner is drawn centred here)
// Trailing ghost copies: progressively further left and MORE x-zoomed than the
// literal efmain.js values (which, under an opaque main, barely showed) so the
// speed streak reads clearly. Centre offset + horizontal zoom + alpha per copy.
const GHOST_CX = [4]f32{ -4, -10, -17, -25 };
const GHOST_Z = [4]f32{ 1.5, 2.0, 2.5, 3.0 };
const GHOST_A = [4]u8{ 179, 128, 77, 26 }; // 0.7/0.5/0.3/0.1
const GHOST_BASE: u8 = 16; // ghost g uses palette [GHOST_BASE + g*8 + idx]

pub const Runner = struct {
    blitter: zg.Blitter = .{},
    nb: f32 = 0,

    pub fn init(self: *Runner, zigos: *ZigOS) void {
        self.blitter.init();
        self.nb = 0;
        const p1: *LogicalFB = &zigos.lfbs[1];
        p1.is_enabled = true;
        p1.setOverscanBuffer();
        p1.setPalette(p1_pal);
        p1.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 }); // transparent
        // Dimmed/alpha copies of the 7 sprite colours for the ghost trail.
        for (0..4) |g| {
            const base: u8 = GHOST_BASE + @as(u8, @intCast(g)) * 8;
            var c: u8 = 1;
            while (c < 8) : (c += 1) {
                const col = p1_pal[c];
                p1.setPaletteEntry(base + c, Color{ .r = col.r, .g = col.g, .b = col.b, .a = GHOST_A[g] });
            }
        }
    }

    pub fn update(self: *Runner) void {
        self.nb += 0.6;
        if (self.nb > 7) self.nb = 0;
    }

    // `scale` (1.0 = full speed) attenuates the ghost trail: as it → 0 the ghosts
    // collapse toward the runner's own position/size and vanish under it, so a
    // slowed-down sprite loses its speed streak.
    /// At full speed the runner and its ghosts are one ready picture of the whole BOX
    /// (runner_box.zig), 0 around them: draw() then paints the box itself, and the caller
    /// does not erase it first.
    pub fn paintsBox(self: *const Runner, scale: f32) bool {
        return scale == 1.0 and @as(usize, @intFromFloat(self.nb)) < FRAMES;
    }

    pub fn draw(self: *Runner, zigos: *ZigOS, scale: f32) void {
        const p1: *LogicalFB = &zigos.lfbs[1]; // erased by the caller (main.zig) unless paintsBox
        const f: usize = @intFromFloat(self.nb);
        if (self.paintsBox(scale)) return gpu.put(p1, zg.blit.Image.init(&box.pictures[f], box.W), null, BOX[0], Y0, null);
        // Ghosts outermost (dimmest) first — each horizontally x-zoomed about its
        // centre for the speed streak — then the opaque runner on top.
        var g: usize = 4;
        while (g > 0) {
            g -= 1;
            if (scale == 1.0) { // full speed (the main screen's whole life): the ghost is a ready picture
                blitFixed(p1, f, g);
                continue;
            }
            const cx = CENTER_X + GHOST_CX[g] * scale;
            const z = 1.0 + (GHOST_Z[g] - 1.0) * scale;
            blitStretch(p1, f, cx, Y0, z, g);
        }
        self.blitter.blitImage(p1, X0, Y0, sprites, @intCast(SW), @as(u16, @intCast(f)) * @as(u16, @intCast(FW)), 0, @intCast(FW), @intCast(FH), 0);
    }
};

// The sprite sheet once per ghost with its colours moved into the ghost's own
// palette slots (non-zero idx -> base + idx), built at compile time, so a ghost
// column is a plain keyed CHISEL copy (the CPU loop stored 28 bytes a column,
// each a blocking DDR write on the board).
const ghost_sheets: [4][sprites.len]u8 = blk: {
    @setEvalBranchQuota(100_000);
    var t: [4][sprites.len]u8 = undefined;
    for (0..4) |g| for (sprites, 0..) |idx, i| {
        t[g][i] = if (idx == 0) 0 else GHOST_BASE + @as(u8, @intCast(g)) * 8 + idx;
    };
    break :blk t;
};

// Blit sprite frame `f` centred at x=cx, stretched horizontally by `z` (the
// ghost speed-streak): one source column per destination column, one keyed
// 1-wide CHISEL blit each, clipped by the machine like the CPU loop was.
fn blitStretch(fb: *LogicalFB, f: usize, cx: f32, y: i16, z: f32, g: usize) void {
    const pw: i16 = @intCast(fb.fb_w);
    const scaled: f32 = @as(f32, @floatFromInt(FW)) * z;
    const x0: i16 = @intFromFloat(cx - scaled * 0.5);
    const cols: i16 = @intFromFloat(@ceil(scaled));
    const sx0: u16 = @intCast(f * @as(usize, @intCast(FW)));
    var dc: i16 = 0;
    while (dc < cols) : (dc += 1) {
        const src: usize = @intFromFloat(@as(f32, @floatFromInt(dc)) / z);
        if (src >= @as(usize, @intCast(FW))) break;
        const px = x0 + dc;
        if (px < 0 or px >= pw) continue;
        gpu.putTile(fb, px, y, &ghost_sheets[g], @intCast(SW), sx0 + @as(u16, @intCast(src)), 0, 1, @intCast(FH));
    }
}

// At full speed (scale 1) every ghost has the same size and place, so each of the 7 sprite frames
// stretched for each of the 4 ghosts is made ONCE, here at compile time, with blitStretch's own f32
// arithmetic and column map, and a frame's ghost is one keyed CHISEL copy (the 1-wide column
// blits above are the fallback while the runner slows down or speeds up). 7 x 288 columns x 28
// rows = 56 KB of the wasm data segment.
pub const FRAMES = 7;
const FWU: usize = 32; // FW, FH as usize
pub const FHU: usize = 28;
pub const FIXED_COLS = [4]usize{ ghostCols(0), ghostCols(1), ghostCols(2), ghostCols(3) };
pub const FIXED_OFF = [4]usize{ 0, FRAMES * FHU * FIXED_COLS[0], FRAMES * FHU * (FIXED_COLS[0] + FIXED_COLS[1]), FRAMES * FHU * (FIXED_COLS[0] + FIXED_COLS[1] + FIXED_COLS[2]) };

fn zoom(g: usize) f32 {
    return 1.0 + (GHOST_Z[g] - 1.0) * @as(f32, 1.0);
}
fn ghostCols(g: usize) usize {
    return @intFromFloat(@ceil(@as(f32, @floatFromInt(FWU)) * zoom(g)));
}
pub fn left(g: usize) i16 {
    const cx = CENTER_X + GHOST_CX[g] * @as(f32, 1.0);
    return @intFromFloat(cx - @as(f32, @floatFromInt(FWU)) * zoom(g) * 0.5);
}

comptime { // main.zig erases only BOX: every full-speed ghost and the runner lie inside it
    for (0..4) |g| if (left(g) < BOX[0] or @as(i32, left(g)) + @as(i32, FIXED_COLS[g]) > BOX[1]) @compileError("a ghost leaves runner.BOX");
    if (X0 < BOX[0] or X0 + FW > BOX[1]) @compileError("the runner leaves runner.BOX");
}

/// Ghost g's sheet, FRAMES pictures side by side (row-major, FRAMES * cols wide), 0 where the stretch leaves a gap.
pub const fixed_sheet: [FRAMES * FHU * (FIXED_COLS[0] + FIXED_COLS[1] + FIXED_COLS[2] + FIXED_COLS[3])]u8 = blk: {
    @setEvalBranchQuota(2_000_000);
    var t = [_]u8{0} ** (FRAMES * FHU * (FIXED_COLS[0] + FIXED_COLS[1] + FIXED_COLS[2] + FIXED_COLS[3]));
    for (0..4) |g| {
        const w = FIXED_COLS[g];
        const z = zoom(g);
        for (0..FRAMES) |f| for (0..w) |dc| {
            const src: usize = @intFromFloat(@as(f32, @floatFromInt(dc)) / z);
            if (src >= FWU) break;
            for (0..FHU) |r| t[FIXED_OFF[g] + r * FRAMES * w + f * w + dc] = ghost_sheets[g][r * SW + f * FWU + src];
        };
    }
    break :blk t;
};

fn blitFixed(fb: *LogicalFB, f: usize, g: usize) void {
    if (f >= FRAMES) return; // nb can read exactly 7: the old code found no sheet column there either
    const w = FIXED_COLS[g];
    const img = fixed_sheet[FIXED_OFF[g]..][0 .. FRAMES * FHU * w];
    gpu.putTile(fb, left(g), Y0, img, @intCast(FRAMES * w), @intCast(f * w), 0, @intCast(w), @intCast(FHU));
}
