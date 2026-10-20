// --------------------------------------------------------------------------
// The DNA scrolltext: 240 two-pixel slices, each a 2x33 strip of one glyph
// frame from the remake's 30-frame filmstrip, drawn along a sine.
//
// The remake builds a 480 x 45*33 image at startup (main.go
// initCharacterFrames), then draws 240 textured quads of 2 source pixels by
// 33 source rows, scaled 2x horizontally and 1.5x vertically.  At our 1x that
// is a 2-pixel-wide, 24.75-row strip: exactly one source column pair and 33
// source rows sampled to 25 destination rows.  So instead of ripping 10,800
// little strips, we keep the 45 glyph bitmaps and compose each destination
// pixel from the same three layers the filmstrip baked in:
//
//   back  : the glyph rotated 180 degrees, purple   (PURPLE[frame row])
//   core  : the red bar, frame rows 12..20           (RED[frame row-12])
//   front : the glyph, 7 rows down in the 33-row cell, silver (SILVER[row])
//
// in that z-order: purple, red over it, silver over both (main.go's Draw calls
// on cnvFrames).  The gradients are indexed by the SOURCE row, exactly as the
// remake paints them before scaling; the vertical 33 -> 25 sample and the
// per-cell posY are the two roundings the Go leaves to Ebitengine's nearest
// filter, reproduced here in integers:
//
//   frame row f  = (4d + 2) / 3                    (25 dest rows)
//   front cell   = floor(f + 0.5 - (33 - 2.25k))   (posY in quarter pixels)
//   back cell    = floor(f + 0.5 - posYback(k))
//
// The sine: ypos = 80*cos(52.5 + t/6 + i/36) once t passes 250 - 0.0033i,
// else 80 (main.go drawScroller).  t is Q16.16 frames*0.3, the phase step is
// exactly 1/36 rad, and both the cart and the harness read the same 4096-entry
// Q16 sin/cos table (assets/screens/phenomena/wave.dat).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const A = @import("assets.zig");
const P = @import("palette.zig");
const text = @import("text.zig");

pub const CELLS: usize = 240;
pub const VISIBLE: usize = 160; // 320 px / 2
pub const FRAMES: usize = 30;
pub const STRIP_H: usize = 25; // 33 * 1.5 / 2, rounded up
pub const ONE: i32 = 1 << 16;
pub const TAU_Q16: i64 = 411775; // 2*pi * 65536

pub const Cell = struct { glyph: u8 = 0, frame: u8 = 0, slice: u8 = 0 };

pub var cells: [CELLS]Cell = [_]Cell{.{}} ** CELLS;
pub var head: usize = 0;
pub var rotation: i32 = 0; // Q16.16, 0..30

pub var msg_index: usize = 0;
pub var slice_count: usize = 0;
pub var pause: bool = false;
pub var pause_time: i32 = 250;
pub var rot_speed: i32 = 22938; // 0.35 * 65536
pub var scroll_speed: usize = 1;

pub const SPEED_PAUSE: i32 = ONE; // +1 / -1 while a control char holds
pub const SPEED_RUN: i32 = 22938;

fn isCtrl(ch: u8) bool {
    return ch == '^' or ch == '&' or ch == '#' or ch == '%';
}

pub fn reset() void {
    cells = [_]Cell{.{}} ** CELLS;
    head = 0;
    rotation = 0;
    msg_index = 0;
    slice_count = 0;
    pause = false;
    pause_time = 250;
    rot_speed = SPEED_RUN;
    scroll_speed = 1;
}

/// Init()'s 320-step warmup: bring the message into the buffer and settle the
/// frames before the first visible frame.
pub fn warmup() void {
    var i: usize = 0;
    while (i < 320) : (i += 1) {
        scroll(1);
        renderFrames(rot_speed);
    }
}

fn shiftLeft() void {
    head += 1;
    if (head == CELLS) head = 0;
}

fn addSlice(ch: u8) void {
    const previous = if (head >= 2) head - 2 else head + CELLS - 2;
    const tail = if (head == 0) CELLS - 1 else head - 1;
    cells[tail] = .{
        .glyph = text.fontIndex(ch),
        .frame = cells[previous].frame,
        .slice = @intCast(slice_count),
    };
}

pub fn scroll(speed: usize) void {
    var n: usize = 0;
    while (n < speed) : (n += 1) {
        const ch = text.MESSAGE[msg_index];
        if (isCtrl(ch) and slice_count == 0) {
            switch (ch) {
                '^' => {
                    pause = true;
                    pause_time = 275;
                    rot_speed = -SPEED_PAUSE;
                },
                '&' => {
                    pause = true;
                    pause_time = 275;
                    rot_speed = SPEED_PAUSE;
                },
                '#' => {
                    pause = true;
                    pause_time = 250;
                    rot_speed = -SPEED_PAUSE;
                },
                '%' => {
                    pause = true;
                    pause_time = 225;
                    rot_speed = -SPEED_PAUSE;
                },
                else => {},
            }
            msg_index += 1;
            if (msg_index >= text.LEN) msg_index = 90;
        } else {
            shiftLeft();
            addSlice(ch);
            slice_count += 1;
            if (slice_count > 7) {
                slice_count = 0;
                msg_index += 1;
                if (msg_index >= text.LEN) msg_index = 90;
            }
        }
    }
}

pub fn renderFrames(speed: i32) void {
    rotation += speed;
    if (rotation >= 30 * ONE) rotation -= 30 * ONE;
    if (rotation < 0) rotation += 30 * ONE;

    var i: usize = 0;
    while (i < CELLS) : (i += 1) {
        var idx = head + i;
        if (idx >= CELLS) idx -= CELLS;
        var f = rotation + P.SINE[i];
        if (f >= 30 * ONE) {
            f -= 30 * ONE;
        } else if (f < 0) {
            f += 30 * ONE;
        }
        cells[idx].frame = @intCast(@divTrunc(f, ONE));
    }
}

inline fn ink(g: u8, x: usize, y: usize) bool {
    return (A.glyphRow(g, y) & (@as(u16, 1) << @intCast(x))) != 0;
}

/// The table cos at radian phase (Q16.16), as an index into wave.dat.
inline fn cosAt(phase: i64) i32 {
    const p = @mod(phase, TAU_Q16);
    const idx: usize = @intCast(@divTrunc(p * 4096, TAU_Q16));
    return A.wave(idx).cos;
}

/// main.go drawScroller at 1x: the strip top row (content) for slice i, from
/// the wave clock t (Q16.16).  ypos is 80 before the wave starts, then 80*cos
/// of 52.5 + t/6 + i/36; the strip is 24.75 rows tall, rounded to 25.
pub fn stripTop(i: usize, t_q16: i64) i32 {
    const angle0: i64 = 3440640 + @divTrunc(t_q16, 6); // 52.5 rad, Q16
    const t2 = t_q16 + @divTrunc(@as(i64, @intCast(i)) * 65536, 6);
    const threshold = (250 * 65536) - @as(i64, @intCast(i)) * 216;
    const cos_q16: i32 = if (t2 > threshold) cosAt(angle0 + @as(i64, @intCast(i)) * 1820) else 65536;
    const ypos_q16: i64 = @as(i64, 80) * cos_q16;
    const y_q16: i64 = 8404992 + @divTrunc(3 * ypos_q16, 4); // 128.25 + 0.75*ypos
    return @intCast(@divFloor(y_q16 + 32768, 65536));
}

/// main.go drawScroller at 1x: the strip top row and the two pixel columns of
/// each 2-px slice, for content x = 2*i.
pub fn draw(fb: *zg.LogicalFB, t_q16: i64) void {
    const base = fb.fb;

    var i: usize = 0;
    while (i < VISIBLE) : (i += 1) {
        const top = stripTop(i, t_q16);

        var idx = head + i;
        if (idx >= CELLS) idx -= CELLS;
        const cell = cells[idx];
        const g = cell.glyph;
        const k: i32 = cell.frame;
        const s: usize = cell.slice;

        const front4: i32 = 132 - 9 * k; // 4 * (33 - 2.25k)
        const back4: i32 = if (k < 15) 9 * k else -132 + 9 * (k - 15);

        var d: usize = 0;
        while (d < STRIP_H) : (d += 1) {
            const f: i32 = @intCast(@divTrunc(4 * @as(i32, @intCast(d)) + 2, 3));
            const fcol: u8 = P.SILVER[@intCast(f)];
            const bcol: u8 = P.PURPLE[@intCast(f)];

            // Purple back: cnvFont2 row r is glyph row 18-r (the remake's
            // Scale(-1,-1) then Translate(16, 26) clips the glyph's last 7
            // rows above the cell), columns mirrored.
            const bc = @divFloor(4 * f + 2 - back4, 4);
            const back_on = bc >= 0 and bc <= 18;
            const bg = if (back_on) @as(usize, @intCast(18 - bc)) else 0;

            var c0: u8 = 0;
            var c1: u8 = 0;
            var painted0 = false;
            var painted1 = false;
            if (back_on) {
                if (ink(g, 15 - 2 * s, bg)) {
                    c0 = bcol;
                    painted0 = true;
                }
                if (ink(g, 14 - 2 * s, bg)) {
                    c1 = bcol;
                    painted1 = true;
                }
            }

            // Red core, frame rows 12..20, opaque over the back.
            if (f >= 12 and f <= 20) {
                const rc = P.RED[@intCast(f - 12)];
                c0 = rc;
                c1 = rc;
                painted0 = true;
                painted1 = true;
            }

            // Silver front on top.
            const fc = @divFloor(4 * f + 2 - front4, 4);
            if (fc >= 7 and fc <= 32) {
                const gy: usize = @intCast(fc - 7);
                if (ink(g, 2 * s, gy)) {
                    c0 = fcol;
                    painted0 = true;
                }
                if (ink(g, 2 * s + 1, gy)) {
                    c1 = fcol;
                    painted1 = true;
                }
            }

            const y = top + @as(i32, @intCast(d));
            if (y < 0 or y >= 240) continue;
            const row = (@as(usize, A.CONTENT_Y) + @as(usize, @intCast(y))) * fb.stride + A.CONTENT_X + 2 * i;
            if (painted0) base[row] = c0;
            if (painted1) base[row + 1] = c1;
        }
    }
}
