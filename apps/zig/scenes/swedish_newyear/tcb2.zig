// --------------------------------------------------------------------------
// TCB SCREEN #2, from the disk: the second half of the load F2 reads from
// tracks 12..37 to $8000 (prototypes/snyd_re/NOTES_tcb.md). TCB #1 ($E192)
// runs until Space is released; then its exit ($E0C2) and this screen's
// set-up (tcb2_init.zig), then the main loop $10B38, once a VBL:
//   VBL $EB3E  the palette $B4CC, Timer B on for the colour-0 rasters, the
//              next of 128 raster frames ($EAFA); every 70 VBLs it hands over
//              to $EC30 for 42 VBLs, which fades colour 1 up and down ($EAA4):
//              the UNION logo (plane 0 = colour 1) flashes out of the black.
//   $10714     flip the screens ($78300 / $70600): the one drawn this pass is
//              shown from the next VBL.
//   $F18C      where the scroller's palette chain starts (Timer B, next VBL).
//   $C06A      the big bouncing scroller (tcb2_scroll.zig) and the keys.
//   $10652 / $1058E  the small cylinder scroller (tcb2_small.zig).
//   $B4BE      the yellow TCB logo (tcb2_logo.zig).
//   $9964      AN COOL / WIZ CODERS (tcb2_ancool.zig).
// The colour registers of every line are tcb2_vbl.zig's palettes(): Timer B
// writes colour 0 from the raster frame at the end of each line, switches
// colours 2..15 at line 37, and from line 88 walks seven palettes, 8 lines
// apart from the scroller's line down, that shade the scroller.
//
// Keys, as the original reads them ($C076, a key acts once until another
// function key is pressed): F1 / F2 set the big scroller's speed (slow /
// normal), F3 / F4 / F5 restart the music at Dugger subtunes 2 / 3 / 4.
// The music starts at subtune 4.
//
// The remake invented or dropped: its F1..F5 played five different tunes,
// one of them a "dugger4" jingle that is nowhere on the disk; its tcb2fx mode
// (the scroller climbing on a sine) was triggered by the SYNC screen's text
// and is not in the original; its bars were a sine formula, not the 128-frame
// table; it drew the cylinder scroller and both logos from PNGs through
// CODEF's FX distortions instead of these preshift/ring/wave routines.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const vbl = @import("tcb2_vbl.zig");
const scroll = @import("tcb2_scroll.zig");
const small = @import("tcb2_small.zig");
const logo = @import("tcb2_logo.zig");
const ancool = @import("tcb2_ancool.zig");
pub const init = @import("tcb2_init.zig").init;
pub const palettes = vbl.palettes;
pub const Shown = vbl.Shown;

const Ram = st.Ram;

pub const BASE: u32 = 0x8000; // where the loader puts the part
pub const TOP: u32 = 0x80000;

pub const DRAWN: u32 = 0x113E6; // .l the screen drawn this pass (shown next VBL)
const FLIP: u32 = 0x1074E; // .l not'ed every pass
pub const MUSIC: u32 = 0x50600; // the Dugger replay, copied here by $10AA0
pub const LINE160: u32 = 0x10D66; // .l line * 160, 200 entries
pub const GLYPH_OFFSET: u32 = 0x3C03C; // .l small glyph * $960, 60 entries
pub const SCALE: u32 = 0xF54E; // 25 blocks of 32 longs: rows, then row offsets
pub const GLYPHS: u32 = 0x1908C; // the preshifted big glyphs
pub const LOGO_SHIFTS: u32 = 0x52600; // the TCB logo's 16 preshifts, $578 each
pub const RASTERS: u32 = 0x3654C; // 128 frames x 90 colour-0 words
pub const SLOT_X: u32 = 0xC150; // .l x 7: the scroller slots' screen offsets
pub const SLOT_GLYPH: u32 = 0xC16C; // .l x 7: their glyphs
pub const LEFT_EDGE: u32 = 0xC188; // .l the slot here takes the next letter
pub const RIGHT_EDGE: u32 = 0xC18C; // .l ... and moves here; the end blocks
pub const TEXT: u32 = 0xC190; // .l -> the next letter
pub const TEXT_START: u32 = 0xCC16;
pub const YLIST: u32 = 0xC198; // .l -> the bounce list being applied
pub const YSCRIPT: u32 = 0xC19C; // .l -> the next bounce list's number
pub const ANCOOL_RING: u32 = 0xA3AA; // 25 x (source, screen offset) + copies
pub const ANCOOL: u32 = 0x57D80; // AN COOL's 16 preshifts, $1644 each
const KEY_SEEN: u32 = 0xC194; // .b the last function key acted on
const CHAIN_LINE: u32 = 0xEF45; // .b the scroller's line - 96, for the next VBL

/// $FFFC02 as the main loop reads it: the last key code the keyboard sent.
var keyboard: u8 = 0;

/// One VBL and one pass of the main loop.
pub fn frame(r: *const Ram) Shown {
    const shown = vbl.vbl(r);
    flip(r);
    r.sb(CHAIN_LINE, @truncate((r.l(RIGHT_EDGE) / 0xA0) -% 0x60)); // $F18C
    scroll.step(r);
    applyKey(r);
    small.clear(r);
    small.step(r);
    logo.step(r);
    ancool.step(r);
    return shown;
}

/// $10714.
fn flip(r: *const Ram) void {
    r.sl(FLIP, ~r.l(FLIP));
    r.sl(DRAWN, if (r.l(FLIP) == 0) 0x78300 else 0x70600);
}

/// A function key (0 = F1 .. 4 = F5) reaching the keyboard. It acts at the
/// end of the next pass's $C06A; returns the Dugger subtune F3..F5 restart.
pub fn key(r: *const Ram, f: u8) ?u8 {
    keyboard = 0x3B + f;
    if (r.b(KEY_SEEN) == keyboard) return null;
    return if (f >= 2) f else null;
}

/// $C076: a function key other than the last one acted on.
fn applyKey(r: *const Ram) void {
    const code = keyboard;
    if (code == r.b(KEY_SEEN) or code < 0x3B or code > 0x3F) return;
    r.sb(KEY_SEEN, code);
    switch (code) {
        0x3B, 0x3C => {
            r.sl(scroll.PHASE, 0);
            r.sl(scroll.SPEED, if (code == 0x3B) 0x258 else 0x4B0);
        },
        else => {
            r.sb(vbl.RESTART, 0xFF);
            r.sl(vbl.RESTART_TUNE, code - 0x3B);
        },
    }
}

/// The keyboard as a fresh load finds it.
pub fn resetKeyboard() void {
    keyboard = 0;
}
