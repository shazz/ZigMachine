// --------------------------------------------------------------------------
// SYNC SCREEN #2, from the disk ($2C1CA, the same load as SYNC #1). Space in
// SYNC #1 jumps here:
//   $2064A  clear the buffer the last flip made the one on screen,
//   $2C28E  tile it with a 32x32 pattern (10 x 6) and put the 160x48 SYNC
//           logo at line 30, x 80; palette $364F8 for the whole screen (Timer B
//           is off: no rasters here, colour 0 is black everywhere);
//   then a 4-voice sample replay on Timer A (7680 Hz) and its sequencer in
//           the VBL ($2C590) -- the music, which this port plays from the SNDH
//           rip of this very player (Swedish_New_Year_Demo_Sync.sndh).
// The one moving thing is colour 1, which is the logo's starry black: the
// sequencer sets it every VBL -- $700 when the fourth voice starts sample 1,
// $007 when it starts any other, 0 otherwise. So the logo flashes red or blue
// for one frame on every drum. Ported here is exactly that: the sequencer's
// pattern walk for voice 1 (which drives the pattern changes) and voice 4
// (which drives the flash); the sample playing is the SNDH's.
// Space leaves: the original resets the ST ($FC0020) and so boots back into
// the menu; here it goes straight to the menu.
//
// The remake showed only the logo, flashing to a blue-sky version on a VU peak;
// it dropped the tiled screen and invented the flash.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const S = @import("sync1.zig");

const Ram = st.Ram;

pub const PALETTE: u32 = 0x364F8;
const TILE: u32 = 0x31CD0; // 32x32, 16 bytes a line
const LOGO: u32 = 0x286E4; // 160x48, 80 bytes a line
// The sequencer ($2C590), its own variables.
const LIST: u32 = 0x2D1AE; // .l -> the next pattern word
const LIST_LOOP: u32 = 0x2D1B2; // .l
const REPEAT: u32 = 0x2D1B6; // .b plays left of this pattern
const PATTERN: u32 = 0x2D1B8; // .w its offset in PATTERNS
const VOICE1: u32 = 0x2D1BA; // .l -> voice 1's next row
const VOICE4: u32 = 0x2D1C6; // .l -> voice 4's next row
const PATTERNS: u32 = 0x2C87E; // 16 bytes a pattern: the four voices' rows
const TICK: u32 = 0x2D26C; // .w VBLs to the next row
const SPEED = 6;
const NO_NOTE: u16 = 0xFFFE;
const END: u16 = 0xFFFF;

/// Space from SYNC #1: draw the screen into the buffer on show. Returns it.
pub fn enter(r: *const Ram) u32 {
    const scr = r.l(S.DRAW);
    r.zero(scr, st.SCREEN);
    for (0..6) |ty| for (0..10) |tx| {
        const at = scr + @as(u32, @intCast(ty)) * 32 * st.LINE + @as(u32, @intCast(tx)) * 16;
        for (0..32) |row| r.cp(at + @as(u32, @intCast(row)) * st.LINE, TILE + 16 * @as(u32, @intCast(row)), 16);
    };
    for (0..48) |row| r.cp(scr + 0x12E8 + @as(u32, @intCast(row)) * st.LINE, LOGO + 80 * @as(u32, @intCast(row)), 80);
    return scr;
}

/// One VBL of $2C590: the colour register 1 it leaves.
pub fn vbl(r: *const Ram) u16 {
    const t = r.w(TICK) -% 1;
    r.sw(TICK, t);
    if (t != 0) return 0;
    r.sw(TICK, SPEED);
    voice1(r);
    return voice4(r);
}

/// Voice 1 reads its row; at its pattern's end the pattern plays again, or
/// the next one from the list starts ($2C5BC..$2C668).
fn voice1(r: *const Ram) void {
    while (true) {
        if (r.b(REPEAT) == 0) nextPattern(r);
        const row = r.w(r.l(VOICE1));
        r.sl(VOICE1, r.l(VOICE1) + 2);
        if (row != END) return;
        r.sb(REPEAT, r.b(REPEAT) -% 1);
        r.sl(VOICE1, r.l(PATTERNS + r.w(PATTERN)));
    }
}

fn nextPattern(r: *const Ram) void {
    var w = r.w(r.l(LIST));
    r.sl(LIST, r.l(LIST) + 2);
    while (w & 0x8000 != 0) { // the list's end: loop
        r.sl(LIST, r.l(LIST_LOOP));
        w = r.w(r.l(LIST));
        r.sl(LIST, r.l(LIST) + 2);
    }
    r.sb(REPEAT, @truncate(w));
    const p = (w >> 4) & 0x7F0;
    r.cp(VOICE1, PATTERNS + p, 16); // the four voices' row pointers
    r.sw(PATTERN, p);
}

/// Voice 4 ($2C79E..$2C818): the flash colour for its row.
fn voice4(r: *const Ram) u16 {
    while (true) {
        const row = r.w(r.l(VOICE4));
        r.sl(VOICE4, r.l(VOICE4) + 2);
        if (row == NO_NOTE) return 0;
        if (row != END) return if (row & 7 == 1) 0x700 else 0x007;
        r.sl(VOICE4, r.l(PATTERNS + r.w(PATTERN) + 12));
    }
}
