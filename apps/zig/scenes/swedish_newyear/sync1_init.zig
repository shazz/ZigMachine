// --------------------------------------------------------------------------
// SYNC #1's set-up, $200BE + $201D8 + $20426 and the loop's first $204B4:
// the tables, the two screens, and the two precalculations the part makes of
// its own graphics -- the font in four 4-pixel preshifts (shifted with roxr IN
// the draw screen, as the original does) and the Redhead logo in sixteen
// 1-pixel ones. Checked against Hatari's RAM at the first iteration
// (prototypes/snyd_re/sync1_init.py): every byte of the part, both screens
// and both preshift areas.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const S = @import("sync1.zig");

const Ram = st.Ram;

const FONT_SRC: u32 = 0x23F0C; // 51 letters, 32x22, 16 bytes a line
const FONT: u32 = 0x3C600;
const LOGO: u32 = 0x37B30; // 192x24, 48 bytes a line
const LOGO_SHIFTS: u32 = 0x37FB0; // 15 more, one pixel apart

/// `r` holds the part as the loader read it; everything above it is zero.
pub fn init(r: *const Ram) void {
    r.sl(0x23BCE, 0x23DEB); // the wave table
    r.sl(S.DRAW, 0x70000);
    r.sl(S.SCR_A, 0x70000);
    r.sl(S.SCR_B, 0x78000);
    r.sl(S.BAND, 0x70000 + 100 * st.LINE);
    for (0..201) |i| r.sw(S.LINE_TAB + 2 * @as(u32, @intCast(i)), @intCast(st.LINE * i));
    for (0..91) |i| r.sl(0x2185C + 4 * @as(u32, @intCast(i)), @intCast(0x840 * i));
    r.zero(0x70000, 0x1F01 * 4);
    preshiftFont(r);
    r.zero(0x70000, st.SCREEN);
    r.zero(0x78000, st.SCREEN);
    preshiftLogo(r);
    r.sl(0x21682, 0x22C02); // the text
    r.zero(S.RASTERS, 400);
    r.sl(0x2B674, 0x2B678); // the first squash list
    r.sl(0x28552, 0x28534); // the SYNC logo and its palette
    r.sl(0x2854E, r.l(0x28534));
    S.rasters(r);
}

/// $20D9A.
fn preshiftFont(r: *const Ram) void {
    const scr = r.l(S.DRAW);
    var src: u32 = FONT_SRC;
    var dst: u32 = FONT;
    for (0..51) |_| {
        for (0..22) |i| {
            const line = scr + @as(u32, @intCast(i)) * st.LINE;
            r.zero(line, 24);
            r.cp(line, src, 16);
            src += 16;
        }
        for (0..4) |_| {
            for (0..22) |i| {
                r.cp(dst, scr + @as(u32, @intCast(i)) * st.LINE, 24);
                dst += 24;
            }
            for (0..22) |i| shiftLine(r, scr + @as(u32, @intCast(i)) * st.LINE);
        }
    }
}

/// Four roxr.w passes over each plane of a 48-pixel line: 4 pixels right.
fn shiftLine(r: *const Ram, line: u32) void {
    for (0..4) |_| {
        for (0..4) |p| {
            var carry: u16 = 0;
            for ([_]u32{ 0, 8, 16 }) |g| {
                const a = line + 2 * @as(u32, @intCast(p)) + g;
                const v = r.w(a);
                r.sw(a, (v >> 1) | (carry << 15));
                carry = v & 1;
            }
        }
    }
}

/// $20F28: shift d7 = 1..15, each word ror'd into two (or'd over the one the
/// previous word spilled into), and the next line's first group cleared ahead.
fn preshiftLogo(r: *const Ram) void {
    r.zero(LOGO_SHIFTS, 0x10E0 * 4);
    var dst: u32 = LOGO_SHIFTS;
    for (1..16) |d7| {
        var src: u32 = LOGO;
        for (0..24) |_| {
            for (0..24) |_| {
                const v: u32 = r.w(src);
                const rot = (v >> @intCast(d7)) | (v << @intCast(32 - d7));
                r.sw(dst, r.w(dst) | @as(u16, @truncate(rot)));
                r.sw(dst + 8, @truncate(rot >> 16));
                src += 2;
                dst += 2;
            }
            r.zero(dst, 8);
        }
    }
}
