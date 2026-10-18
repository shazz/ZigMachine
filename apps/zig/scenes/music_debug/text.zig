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
const fsin = @import("fsin.zig");

const font16_raw = @embedFile("../../assets/fonts/font16.raw"); // 320x48, 20x3 cells of 16x16
const font8_raw = @embedFile("../../assets/fonts/font8.raw"); // 320x16, 40x2 cells of 8x8

const PW: i32 = zg.PHYSICAL_WIDTH; // 400
const MAX_LINE: usize = 40; // longest menu line, in 8px cells

// Column offsets of one wave: off[i] = trunc(sin((x0 + i) * 0.05 + phase) * amp),
// the same f32 expression the per-pixel version evaluated.
fn waveColumns(off: []i32, x0: i32, phase: f32, amp: f32) void {
    for (off, 0..) |*o, i| {
        const px = x0 + @as(i32, @intCast(i));
        o.* = @intFromFloat(fsin.sin(@as(f32, @floatFromInt(px)) * 0.05 + phase) * amp);
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
        const masks: [count][cell]M = blk: {
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

// One glyph's ink in `color`, each column shifted down by wave[px - wave_x0], clipped
// to the plane.
fn drawGlyph(fb: *LogicalFB, comptime F: type, char: u8, x0: i32, y0: i32, color: u8, wave: []const i32, wave_x0: i32) void {
    const idx: usize = if (char >= 32 and char < 32 + F.n) char - 32 else 0;
    for (F.masks[idx], 0..) |mask, gx| {
        const px = x0 + @as(i32, @intCast(gx));
        if (mask == 0 or px < 0 or px >= fb.fb_w) continue;
        const top = y0 + wave[@intCast(px - wave_x0)];
        var m = mask;
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

pub fn drawText8(fb: *LogicalFB, text: []const u8, x: i32, y: i32, color: u8, amp: f32, phase: f32) void {
    var wave: [MAX_LINE * 8]i32 = undefined;
    const n: usize = @min(text.len, MAX_LINE); // usize: @min would narrow to u6, and n * 8 overflow
    waveColumns(wave[0 .. n * 8], x, phase, amp);
    for (text[0..n], 0..) |c, i| drawGlyph(fb, Font8, c, x + @as(i32, @intCast(i * 8)), y, color, &wave, x);
}

// The scroller across the full physical width (the overscan plane is 400x280, so the
// glyph clip is the physical one); `base_x` is the message's left edge.
pub fn drawScroller(fb: *LogicalFB, message: []const u8, base_x: i32, y0: i32, color: u8, amp: f32, phase: f32) void {
    var wave: [zg.PHYSICAL_WIDTH]i32 = undefined;
    waveColumns(&wave, 0, phase, amp);
    for (message, 0..) |char, i| {
        const cx: i32 = base_x + @as(i32, @intCast(i * 16));
        if (cx <= -16 or cx >= PW) continue;
        drawGlyph(fb, Font16, char, cx, y0, color, &wave, 0);
    }
}
