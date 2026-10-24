// --------------------------------------------------------------------------
// The music screen's text: the wobbling 8x8 menu lines and the 16x16
// fullscreen scrolltext, on the overscan plane (physical coordinates).
//
// The wobble is a per-COLUMN sine: a pixel's offset depends on its x only.
// So each line computes its column offsets once (one sine a column) instead
// of one sine per lit pixel, as the first version did.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;
const wave = @import("wave.zig");

const font16_raw = @embedFile("../../assets/fonts/font16.raw"); // 320x48, 20x3 cells of 16x16
const font8_raw = @embedFile("../../assets/fonts/font8.raw"); // 320x16, 40x2 cells of 8x8

const PW: i32 = zg.PHYSICAL_WIDTH; // 400
const MAX_LINE: usize = 40; // longest menu line, in 8px cells

const COL_STEP = wave.rad(0.05); // the wave's phase step a column

// Column offsets of one wave: off[i] = trunc(sin((x0 + i) * 0.05 + phase) * amp),
// amp in Q8, phase an Angle: one table lookup a column.
fn waveColumns(off: []i32, x0: i32, phase: wave.Angle, amp8: i32) void {
    var a = phase +% @as(u32, @bitCast(x0)) *% COL_STEP;
    for (off) |*o| {
        o.* = wave.offset(a, amp8);
        a +%= COL_STEP;
    }
}

// A font as comptime column bitmasks: masks[glyph][column], bit gy = ink at row gy.
// Read from the 320-wide sheet, a glyph's column walk missed the 4 KB D-cache on
// every pixel; a mask is one load a column. ASCII from space; an unknown char is
// glyph 0, as before.
fn Font(comptime sheet: []const u8, comptime per_row: usize, comptime cell: usize, comptime M: type) type {
    const count = per_row * ((sheet.len / 320) / cell);
    return struct {
        const n = count;
        // Read by pointer (drawGlyph): a by-value copy of a glyph's masks was one
        // i64 load off a 2-aligned address, which TRAPS on the board (~700 cycles,
        // 139 a frame). align(8) keeps any such wide read aligned.
        const masks: [count][cell]M align(8) = blk: {
            @setEvalBranchQuota(count * cell * cell * 8);
            var t: [count][cell]M = undefined;
            for (0..count) |g| {
                const cx = (g % per_row) * cell;
                const cy = (g / per_row) * cell;
                for (0..cell) |gx| {
                    var m: M = 0;
                    for (0..cell) |gy| {
                        if (sheet[(cy + gy) * 320 + cx + gx] != 0) m |= @as(M, 1) << @intCast(gy);
                    }
                    t[g][gx] = m;
                }
            }
            break :blk t;
        };
    };
}
const Font8 = Font(font8_raw, 40, 8, u8);
const Font16 = Font(font16_raw, 20, 16, u16);

/// The lowest set bit's index of a byte (comptime): rv32im has no ctz instruction,
/// and @ctz became a library call.
const LOW_BIT: [256]u8 = blk: {
    var t: [256]u8 = undefined;
    t[0] = 0;
    for (1..256) |b| t[b] = @ctz(@as(u8, @intCast(b)));
    break :blk t;
};

inline fn lowBit(m: anytype) usize {
    if (@TypeOf(m) == u8) return LOW_BIT[m];
    const lo: u8 = @truncate(m);
    return if (lo != 0) LOW_BIT[lo] else 8 + @as(usize, LOW_BIT[@as(u8, @truncate(m >> 8))]);
}

// One glyph's ink in `color`, each column shifted down by offs[px - wave_x0], clipped
// to the plane.
fn drawGlyph(fb: *LogicalFB, comptime F: type, char: u8, x0: i32, y0: i32, color: u8, offs: []const i32, wave_x0: i32) void {
    const idx: usize = if (char >= 32 and char < 32 + F.n) char - 32 else 0;
    for (&F.masks[idx], 0..) |mask, gx| { // by pointer: a by-value copy was one wide load
        const px = x0 + @as(i32, @intCast(gx));
        if (mask == 0 or px < 0 or px >= fb.fb_w) continue;
        const top = y0 + offs[@intCast(px - wave_x0)];
        var m = mask;
        if (top >= 0 and top + @bitSizeOf(@TypeOf(mask)) <= fb.fb_h) { // the whole column on the plane
            const p: [*]u8 = fb.fb + @as(usize, @intCast(top)) * fb.stride + @as(usize, @intCast(px));
            while (m != 0) : (m &= m - 1) p[lowBit(m) * fb.stride] = color; // set bits only
            continue;
        }
        var py = top;
        while (m != 0) : ({
            m >>= 1;
            py += 1;
        }) {
            if (m & 1 == 0 or py < 0 or py >= fb.fb_h) continue;
            fb.fb[@as(usize, @intCast(py)) * fb.stride + @as(usize, @intCast(px))] = color;
        }
    }
}

pub fn drawText8(fb: *LogicalFB, text: []const u8, x: i32, y: i32, color: u8, amp8: i32, phase: wave.Angle) void {
    var off: [MAX_LINE * 8]i32 = undefined;
    const n: usize = @min(text.len, MAX_LINE); // usize: @min would narrow to u6, and n * 8 overflow
    waveColumns(off[0 .. n * 8], x, phase, amp8);
    for (text[0..n], 0..) |c, i| drawGlyph(fb, Font8, c, x + @as(i32, @intCast(i * 8)), y, color, &off, x);
}

// The scroller across the full physical width (the overscan plane is 400x280, so the
// glyph clip is the physical one); `base_x` is the message's left edge.
pub fn drawScroller(fb: *LogicalFB, message: []const u8, base_x: i32, y0: i32, color: u8, amp8: i32, phase: wave.Angle) void {
    var off: [zg.PHYSICAL_WIDTH]i32 = undefined;
    waveColumns(&off, 0, phase, amp8);
    for (message, 0..) |char, i| {
        const cx: i32 = base_x + @as(i32, @intCast(i * 16));
        if (cx <= -16 or cx >= PW) continue;
        drawGlyph(fb, Font16, char, cx, y0, color, &off, 0);
    }
}
