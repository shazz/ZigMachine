// --------------------------------------------------------------------------
// OMEGA's set-up, $8000..$8124 of the OMEGA load (tracks 38..44 to $8000;
// prototypes/snyd_re/NOTES_omega.md): the screen at $70000 is cleared (40,000
// bytes: the 200 lines and the 50 of the opened bottom border), the frame
// picture copied to lines 0..169 and the LED panel to lines 201..224, and the
// ATARI logo's 32 frames built at $40000: each is the 96x89 logo shifted left
// by a per-line amount (0..16) from a 32-entry wave that slides one entry a
// frame -- the logo twists as the frames play. The carry words live in the
// part's RAM ($C806..$C80C), as on the 68000, so the memory ends as it did.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("st.zig");
const O = @import("omega.zig");

const Ram = st.Ram;

const PICTURE: u32 = 0xDDDA; // 170 lines
const PICTURE_LEN = 0x1A90 * 4;
const PANEL: u32 = 0x1495A; // the LED panel, 24 lines
const PANEL_AT: u32 = O.SCREEN + 201 * st.LINE;
const PANEL_LEN = 0x3C0 * 4;
const CLEAR_LEN = 0x2710 * 4;
const LOGO_END: u32 = 0xCA12; // the logo is read backwards from here, 48 bytes a line
const SHIFTS: u32 = 0xC80E; // .w per line and frame: 0..16
const CARRY: u32 = 0xC806; // .w x 4: the bits shifted out of the group to the right
const LOGO_LINES = 89;
const SRC_GROUPS = 6; // 96 pixels
pub const LOGO_BYTES = 56; // a built line: 7 groups, 112 pixels

pub fn init(r: *const Ram) void {
    r.zero(O.SCREEN, CLEAR_LEN);
    r.cp(O.SCREEN, PICTURE, PICTURE_LEN);
    r.cp(PANEL_AT, PANEL, PANEL_LEN);
    var shifts = SHIFTS;
    var dst: u32 = O.FRAMES + LOGO_BYTES;
    for (0..O.LOGO_FRAMES) |_| {
        var src = LOGO_END;
        var d1: u32 = 2 * LOGO_LINES; // $B2: the line's index into the wave, x2
        while (d1 != 0) : (d1 -= 2) {
            // rol.l Dn counts mod 64; a 32-bit rotation by c is one by c mod 32
            logoLine(r, src, dst, @truncate(r.w(shifts + d1)));
            src += SRC_GROUPS * 8; // 48 read backwards, then +$60
            dst += LOGO_BYTES; // 56 written backwards, then +$70
        }
        shifts += 2;
    }
}

/// One line, right to left: each plane's word rotated left through its carry
/// ($8064..$8110). `src` / `dst` are the line's ends; the carries become the
/// seventh (leftmost) group.
fn logoLine(r: *const Ram, src_end: u32, dst_end: u32, shift: u5) void {
    for (0..4) |p| r.sw(CARRY + 2 * @as(u32, @intCast(p)), 0);
    var src = src_end;
    var dst = dst_end;
    for (0..SRC_GROUPS) |_| {
        for (0..4) |p| {
            const c = CARRY + 2 * @as(u32, @intCast(p));
            src -= 2;
            dst -= 2;
            const v = std.math.rotl(u32, r.w(src), shift) | r.w(c);
            r.sw(dst, @truncate(v));
            r.sw(c, @truncate(v >> 16));
        }
    }
    for (0..4) |p| {
        dst -= 2;
        r.sw(dst, r.w(CARRY + 2 * @as(u32, @intCast(p))));
    }
}
