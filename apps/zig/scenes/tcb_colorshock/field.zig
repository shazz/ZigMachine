// --------------------------------------------------------------------------
// COLORSHOCK 2 — the 512-colour square field: a Lissajous pan over an overscan
// SCROLL plane (the hardware pan is the one thing that needs this plane).
//
// screen.js: myfond.setmidhandle() then, every frame,
//   myfond.draw(fond, 400 - sin(vbl*PI/100)*400, 180 - cos(vbl*PI/200)*300)
// setmidhandle() makes that the CENTRE, so the sheet's top-left lands at
// (X-623, Y-288) in ST pixels, with X = 200 - sin(vbl*PI/100)*200 in [0,400] and
// Y = 90 - cos(vbl*PI/200)*150 in [-60,240].
//
// Plane pixel (px,py) is canvas pixel (px-30, py-40), so it samples the sheet at
//   src_x = px + 593 - X,  src_y = py + 248 - Y.
// Over px in 0..399 and py in 0..279 that is src_x in [193,992] — 800 columns —
// and src_y in [8,587].
//
// The sheet is 1246x576 at ST scale and VERTICALLY PERIODIC with period 288 (row
// y and row y+288 are bit-identical), so src_y is taken mod 288 and only the
// 288-row tile is stored. The pan buffer is that tile repeated to 568 rows, so
// buffer pixel (x, y) is always tile pixel (x, y mod 288): that is also how the
// scroller and the logo, drawn INTO this buffer, are erased (ink.zig).
//
// VRAM. 800*568 = 454400 B here, plus the four 64000 B planes the machine
// allocates at boot and never reclaims. vramAlloc() has no pool guard, so the
// bound is checked at comptime below rather than trusted.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

const LogicalFB = zg.LogicalFB;
const DIR = "../../assets/screens/tcb_colorshock/";

// Assets (tools/private_tools/tcb_colorshock_assets.py)
pub const fond_b = @embedFile(DIR ++ "fond.raw");
const fond_rows = @embedFile(DIR ++ "fond_rows.pal");

pub const TILE_W: u16 = 800;
pub const TILE_H: u32 = 288;
pub const BUF_W: u16 = TILE_W;
pub const BUF_H: u16 = zg.PHYSICAL_HEIGHT + @as(u16, TILE_H); // 568
/// Palette entries 0..ROW_COLOURS-1 are the field's, rewritten on every line.
pub const ROW_COLOURS: usize = 105; // the widest scanline of the pan window
const ROW_PAL_BYTES: usize = ROW_COLOURS * 4;

comptime {
    // The pan never leaves the buffer: scroll x is round(200+sin*200) clamped to
    // 0..400 and scroll y is a value mod 288, so the last byte the machine can
    // read is (287+279)*800 + (400+399) = 453599, inside 454400.
    if (TILE_H - 1 + zg.PHYSICAL_HEIGHT > BUF_H) @compileError("pan buffer too short");
    if (400 + zg.PHYSICAL_WIDTH > BUF_W) @compileError("pan buffer too narrow");
    if (fond_b.len != @as(usize, TILE_W) * TILE_H) @compileError("fond.raw is not one TILE_W x TILE_H tile");
    if (fond_rows.len != @as(usize, TILE_H) * ROW_PAL_BYTES) @compileError("fond_rows.pal is not TILE_H rows of ROW_COLOURS");
    // The four NORMAL planes ZigOS allocates at boot are never reclaimed, so the
    // pan buffer is allocated ON TOP of them.
    const VRAM = zg.NB_PLANES * zg.NORMAL_FB_BYTES + @as(usize, BUF_W) * BUF_H;
    if (VRAM > zg.VRAM_BYTES) @compileError("over the VRAM pool");
}

/// The tile row shown on physical line 0 — the scroll offset AND the palette
/// offset, which are the same number by construction — and the window's x.
pub var pan_row: u32 = 0;
pub var pan_x: u16 = 0;

/// fond_rows.pal as aligned little-endian words (the palette entries' own format).
pub const fond_words: [fond_rows.len / 4]u32 align(4) = blk: {
    @setEvalBranchQuota(1_000_000);
    var w: [fond_rows.len / 4]u32 = undefined;
    for (&w, 0..) |*x, i| x.* = std.mem.readInt(u32, fond_rows[i * 4 ..][0..4], .little);
    break :blk w;
};

/// The entries tile row r's pixels use: its indices are packed from 0 (the
/// asset tool hands them out in order), so they are 0..fond_used[r]-1 and the
/// rest of the row's 105 need not be written (avg 86: 18 % fewer stores). Every
/// one a row does use differs from the row above it (measured: 86.3 of 86.3),
/// so these ARE the changes. Computed from the pixels, at comptime.
pub const fond_used: [TILE_H]u8 = blk: {
    @setEvalBranchQuota(2_000_000);
    var n: [TILE_H]u8 = undefined;
    for (&n, 0..) |*c, r| {
        var top: u8 = 0;
        for (fond_b[r * TILE_W ..][0..TILE_W]) |v| top = @max(top, v);
        if (top >= ROW_COLOURS) @compileError("fond.raw uses an entry past the row palette");
        c.* = top + 1;
    }
    break :blk n;
};

// Repeat the 288-row tile down the pan buffer. The window wraps seamlessly
// wherever it lands because the artwork is exactly 288-periodic.
pub fn paintPanBuffer(bg: *LogicalFB) void {
    var y: usize = 0;
    while (y < BUF_H) : (y += 1) {
        const src = fond_b[(y % TILE_H) * TILE_W ..][0..TILE_W];
        @memcpy(bg.fb[y * BUF_W ..][0..TILE_W], src);
    }
}

pub fn installRowPalette(bg: *LogicalFB, row: usize) void {
    const src = fond_words[row * ROW_COLOURS ..][0..ROW_COLOURS];
    for (src, 0..) |v, i| bg.palette[i] = v;
}

/// The pan buffer from buffer row `y` down, as a plane CHISEL can address: the
/// blitter bounds an 800-stride destination to 200 rows from its base, so each
/// blit gets a base at its own first row (every one here is <= 33 rows).
pub fn rowView(bg: *const LogicalFB, y: u32) LogicalFB {
    var v = bg.*;
    v.fb = bg.fb + @as(usize, y) * BUF_W;
    return v;
}

/// Put the field back over the buffer rectangle (x, y, w, h), h <= 200, from
/// the tile in cart RAM: buffer row y is tile row y mod 288, so a rectangle
/// crossing a tile boundary is two copies.
pub fn restore(gpu: *zg.Blitter, bg: *const LogicalFB, x: u16, y: u32, w: u16, h: u16) void {
    const t: u32 = y % TILE_H;
    const first: u16 = @intCast(@min(@as(u32, h), TILE_H - t));
    var v = rowView(bg, y);
    gpu.blitImage(&v, @intCast(x), 0, fond_b, TILE_W, x, @intCast(t), w, first, null);
    if (first == h) return;
    v = rowView(bg, y + first);
    gpu.blitImage(&v, @intCast(x), 0, fond_b, TILE_W, x, 0, w, h - first, null);
}

/// go(): vbl += 0.8, which CODEF lets grow forever (f64). Here the two phases
/// sin(vbl*PI/100) and cos(vbl*PI/200) are u32 turn counts (zg.fixtrig): they
/// wrap exactly at 2 PI (250 and 500 frames), so the Lissajous repeats
/// bit-for-bit, and the pan costs two table lookups, no soft-float.
/// sx is clamped and sy is taken mod TILE_H, which holds for ANY phase.
pub const Lissajous = struct {
    x: zg.fixtrig.Angle, // sin(vbl*PI/100) phase
    y: zg.fixtrig.Angle, // cos(vbl*PI/200) phase

    const STEP_X = zg.fixtrig.angle(0.8 * std.math.pi / 100.0);
    const STEP_Y = zg.fixtrig.angle(0.8 * std.math.pi / 200.0);

    pub fn pan(self: *Lissajous, bg: *LogicalFB) void {
        const one = zg.fixtrig.ONE;
        const sx: i32 = (200 * one + 200 * zg.fixtrig.sin(self.x) + one / 2) >> 16;
        const sy: i32 = (158 * one + 150 * zg.fixtrig.cos(self.y) + one / 2) >> 16;
        pan_row = @intCast(@mod(sy, @as(i32, TILE_H)));
        pan_x = @intCast(std.math.clamp(sx, 0, 400));
        bg.setScroll(pan_x, pan_row);
        self.x +%= STEP_X;
        self.y +%= STEP_Y;
    }
};
