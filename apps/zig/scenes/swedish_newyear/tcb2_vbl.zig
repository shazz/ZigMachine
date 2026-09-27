// --------------------------------------------------------------------------
// TCB #2's VBL ($EB3E, or $EC30 while colour 1 fades) and what the colour
// registers hold on every line of the frame it starts. Timer B (event count,
// data 1) interrupts at the END of each display line, so what a handler
// writes shows from the next line:
//   $ECBE  colour 0 = the raster frame's next word; the word-36 marker (bit
//          15) also loads colours 2..15 ($ECFA) and moves on to $ED16;
//   $ED16  colour 0 = the next word; the word-87 marker clears it, loads the
//          whole palette $EE64 and re-arms Timer B for $EF44 lines ($F18C:
//          the scroller's top - 96);
//   $ED68, $EDA0, $EDC8, $EDF0, $EE18, $EE40  the next six palettes of the
//          chain, 8 lines apart; the last one stops Timer B.
// The ST shows bits 0..10 of a colour register; the markers' bit 15 is
// masked where the colour is converted (st.color).
// --------------------------------------------------------------------------
const st = @import("st.zig");
const T = @import("tcb2.zig");

const Ram = st.Ram;

const PALETTE: u32 = 0xB4CC; // the VBL's 16 colours
const UPPER: u32 = 0xECFA; // colours 2..15 from line 37
const CHAIN: u32 = 0xEE64; // 7 palettes of 16
const FADE: u32 = 0xEAA4; // colour 1, a word a VBL, $FFFF ends
const FADE_PTR: u32 = 0xECB8; // .l
const FLASH_COUNT: u32 = 0xECBC; // .w VBLs since the last fade
const FRAME_OFFSET: u32 = 0xEB3A; // .l the raster frame, * $B4
pub const RESTART: u32 = 0xC130; // .b a function key asked for a tune
pub const RESTART_TUNE: u32 = 0xC132; // .l which
const CHAIN_GAP: u32 = 0xEF44; // .b lines from the chain's first palette to the second

pub const FADE_EVERY = 0x46;
const NORMAL: u32 = 0xEB3E;
const FADING: u32 = 0xEC30;

/// $70, the VBL vector (outside the part's memory).
pub var vector: u32 = NORMAL;

/// $1081C: the set-up's last step installs the VBL.
pub fn install() void {
    vector = NORMAL;
}

/// What one frame shows: the screen, colour 1 as the VBL left it, the raster
/// frame Timer B walks, and the chain's gap.
pub const Shown = struct { screen: u32, colour1: u16, rasters: u32, gap: u8 };

/// One VBL.
pub fn vbl(r: *const Ram) Shown {
    var colour1 = r.w(PALETTE + 2);
    if (vector == NORMAL) {
        const n = r.w(FLASH_COUNT) +% 1;
        r.sw(FLASH_COUNT, n);
        if (n == FADE_EVERY) {
            r.sw(FLASH_COUNT, 0);
            r.sl(FADE_PTR, FADE);
            vector = FADING;
        }
    } else {
        const w = r.w(r.l(FADE_PTR));
        if (w == 0xFFFF) {
            colour1 = 0;
            vector = NORMAL;
        } else {
            colour1 = w;
            r.sl(FADE_PTR, r.l(FADE_PTR) + 2);
        }
    }
    r.sb(0x10D26, 0xFF); // the flag the main loop waits on
    var off = r.l(FRAME_OFFSET) + 0xB4; // $EAFA
    if (@as(i32, @bitCast(off)) >= 0x5A00) off = 0;
    r.sl(FRAME_OFFSET, off);
    r.sb(RESTART, 0); // the replay restarts from its SNDH (tcb2.key)
    r.sb(CHAIN_GAP, r.b(CHAIN_GAP + 1));
    return .{ .screen = r.l(T.DRAWN), .colour1 = colour1, .rasters = T.RASTERS + off, .gap = r.b(CHAIN_GAP) };
}

/// The colour registers of display lines 0..199, and colour 0 above and below.
pub fn palettes(r: *const Ram, shown: Shown, out: *[200][16]u16, top: *u16, bottom: *u16) void {
    var pal: [16]u16 = undefined;
    for (&pal, 0..) |*c, i| c.* = r.w(PALETTE + 2 * @as(u32, @intCast(i)));
    pal[1] = shown.colour1;
    top.* = pal[0];
    var word = shown.rasters;
    var chain: u32 = CHAIN;
    var handler: u8 = 0; // $ECBE, $ED16, then the chain's six
    var wait: u16 = 1;
    for (out) |*line| {
        line.* = pal;
        if (handler > 7) continue; // Timer B stopped
        wait -= 1;
        if (wait != 0) continue;
        wait = 1;
        switch (handler) {
            0, 1 => {
                const w = r.w(word);
                word += 2;
                pal[0] = w;
                if (w & 0x8000 == 0) continue;
                if (handler == 0) {
                    for (2..16) |i| pal[i] = r.w(UPPER + 2 * @as(u32, @intCast(i - 2)));
                } else {
                    chain = load(r, &pal, chain);
                    wait = if (shown.gap == 0) 256 else shown.gap;
                }
                handler += 1;
            },
            else => {
                chain = load(r, &pal, chain);
                wait = 8;
                handler += 1;
            },
        }
    }
    bottom.* = pal[0];
}

fn load(r: *const Ram, pal: *[16]u16, at: u32) u32 {
    for (pal, 0..) |*c, i| c.* = r.w(at + 2 * @as(u32, @intCast(i)));
    return at + 32;
}
