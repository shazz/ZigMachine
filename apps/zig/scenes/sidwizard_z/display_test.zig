// --------------------------------------------------------------------------
// display_test.zig — Part 2 checks: render() against tunes/FLASHITBACK.SWM,
// whose cell values were probed from the file and cross-read from the asm.
// --------------------------------------------------------------------------

const std = @import("std");
const swm = @import("swm.zig");
const dsp = @import("display.zig");

const tune = @embedFile("tunes/FLASHITBACK.SWM");

var song: swm.Song = .{};
var scr: dsp.Screen = .{};
var over: dsp.Overlay = .{};

// The editor's start-up view: window 0, track 0, row 0, pattern 1 per track,
// instrument 1, subtune 0, mutesolo from the header (editor.asm inits $FF and
// a load copies the header bytes over).
fn startupView() dsp.View {
    var v = dsp.View{};
    v.mutesolo = .{ song.header[swm.H_MUTE], song.header[swm.H_MUTE + 1], song.header[swm.H_MUTE + 2] };
    return v;
}

test "load fixture" {
    try swm.load(&song, tune);
    try std.testing.expectEqualStrings("HERMIT: FLASH IT BACK", song.header[swm.H_AUTHOR .. swm.H_AUTHOR + 21]);
    try std.testing.expectEqual([2]u8{ 0x86, 0x84 }, song.funk[0]);
    try std.testing.expectEqual(@as(u8, 0xff), song.header[swm.H_MUTE]); // all tracks unmuted
}

// -- dispaut (menu.inc): the 38-byte author text + separator + driver sig ----

test "row26 author/title" {
    var v = startupView();
    v.titledi = true;
    dsp.overlayRender(&song, &v, &over);
    try std.testing.expect(over.row26_title);
    try std.testing.expectEqualStrings("HERMIT: FLASH IT BACK", over.row26[0..21]);
    for (22..38) |k| try std.testing.expectEqual(@as(u8, ' '), over.row26[k]);
    try std.testing.expectEqual(@as(u8, 0xbd), over.row26[38]); // separator
    try std.testing.expectEqual(@as(u8, 'M'), over.row26[39]); // menu.inc drvsig .text "N","M",... (ASCII, not screen code 0x0d)
}

// -- seqdisp: the hidden 26th row's orderlist position numbering --------------
// pair i at pos seqposdisp+i: hi = pos>>4 (|$30 when marked), lo = $90|pos&f
// (ASCII hexchar when marked). Startup: seqposdisp 0 = olstart[0] -> marked.

test "row26 seqdisp numbering" {
    var v = startupView();
    dsp.overlayRender(&song, &v, &over);
    try std.testing.expect(!over.row26_title);
    try std.testing.expectEqual(@as(u8, 0), over.row26_mark);
    try std.testing.expectEqual(@as(u8, 0x30), over.row26[0]); // '0' hi, marked
    try std.testing.expectEqual(@as(u8, 0x30), over.row26[1]); // '0' lo, marked
    try std.testing.expectEqual(@as(u8, 0x00), over.row26[2]); // pos 1 hi: raw 0
    try std.testing.expectEqual(@as(u8, 0x91), over.row26[3]); // pos 1 lo
    try std.testing.expectEqual(@as(u8, 0x01), over.row26[32]); // pos 16 hi: raw 1
    try std.testing.expectEqual(@as(u8, 0x90), over.row26[33]); // pos 16 lo
    // move the play mark: olstart[0] = 3 -> pair 3 gets the ASCII pair
    v.olstart[0] = 3;
    v.olstart[1] = 5;
    dsp.overlayRender(&song, &v, &over);
    try std.testing.expectEqual(@as(u8, 3), over.row26_mark);
    try std.testing.expectEqual(@as(u8, 0x30), over.row26[6]);
    try std.testing.expectEqual(@as(u8, '3'), over.row26[7]);
    // ordl_mark: track 1 differs from track 0 -> underlined at column 5;
    // track 2 shares track 0's position -> no mark
    try std.testing.expectEqual(@as(i16, 5), over.ordl_mark[1]);
    // track 2 stays at 0, which differs from track 0's new position 3
    try std.testing.expectEqual(@as(i16, 0), over.ordl_mark[2]);
    try std.testing.expectEqual(@as(i16, -1), over.ordl_mark[0]);
}

// -- ptndisp/stpdisp/mutesolodisp/row25back: the pattern area -----------------
// Startup: all tracks show pattern 1 (pats[0] = bd 82 59 00 00 00 00 00 bb
// 58 ...), prowpos 0, stptick 4, mutesolo $ff (not muted).

test "pattern row 0 cells" {
    var v = startupView();
    dsp.render(&song, &v, &scr);
    // note $bd -> notechar[$3d]=$80, octachar[$3d]=$a5
    try std.testing.expectEqual(@as(u8, 0x80), scr.chars[0][1]);
    try std.testing.expectEqual(@as(u8, 0xa5), scr.chars[0][2]);
    // instrument $82 -> hi digit 0, lo char $10|2
    try std.testing.expectEqual(@as(u8, 0x00), scr.chars[0][3]);
    try std.testing.expectEqual(@as(u8, 0x12), scr.chars[0][4]);
    // fx $59 (bigfx, no value column) -> hi digit 5, lo char $10|9
    try std.testing.expectEqual(@as(u8, 0x05), scr.chars[0][5]);
    try std.testing.expectEqual(@as(u8, 0x19), scr.chars[0][6]);
    // filrlop fills the tail with the dash pairs
    try std.testing.expectEqual(@as(u8, 0x5d), scr.chars[0][7]);
    try std.testing.expectEqual(@as(u8, 0x5e), scr.chars[0][8]);
    // all three tracks show pattern 1 -> same cells
    try std.testing.expectEqual(scr.chars[0][1], scr.chars[0][11]);
    try std.testing.expectEqual(scr.chars[0][1], scr.chars[0][21]);
}

test "pattern rows 1..7 cells" {
    var v = startupView();
    dsp.render(&song, &v, &scr);
    // rows 1..5 are note $00 -> rest glyphs + blank instrument pair + dashes
    for (1..6) |r| {
        try std.testing.expectEqual(@as(u8, 0x5b), scr.chars[r][1]); // notechar[0]
        try std.testing.expectEqual(@as(u8, 0x5c), scr.chars[r][2]); // octachar[0]
        try std.testing.expectEqual(@as(u8, 0xbd), scr.chars[r][3]);
        try std.testing.expectEqual(@as(u8, 0xbd), scr.chars[r][4]);
        try std.testing.expectEqual(@as(u8, 0x5d), scr.chars[r][5]);
        try std.testing.expectEqual(@as(u8, 0x5e), scr.chars[r][6]);
        try std.testing.expectEqual(@as(u8, 0x5d), scr.chars[r][7]);
        try std.testing.expectEqual(@as(u8, 0x5e), scr.chars[r][8]);
    }
    // row 6 is note $bb (bit7 set) -> notechar[$3b]=$89 + inst $58 pair
    try std.testing.expectEqual(@as(u8, 0x89), scr.chars[6][1]);
    try std.testing.expectEqual(@as(u8, 0xb4), scr.chars[6][2]); // octachar[$3b]
    try std.testing.expectEqual(@as(u8, 0x05), scr.chars[6][3]); // inst $58 hi
    try std.testing.expectEqual(@as(u8, 0x18), scr.chars[6][4]); // $10|8
    // row 7 is a rest ($00 byte in memory)
    try std.testing.expectEqual(@as(u8, 0x5b), scr.chars[7][1]);
    try std.testing.expectEqual(@as(u8, 0x5c), scr.chars[7][2]);
    // row 10 is $7e: the gateoff-signal glyphs
    try std.testing.expectEqual(@as(u8, 0x5f), scr.chars[10][1]); // notechar[$7e]
    try std.testing.expectEqual(@as(u8, 0x60), scr.chars[10][2]); // octachar[$7e]
}

test "step numbers and colours" {
    var v = startupView();
    dsp.render(&song, &v, &scr);
    // stpdisp: chars $c0|row, downbeat every stptick=4 rows, else ptrownum
    for (0..dsp.ROWS) |r| {
        try std.testing.expectEqual(@as(u8, 0xc0 | @as(u8, @intCast(r))), scr.chars[r][0]);
        const want: u4 = if (r % 4 == 0) 12 else 11; // downbeat : ptrownum
        try std.testing.expectEqual(want, scr.colours[r][0]);
    }
    // mutesolo $ff (unmuted): note pair 15 (notecolu), inst pair 3 (instcolu)
    try std.testing.expectEqual(@as(u4, 15), scr.colours[2][1]);
    try std.testing.expectEqual(@as(u4, 3), scr.colours[2][3]);
    // row 24 (row25back): step colour + mute colours, panel ipa/itahdr
    try std.testing.expectEqual(@as(u4, 12), scr.colours[24][0]); // 24%4==0
    try std.testing.expectEqual(@as(u4, 15), scr.colours[24][1]);
    try std.testing.expectEqual(@as(u4, 3), scr.colours[24][3]);
    try std.testing.expectEqual(@as(u4, 12), scr.colours[24][30]); // ipa
    try std.testing.expectEqual(@as(u4, 15), scr.colours[24][33]); // itahdr
}

test "muted track colours" {
    var v = startupView();
    v.mutesolo[0] = 0xfe; // bit0 clear = muted
    dsp.render(&song, &v, &scr);
    try std.testing.expectEqual(@as(u4, 11), scr.colours[2][1]); // mutecol
    try std.testing.expectEqual(@as(u4, 11), scr.colours[2][3]);
    try std.testing.expectEqual(@as(u4, 15), scr.colours[2][12]); // track 1 normal
}

// -- miscdis: subtune number + the RESTEMP funk pair --------------------------

test "misc row 24" {
    var v = startupView();
    dsp.render(&song, &v, &scr);
    try std.testing.expectEqual(@as(u8, 0xc0), scr.chars[24][33]); // selsubt 0
    try std.testing.expectEqual(@as(u8, 0xc6), scr.chars[24][37]); // funk t0 $86
    try std.testing.expectEqual(@as(u8, 0x20), scr.chars[24][38]); // t0 bit7 -> space
}

// -- insdisp: instrument panel ------------------------------------------------

test "instrument panel" {
    var v = startupView();
    dsp.render(&song, &v, &scr);
    // selinst number "01" (ASCII hexchar digits)
    try std.testing.expectEqual(@as(u8, '0'), scr.chars[0][30]);
    try std.testing.expectEqual(@as(u8, '1'), scr.chars[0][31]);
    // name: copied verbatim from the instrument slot like the asm (the real
    // C64 shows the ASCII bytes as mirrored/inverse glyphs in SW's charset)
    try std.testing.expectEqual(song.insts[1][120..128].*, scr.chars[0][32..40].*);
    // main data: ins[1]=$0f at row2 c32/33 (hi raw digit, lo plain)
    try std.testing.expectEqual(@as(u8, 0x00), scr.chars[2][32]);
    try std.testing.expectEqual(@as(u8, 0x0f), scr.chars[2][33]);
    // ins[6]=$10 at row3 c34/35: lo |$10 (k>=6)
    try std.testing.expectEqual(@as(u8, 0x01), scr.chars[3][34]);
    try std.testing.expectEqual(@as(u8, 0x10), scr.chars[3][35]);
    // octave ins[9]=$00: blank sign, quotient $30
    try std.testing.expectEqual(@as(u8, ' '), scr.chars[4][38]);
    try std.testing.expectEqual(@as(u8, 0x30), scr.chars[4][39]);
    // wf1 pair (ctrl $1a bit3 SET -> the waform1 hex pair: ins[15]=$09 ->
    // hi raw digit 0, lo 0x90|9; bit3 clear would show the $69,$69 pair)
    try std.testing.expectEqual(@as(u8, 0x00), scr.chars[1][38]);
    try std.testing.expectEqual(@as(u8, 0x99), scr.chars[1][39]);
    // condisa: control $1a -> bit7/6 clear -> colours 15 on rows 19/14
    try std.testing.expectEqual(@as(u4, 15), scr.colours[19][30]);
    try std.testing.expectEqual(@as(u4, 15), scr.colours[14][30]);
    // HR timer digit (ctrl&3)|$30 at row2 c38; sync "$7f" at row2 c39
    try std.testing.expectEqual(@as(u8, 0x32), scr.chars[2][38]); // ($1a&3)|$30
    try std.testing.expectEqual(@as(u8, 0x7f), scr.chars[2][39]);
    // vibrato type (ctrl>>3)&6 = 2 -> vibtype[2]/[3] at row3 c38/39
    try std.testing.expectEqual(@as(u8, 0x6e), scr.chars[3][38]);
    try std.testing.expectEqual(@as(u8, 0x70), scr.chars[3][39]);
}

test "instrument panel signed octave and gate bits" {
    var v = startupView();
    v.selinst = 1;
    song.insts[1][9] = 0xf4; // -12 -> sign '-', quotient 1
    song.insts[1][0] = 0x80; // bit7 set -> rows 19 c30-33 colour 11
    dsp.render(&song, &v, &scr);
    try std.testing.expectEqual(@as(u8, '-'), scr.chars[4][38]);
    try std.testing.expectEqual(@as(u8, 0x31), scr.chars[4][39]); // 12/12
    try std.testing.expectEqual(@as(u4, 11), scr.colours[19][30]); // gate bit on
    // restore for later tests
    song.insts[1][9] = 0x00;
    song.insts[1][0] = 0x1a;
}

// -- cursord: the cursor sprite coordinates -----------------------------------

test "cursor moves" {
    var v = startupView();
    dsp.overlayRender(&song, &v, &over);
    try std.testing.expectEqual(@as(u16, 24), over.cursor_x); // track 0, note col
    try std.testing.expectEqual(@as(u16, 34), over.cursor_y); // row 0
    try std.testing.expect(over.cursor_2x); // note column is double-wide
    v.subwpos2[0] = 1; // instrument column
    dsp.overlayRender(&song, &v, &over);
    try std.testing.expectEqual(@as(u16, 40), over.cursor_x); // (0+2)*8+24
    try std.testing.expect(!over.cursor_2x);
    v.subwpos1[0] = 1; // track 1, note column
    v.subwpos2[0] = 0;
    dsp.overlayRender(&song, &v, &over);
    try std.testing.expectEqual(@as(u16, 104), over.cursor_x); // 10*8+24
    try std.testing.expect(over.cursor_2x);
    v.subwpos3[0] = 5; // row 5
    dsp.overlayRender(&song, &v, &over);
    try std.testing.expectEqual(@as(u16, 74), over.cursor_y); // 5*8+34
    // chord-table window: fixed x at 38, y at row 6
    v.curwind = 3;
    dsp.overlayRender(&song, &v, &over);
    try std.testing.expectEqual(@as(u16, 328), over.cursor_x); // 38*8+24
    try std.testing.expectEqual(@as(u16, 82), over.cursor_y); // 6*8+34
    // instrument window, common subwindow: X base 32, Y base 1
    v.curwind = 2;
    v.inswXbuf[0] = 4;
    v.inswYbuf[0] = 1;
    dsp.overlayRender(&song, &v, &over);
    try std.testing.expectEqual(@as(u16, 328), over.cursor_x); // (36->38)*8+24
    try std.testing.expectEqual(@as(u16, 50), over.cursor_y); // (1+1)*8+34
}

// -- ptncurs: the byte index under the cursor row (Part 3 datawriter input) ---

test "ptncurs walks the pattern" {
    var v = startupView();
    dsp.overlayRender(&song, &v, &over);
    try std.testing.expectEqual(@as(u8, 0), over.ptncurs[0]);
    v.subwpos3[0] = 7; // rows 0..6 consume 3 + 5*1 + 2 (row 6 carries inst) = 10
    dsp.overlayRender(&song, &v, &over);
    try std.testing.expectEqual(@as(u8, 10), over.ptncurs[0]);
}

// -- ordldis: the low-border orderlist sprites --------------------------------

test "orderlist values" {
    var v = startupView();
    dsp.overlayRender(&song, &v, &over);
    // seq 0: 01 04 17 04 04 09 18 04 04 09 18 04 17 04 04 09 18 0d 10 04 ...
    try std.testing.expectEqual(@as(u8, 0x01), over.ordl_val[0][0]);
    try std.testing.expectEqual(@as(u8, 0x17), over.ordl_val[0][2]);
    try std.testing.expectEqual(@as(u8, 0x18), over.ordl_val[0][6]);
    for (0..20) |k| try std.testing.expectEqual(song.seqs[0][k], over.ordl_val[0][k]);
    for (0..20) |k| try std.testing.expectEqual(song.seqs[1][k], over.ordl_val[1][k]);
    for (0..20) |k| try std.testing.expectEqual(song.seqs[2][k], over.ordl_val[2][k]);
}

// -- upbordisp: the upper-border readouts --------------------------------------

test "upper border readouts" {
    var v = startupView();
    dsp.overlayRender(&song, &v, &over);
    for (0..3) |t| {
        try std.testing.expectEqual(@as(u8, 1), over.upbord_patnum[t]);
        // ptnsize = ptn_size[1]-%1: lo nybble LEFT, hi nybble RIGHT (raw fields)
        try std.testing.expectEqual(song.ptn_size[1] -% 1, over.upbord_ptnsize[t]);
    }
    try std.testing.expectEqual(@as(u8, 1), over.upbord_octave); // 0+1
}

// -- out-of-range View fields clamp, never crash ------------------------------

test "garbage view is clamped" {
    var v = dsp.View{
        .curwind = 9,
        .subwpos1 = @splat(200),
        .subwpos2 = @splat(200),
        .subwpos3 = @splat(250),
        .prowpos = @splat(200),
        .curptn1 = .{ 200, 0, 255 },
        .played_curptn = @splat(7),
        .ptrowpos = @splat(3),
        .olstart = @splat(250),
        .selinst = 200,
        .selchor = 200,
        .seltemp = 200,
        .selsubt = 200,
        .chorpos = 200,
        .temppos = 200,
        .wfarpos = 200,
        .pwtbpos = 200,
        .ctftpos = 200,
        .inswXbuf = @splat(200),
        .inswYbuf = @splat(200),
        .mutesolo = @splat(200),
        .stptick = 0, // would divide by zero
        .octave = 200,
        .seqposdisp = 200,
        .inamepos = 200,
        .curcolc = 200,
    };
    dsp.render(&song, &v, &scr);
    dsp.overlayRender(&song, &v, &over);
    // pattern 200 clamps to 100, pattern 0 keeps the dummy (PTN0 = $00,$ff).
    // The window top is prowpos=200 -> walkPtn lands on the endmark, so the
    // dummy's screen row 0 is the ptendch string, rows below blanked to $bd.
    try std.testing.expectEqual(@as(u8, 0xbe), scr.chars[0][11]); // track 1: ptn 0
    try std.testing.expectEqual(@as(u8, 0xbb), scr.chars[0][14]);
    try std.testing.expectEqual(@as(u8, 0xbd), scr.chars[1][11]);
    try std.testing.expectEqual(@as(u8, 0xbd), scr.chars[2][11]);
    // cursor row clamps to 24
    try std.testing.expectEqual(@as(u16, 226), over.cursor_y); // 24*8+34
    try std.testing.expectEqual(@as(u16, 336), over.cursor_x); // col clamps to 39
    // the subtune digit is shown from RAW selsubt (miscdis: ora #$c0);
    // only the funk-table read is clamped (deviation for memory safety)
    try std.testing.expectEqual(@as(u8, 0xc8), scr.chars[24][33]);
    // ptncurs stopped at the endmark, never past the slot
    for (0..3) |t| try std.testing.expect(over.ptncurs[t] <= swm.ptn_bound);
}

// -- dummy pattern (curptn1 = 0) end string ------------------------------------

test "dummy pattern end string" {
    var v = startupView();
    v.curptn1 = .{ 0, 0, 0 };
    dsp.render(&song, &v, &scr);
    // ptendch: $be,$be,$be,$bb,$bc,$be,$be,$be at row 1, blanks below
    const want = [8]u8{ 0xbe, 0xbe, 0xbe, 0xbb, 0xbc, 0xbe, 0xbe, 0xbe };
    for (0..8) |k| try std.testing.expectEqual(want[k], scr.chars[1][1 + k]);
    try std.testing.expectEqual(@as(u8, 0xbd), scr.chars[2][1]);
    try std.testing.expectEqual(@as(u8, 0x5b), scr.chars[0][1]); // note $00
}

// -- colour themes (displayer2.inc coloriz / ColorThemes) ----------------------

fn themeScreen(n: u8) dsp.Screen {
    var v = startupView();
    v.themeno = n;
    var s: dsp.Screen = .{};
    dsp.render(&song, &v, &s);
    return s;
}

test "every theme recolours the whole editor from the asm's table, not only the menu" {
    try swm.load(&song, tune);
    const base = themeScreen(0);
    for (1..dsp.themes.len) |n| {
        const t = dsp.themes[n];
        const s = themeScreen(@intCast(n));
        var differ: usize = 0;
        for (0..dsp.ROWS) |r| {
            for (0..dsp.COLS) |c| differ += @intFromBool(s.colours[r][c] != base.colours[r][c]);
        }
        try std.testing.expect(differ > 50); // the pattern view and the panel, not a few cells
        try std.testing.expectEqual(t[3], s.colours[0][29]); // the underlay and fx columns: fxcol
        var o: dsp.Overlay = .{};
        var v = startupView();
        v.themeno = @intCast(n);
        dsp.overlayRender(&song, &v, &o);
        try std.testing.expectEqual(t[0], o.sprite_colour); // the border sprites: borderspcol
        try std.testing.expectEqual(t[3], o.fx_colour); // the 26th row: fxcol
    }
}

test "theme 0 is the colour scheme the editor starts with" {
    try swm.load(&song, tune);
    const s = themeScreen(0);
    try std.testing.expectEqual(@as(u4, 12), s.colours[0][29]);
    try std.testing.expectEqual(@as(u4, 12), s.colours[24][31]); // the panel's default: ipacol
}
