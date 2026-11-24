// --------------------------------------------------------------------------
// border.zig — the editor's sprite-drawn border: the upper-border logo and
// readouts (displayer2.inc `upbordisp`) and the low-border orderlist
// (`ordldis`), as sprite bitmaps. Pure, no I/O, no allocator.
//
// The C64 keeps these as 7 expanded-X 24x21 sprites each:
//   upper: bank 3 $d940.. (`updispr`), sprite Y 25 (raster 26)
//   lower: bank 0 $0400.. (`ordlspr`), sprite Y 1 (raster 257, the 8-bit wrap)
// They are why the 25-row text screen alone misses the SID-WIZARD logo, the
// header row and the "-1 -4 17..." orderlist rows under the 26th row.
// --------------------------------------------------------------------------
const dsp = @import("display.zig");

const header = @embedFile("sw_header.bin"); // asm/graphics/sw-header.prg minus its load address

pub const up_base: u16 = 0xd900; // `cursprite`; `updispr` starts at +0x40
pub const updispr: u16 = 0xd940;
const seqchr_off: usize = 90; // seqchr2 follows seqchar in `glyphs`

/// seqchar (graphics.inc, 18 glyphs of 5 rows: 0..f, dots, NOP separator)
/// followed by seqchr2 (type 1 "ghostpixel" set, 16 glyphs).
const glyphs = [_]u8{
    0xee, 0xaa, 0xaa, 0xaa, 0xee, 0x44, 0xcc, 0x44, 0x44, 0xee,
    0xee, 0x22, 0x66, 0x88, 0xee, 0xee, 0x22, 0x66, 0x22, 0xcc,
    0x44, 0x88, 0xee, 0x22, 0x22, 0xee, 0x88, 0xee, 0x22, 0xcc,
    0x66, 0x88, 0xcc, 0xaa, 0xcc, 0xee, 0x22, 0x44, 0x44, 0x44,
    0xee, 0xaa, 0xee, 0xaa, 0xee, 0xee, 0xaa, 0xee, 0x22, 0xcc,
    0xee, 0xaa, 0xee, 0xaa, 0xaa, 0xcc, 0xaa, 0xcc, 0xaa, 0xcc,
    0x66, 0x88, 0x88, 0x88, 0x66, 0xcc, 0xaa, 0xaa, 0xaa, 0xcc,
    0x66, 0x88, 0xcc, 0x88, 0xee, 0xee, 0x88, 0xcc, 0x88, 0x88,
    0x00, 0x00, 0x24, 0x00, 0x00, 0x00, 0x00, 0xff, 0x00, 0x00,
    0x7e, 0x5a, 0x5a, 0x5a, 0x7e, 0x24, 0x6c, 0x24, 0x24, 0x7e,
    0x7e, 0x12, 0x36, 0x4c, 0x7e, 0x7e, 0x12, 0x36, 0x12, 0x6e,
    0x22, 0x44, 0x7e, 0x12, 0x12, 0x7e, 0x48, 0x7e, 0x12, 0x6e,
    0x3e, 0x48, 0x6e, 0x5a, 0x6e, 0x7e, 0x12, 0x22, 0x22, 0x22,
    0x7e, 0x5a, 0x7e, 0x5a, 0x7e, 0x7e, 0x5a, 0x7e, 0x12, 0x6e,
    0x7e, 0x5a, 0x7e, 0x5a, 0x5a, 0x6c, 0x5a, 0x6c, 0x5a, 0x6c,
    0x36, 0x48, 0x48, 0x48, 0x36, 0x6c, 0x5a, 0x5a, 0x5a, 0x6c,
    0x7e, 0x48, 0x6c, 0x48, 0x7e, 0x7e, 0x48, 0x6c, 0x48, 0x48,
};

/// seqchtb2: glyph offset for the right (low-nibble) char of an orderlist value.
fn rightGlyph(i: usize) usize {
    return if (i < 16) seqchr_off + 5 * i else 80 + 5 * (i - 16);
}

/// seqchtbb: glyph offset for the left (high-nibble) char.
fn leftGlyph(i: usize) usize {
    return switch (i) {
        0, 16 => 80,
        15 => 85,
        else => seqchr_off + 5 * i,
    };
}

pub const Border = struct {
    up: [0x240]u8 = [_]u8{0} ** 0x240, // $d900.. (cursor sprite, header sprites)
    low: [0x1c0]u8 = [_]u8{0} ** 0x1c0, // ordlspr: 7 sprites x 64 bytes

    pub fn init() Border {
        var b: Border = .{};
        @memcpy(b.up[0x40..][0..header.len], header);
        return b;
    }
};

// -- upper border (displayer2.inc upbordisp) ------------------------------------

/// upchar1/uplchar (left = high nibble) and upchar2/uprchar (right = low
/// nibble): `chdrcom` writes the glyph INVERTED into one nibble of 5 rows.
fn putChar(b: *Border, addr: u16, glyph: usize, left: bool) void {
    const keep: u8 = if (left) 0x0f else 0xf0;
    for (0..5) |x| {
        const g = glyphs[glyph * 5 + x];
        const i = addr - up_base + 3 * x;
        const mask = (~g) | keep; // eor #$ff; ora zpvari4
        b.up[i] = (b.up[i] | ~keep) & mask;
    }
}

fn hex2(b: *Border, addr: u16, v: u8) void {
    putChar(b, addr, v >> 4, true);
    putChar(b, addr, v & 0x0f, false);
}

/// dispmtr: a 5-bit value as three scaled bar bytes (scalemask1).
fn meter(b: *Border, addr: u16, v: u8) void {
    const mask = [12]u8{ 0xff, 0xfe, 0xfc, 0xf8, 0xf8, 0xf0, 0xe0, 0xe0, 0xc0, 0x80, 0x80, 0x00 };
    const comp = [3]i16{ 11, 21, 32 };
    for (0..3) |y| {
        var x: i16 = comp[y] - @as(i16, v);
        if (x < 0) x = 0;
        if (x >= 12) x = 11;
        b.up[addr - up_base + y] = mask[@intCast(x)];
    }
}

/// The 3 single-SID "posies" readouts: songtime mm:ss, then patterns 3,2,1.
fn numbers(b: *Border, o: *const dsp.Overlay) void {
    hex2(b, 0xda84, o.upbord_songtime[0]);
    hex2(b, 0xda85, o.upbord_songtime[1]);
    hex2(b, 0xda2f, o.upbord_patnum[2]);
    hex2(b, 0xd9ed, o.upbord_patnum[1]);
    hex2(b, 0xd96e, o.upbord_patnum[0]);
}

fn ptnSizes(b: *Border, o: *const dsp.Overlay) void {
    const left = [3]u16{ 0xd9ae, 0xda2d, 0xda6f }; // ctuvm1; x=0 runs after `dec vidzptr+1`, so page $d9
    const right = [3]u16{ 0xd9ad, 0xd9ef, 0xda6e }; // dec vidzptr (x=1 jumps to $d9ef)
    for (0..3) |x| {
        putChar(b, left[x], o.upbord_ptnsize[x] & 0x0f, true);
        putChar(b, right[x], o.upbord_ptnsize[x] >> 4, false);
    }
}

/// The oscilloscope window: edge pixels, then the flat centre line a silent
/// SID (OSC3 = ENV3 = 0) draws: row 7, OsciPixel ORs on both bytes.
fn scope(b: *Border) void {
    const base: usize = 0xdac6 - up_base;
    for (0..16) |r| {
        b.up[base + 3 * r] = 0x80;
        b.up[base + 3 * r + 1] = 0x05;
    }
    b.up[base + 21] |= 0x3f; // OsciPixel $20..$01 (x = 0..5)
    b.up[base + 22] |= 0xfc; // OsciPixel $80..$04 (x = 6..11)
}

/// upbordisp: redraw every readout. `rastime` is the player-runtime
/// maxrasti byte, `ct`/`pw` the 5-bit meters (host-supplied, live).
pub fn upperRender(b: *Border, o: *const dsp.Overlay) void {
    numbers(b, o);
    putChar(b, 0xda97, @intFromBool(o.upbord_autoadv), false);
    hex2(b, 0xda95, o.upbord_rastime);
    putChar(b, 0xda83, o.upbord_octave, true);
    ptnSizes(b, o);
    meter(b, 0xdaaa, o.pw_meter[0]);
    meter(b, 0xdaad, o.pw_meter[1]);
    meter(b, 0xdab0, o.pw_meter[2]);
    meter(b, 0xdab6, o.ct_meter);
    scope(b);
}

// -- low border (displayer2.inc ordldis) -----------------------------------------

/// sprtable: byte offset of orderlist column k inside ordlspr.
fn colOffset(k: usize) usize {
    return (k / 3) * 0x40 + k % 3;
}

fn orderValue(b: *Border, off: usize, v: u8, mark: bool) void {
    b.low[off + 15] = if (mark) 0xc8 else 0; // markpos underline, line 5
    var lo: usize = 0x11; // value 0 shows dots, $f0 the NOP separator
    if (v == 0) lo = 0x10 else if (v != 0xf0) lo = v & 0x0f;
    const hi: usize = v >> 4; // seqchtbb maps 0 to the dots glyph
    for (0..5) |x| {
        const r = glyphs[rightGlyph(lo) + x] & 0x0f;
        const l = glyphs[leftGlyph(hi) + x] & 0xf0;
        b.low[off + 3 * x] = l | r;
    }
}

/// ordldis: the three orderlist rows, 20 values each, 7 sprite lines apart.
pub fn lowerRender(b: *Border, o: *const dsp.Overlay) void {
    for (0..3) |t| {
        for (0..20) |k| {
            const off = colOffset(k) + t * 21;
            const mark = o.ordl_mark[t] == @as(i16, @intCast(k));
            orderValue(b, off, o.ordl_val[t][k], mark);
        }
    }
}
