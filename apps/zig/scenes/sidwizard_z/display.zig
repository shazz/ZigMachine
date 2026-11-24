// --------------------------------------------------------------------------
// display.zig — the SID-Wizard 1.97 editor screen, native port (Part 2).
// A mirror of asm/include/displayer1.inc (display/ptndisp/stpdisp/insdisp/
// chtmdis/miscdis) and displayer2.inc (iniscrn/ordldis/seqdisp/cursord/
// upbordisp) plus the bits of commonsubs.inc they call.
//
// render() draws the 25×40 text screen the C64 shows (screen codes + colour
// RAM), exactly as the original paints cells. What the editor shows with
// sprites instead of cells (the orderlist low-border band, the cursor, the
// upper-border readouts, the hidden 26th row of video-RAM) is recorded as
// data in Overlay via overlayRender(), never as pixels.
//
// The static screen template (graphics.inc vidram, $e000..$e3ff · notechar/
// octachar · charset digit house code, probed with 64tass .enc "screen":
// A-Z=$01-$1a, a-z=$41-$5a, digits ASCII) is carried as data, all comptime.
// --------------------------------------------------------------------------

const std = @import("std");
const swm = @import("swm.zig");
const filer = @import("filer.zig");

pub const ROWS = 25;
pub const COLS = 40;

pub const Screen = struct {
    chars: [ROWS][COLS]u8 = [_][COLS]u8{[_]u8{0} ** COLS} ** ROWS,
    colours: [ROWS][COLS]u4 = [_][COLS]u4{[_]u4{0} ** COLS} ** ROWS,
};

/// The editor state the displayer routines read. Every field mirrors the asm
/// variable whose name (last word after the `.`, zeropages aside) sits in the
/// comment behind it.
pub const View = struct {
    curwind: u8 = 0, // curwind: 0-pattern,1-orderlist,2-instrum,3-chord,4-tempo
    subwpos1: [5]u8 = @splat(0), // subwpos1: window "row": track / olist row / inst
    //   subwindow 0..3 (common,wf,pw,ctf) / chord row / tempo page (cursor Y)
    subwpos2: [5]u8 = @splat(0), // subwpos2: window "column" (note/inst/fx...) /
    //   olist col / chord col / tempo col (cursor X)
    subwpos3: [5]u8 = @splat(0), // subwpos3: pattern cursor row / olist cursor /
    //   (unused for inst; inswYbuf[0] covers it) / ...
    prowpos: [3]u8 = @splat(0), // prowpos: pattern-editor display window top row per track
    curptn1: [3]u8 = .{ 1, 1, 1 }, // curptn1: displayed pattern number per track
    played_curptn: [3]u8 = @splat(0), // player.CURPTN per channel ($00 = never started)
    ptrowpos: [3]u8 = @splat(0), // playadapter.ptrowpos: played each-frame row
    olstart: [3]u8 = @splat(0), // playadapter.olstart: played orderlist position per channel
    selinst: u8 = 1, // display.selinst
    selchor: u8 = 1, // display.selchor
    seltemp: u8 = 1, // display.seltemp
    selsubt: u8 = 0, // miscdis.selsubt
    chorpos: u8 = 0, // chorpos: chord-table display position
    temppos: u8 = 0, // temppos: tempo-table display position
    wfarpos: u8 = 0, // wfarpos: WF/ARP/DETUNE table display position
    pwtbpos: u8 = 0, // pwtbpos: PW table display position
    ctftpos: u8 = 0, // ctftpos: FILTER table display position
    inswXbuf: [4]u8 = @splat(0), // inswXbuf: cursor column in instrument subwindows
    inswYbuf: [4]u8 = @splat(0), // inswYbuf: cursor row in instrument subwindows
    mutesolo: [3]u8 = @splat(0), // mutesolo: bit0 per track (1 = unmuted, $FF default)
    stptick: u8 = 4, // stptick (editor.asm: $04 default): bar-highlight tick amount
    octave: u8 = 0, // jamoctave (upbordisp shows it +1)
    seqposdisp: u8 = 0, // seqdpos: orderlist display scroll position
    titledi: bool = false, // display.titledi: author/title stays in row26 until keypress
    drvidx: u8 = 1, // DrvType → drvsig abbreviation (index into .text "N","M","L","E","B","D")
    namemode: bool = false, // namemode: instrument-name typing (cursord + name cells)
    inamepos: u8 = 0, // compzvar2: name-typing cursor offset (cursord namemode)
    curcolc: u8 = 0, // curcolc: cursor colour flasher counter (cursord)
    autoadv: u8 = 0, // Config.autoadv counter (upbordisp arrow when != 0)
    // -- Part 3 (keyhandler) state ------------------------------------------------
    jammode: bool = false, // jammode+1: keys jam instead of type when playing
    filer_loc: [24]u8 = [_]u8{' '} ** 24, // the file dialog's "DR:" text (host-set: where it is)
    followp: bool = false, // playadapter.followp+1: follow-play while playing
    framesp: u8 = 1, // framesp: frame-speed (PALmaxframespeed = 1..6, 1 = fastest)
    prevwin: u8 = 0, // keyrtbb save: window reter returns to
    valuecont: u8 = 0, // valuecont: hex-digit entry continuation counter
    solosta: u8 = 0, // solosta: solo toggle state (0 = off, 1 = soloed)
    namebuf: [8]u8 = @splat('.'), // instrument-name staging (menu.setyfl2 field)
    undo_type: u8 = 0xff, // UndoType: 0-pattern/1-order/2-inst/$ff none
    undo_item: u8 = 0, // UndoNo: pattern/instrument number saved
    undo_len: u8 = 0, // UndoLen: rows saved for the pattern undo
    undo_size: u8 = 0, // UndoSize: ptnsize bytes saved for the pattern undo
    undo_buf: [256]u8 = @splat(0), // undobuffer: one saved row/inst/seq snapshot
    menumode: bool = false, // menumode: Part 4 menu open (keyhandler gates on it)
    menucurpos: u8 = 3, // menu.menucurpos: menu cursor (firstcpos = 3)
    menupoint: u8 = 0, // menu.menupoint: row chosen by RETURN, run by the host
    helpmode: bool = false, // menu.helpmode: INSTANT HELP instead of the menu
    menuprompt: u8 = 0, // menu.menuprompt: pending "are you sure" (0/1/2)
    confbits: u8 = default_confbits, // Config.confbits: editor feature switches
    confbits2: u8 = 0, // Config.confbits2: bit0 = save dialog auto-directory
    devicen: u8 = 8, // devicen+1: disk device number (8..30)
    themeno: u8 = 0, // Config.ThemeNo: colour theme 0..8
    keybtyp: u8 = 0, // Config.KeybTyp: 0 SIDW, $2c Janko, $44 DMC, $88 SDI
    cfgstat: u8 = ' ', // menu.cfgstat: '!' when SaveConfig failed
    jamnote: u8 = 0xff, // playadapter.jamnote: $ff = no jammed note
    basnote: u8 = 0, // display.BasNote: chord-edit base note (host sets at jam)
    copyrow: u8 = 0, // copyrow: copy-start row (pattern clipboard)
    copyptn: u8 = 0, // copyptn: copy-start pattern number
    ptnbuf: [256]u8 = @splat(0), // patternbuffer: copy/cut staging area
    ptnbuf_len: u8 = 0, // bufflen: rows staged for paste
    ptnbuf_size: u8 = 0, // sizesto: ptnsize staged at copy time
    copypos: u8 = 0, // copypos: absolute pattern byte index where copy started
    seqbuf: [128]u8 = @splat(0), // seqbuffer: orderlist copy staging
    seqbuf_len: u8 = 0, // seqbufs
    seqbuf_pos: u8 = 0, // scopypos: copy-start position (shift+C end marker)
    instbuf: [128]u8 = @splat(0), // instrumentbuffer: CopyIns staging
    filer: filer.State = .{}, // menu.inc filedialog/filenamer state (Part 4)
};

/// The editor's own config word now lives in View.confbits (editor.asm:331,
/// `confbits .byte %00001001`): the toggles in keys.zig and menu.zig XOR it
/// and the displayer/editor read the bits from the same place. It is *not* a
/// tune-header byte: TUNEHEADER+6..7 are `leavemp`, saved verbatim.
pub const default_confbits = 0b00001001;

/// All the feature switches on at their defaults; every `bit X / bpl / bmi`
/// disable branch in iniscrn therefore resolves to the normal colour.
fn featOn(comptime _: void) bool {
    return true;
}

pub const Palette = struct {
    bordersp: u4 = 12, // borderspcol (orderlist sprites / trackers' borders)
    notecolu: u4 = 15, // notecolucol: colour of pattern note-columns
    instcolu: u4 = 3, // instcolucol: colour of pattern instrument-columns
    fx: u4 = 12, // fxcol: pattern fx columns + whole underlay + orderlist numbering
    ptrownum: u4 = 11, // ptrownumcol
    downbeat: u4 = 12, // downbeatcol
    playposi: u4 = 15, // playposicol
    instnum: u4 = 13, // instnumcol: instrument-number cell ("01")
    ina: u4 = 15, // inacol: instrument-name + table headers
    ipa: u4 = 12, // ipacol: instrument-panel default + current-table row number
    itahdr: u4 = 15, // itahdrcol
    ita: u4 = 3, // itacol
    itaemph: u4 = 15, // itaemphcol
    gateoff: u4 = 11, // gateoffcol: gate-off row number in the tables
    mutecol: u4 = 11, // settings.cfg mutecol
    disable: u4 = 11, // DISABLECOL (features compiled out in light builds)
    detut: u4 = 5, // detutcol
    pwtkt: u4 = 14, // pwtktcol
    fltkt: u4 = 8, // fltktcol
};

const palette = Palette{};

/// What the editor shows with sprites instead of screen cells.
pub const Overlay = struct {
    row26: [COLS]u8 = @splat(0), // the hidden 26th row of videoram ($ffc0 = page-2
    // row 24): seqdisp's orderlist numbering, or dispaut's author/title.
    row26_title: bool = false, // dispaut mode (the tune's author/title row)
    row26_mark: u8 = 0xFF, // seqdisp: pair index (0..19) whose orderlist position
    // equals olstart[0] (displayed with hexchar glyphs), 0xFF = none.
    ordl_val: [3][20]u8 = [_][20]u8{[_]u8{0} ** 20} ** 3, // ordldis: 20 sprite columns per track, the
    // orderlist values seq[seqposdisp+k] (&0x7f); $00 = the "dots" glyph.
    ordl_mark: [3]i16 = @splat(-1), // ordldis underline: display column (0..19) of
    // each track's played orderlist position, -1 = none.
    cursor_x: u16 = 0, // cursord $d000 (chars*8 + 24)
    cursor_y: u16 = 0, // cursord $d001 (row*8 + 34)
    cursor_2x: bool = false, // cursord $d01d: double-wide cursor sprite
    cursor_col: u8 = 0, // cursord flasher colour (curcols[curcolc])
    ptncurs: [3]u8 = @splat(0), // rowdlop/setrpos: the cursor row's byte index in
    // pattern memory (absolute: walkPtn(prowpos+subwpos3[0]); Part 3 datawriter)
    upbord_songtime: [2]u8 = @splat(0), // upbordisp: songtime minutes/seconds (BCD);
    //   player-runtime value, the host presetts it, overlayRender leaves it.
    upbord_patnum: [3]u8 = @splat(0), // upbordisp: curptn1 per track (2 hex digits)
    upbord_octave: u8 = 1, // upbordisp: jamoctave+1 (single left char)
    upbord_autoadv: bool = false, // upbordisp: Config.autoadv sign char
    upbord_ptnsize: [3]u8 = @splat(0), // upbordisp: ptnsize[curptn1]-1 per track
    //   (lo nybble char LEFT, hi nybble char RIGHT)
    upbord_rastime: u8 = 0, // upbordisp: playadapter.maxrasti (player-runtime)
    pw_meter: [3]u8 = @splat(0), // upbordisp DisPWmt 5-bit inputs (0..31); the
    //   host (player adapter) presetts them, overlayRender leaves them.
    ct_meter: u8 = 0, // upbordisp CTFMETR input (0..31); host presets.
    scope: [12]u8 = @splat(7), // the oscilloscope: the pixel row (0 top .. 15) of each of its 12 columns; 7 = the flat centre line of a silent SID
};

// -- static data ------------------------------------------------------------

const template = comptimeHex(template_hex, ROWS * COLS);
pub const notechar = comptimeHex(notechar_hex, 128); // graphics.inc notechar
pub const octachar = comptimeHex(octachar_hex, 128); // graphics.inc octachar

const ptn_end_str = [8]u8{ 0xbe, 0xbe, 0xbe, 0xbb, 0xbc, 0xbe, 0xbe, 0xbe }; // ptendch
const drvsig = [6]u8{ 'N', 'M', 'L', 'E', 'B', 'D' }; // menu.inc drvsig .text (ASCII in the official build)

fn comptimeHex(comptime hex: []const u8, comptime n: usize) [n]u8 {
    @setEvalBranchQuota(20000);
    var out: [n]u8 = undefined;
    inline for (0..n) |i| {
        out[i] = nyb(hex[i * 2]) * 16 + nyb(hex[i * 2 + 1]);
    }
    return out;
}

fn nyb(h: u8) u8 {
    return if (h <= '9') h - '0' else h - 'a' + 10;
}

const template_hex =
    "c080a0001000100010bdc080a0001000100010bdc05d5c5d5c5d5c5d5cbd3031494e535452554d2ec180a00010001000" ++
    "10bdc180a0001000100010bdc15d5c5d5c5d5c5d5cbd64650000000066676869c280a0001000100010bdc280a0001000" ++
    "100010bdc25d5c5d5c5d5c5d5cbd777800000000786c3279c380a0001000100010bdc380a0001000100010bdc35d5c5d" ++
    "5c5d5c5d5cbd6a6b000000106c6d6e70c180a0001000100010bdc180a0001000100010bdc15d5c5d5c5d5c5d5cbd7374" ++
    "0010001075762b31c180a0001000100010bdc180a0001000100010bdc15d5c5d5c5d5c5d5cbd574641525044547a7bc1" ++
    "c180a0001000100010bdc180a0001000100010bdc15d5c5d5c5d5c5d5cbdc1001000900010c10090c180a00010001000" ++
    "10bdc180a0001000100010bdc15d5c5d5c5d5c5d5cbdc2001000900010c20090c180a0001000100010bdc180a0001000" ++
    "100010bdc15d5c5d5c5d5c5d5cbdc3001000900010c30090c180a0001000100010bdc180a0001000100010bdc15d5c5d" ++
    "5c5d5c5d5cbdc4001000900010c40090c180a0001000100010bdc180a0001000100010bdc15d5c5d5c5d5c5d5cbdc500" ++
    "1000900010c50090c180a0001000100010bdc180a0001000100010bdc15d5c5d5c5d5c5d5cbdc6001000900010c60090" ++
    "c180a0001000100010bdc180a0001000100010bdc15d5c5d5c5d5c5d5cbdc7001000900010c70090c180a00010001000" ++
    "10bdc180a0001000100010bdc15d5c5d5c5d5c5d5cbdc8001000900010c80090c180a0001000100010bdc180a0001000" ++
    "100010bdc15d5c5d5c5d5c5d5cbd50554c53454b54c90090c180a0001000100010bdc180a0001000100010bdc15d5c5d" ++
    "5c5d5c5d5cbdc1001000900010ca0090c180a0001000100010bdc180a0001000100010bdc15d5c5d5c5d5c5d5cbdc200" ++
    "1000900010cb0090c180a0001000100010bdc180a0001000100010bdc15d5c5d5c5d5c5d5cbdc3001000900010cc0090" ++
    "c180a0001000100010bdc180a0001000100010bdc15d5c5d5c5d5c5d5cbdc4001000900010cd0090c180a00010001000" ++
    "10bdc180a0001000100010bdc15d5c5d5c5d5c5d5cbd46494c542e4b547c7dc1c180a0001000100010bdc180a0001000" ++
    "100010bdc15d5c5d5c5d5c5d5cbdc1001000900010c10090c180a0001000100010bdc180a0001000100010bdc15d5c5d" ++
    "5c5d5c5d5cbdc2001000900010c20090c180a0001000100010bdc180a0001000100010bdc15d5c5d5c5d5c5d5cbdc300" ++
    "1000900010c30090c180a0001000100010bdc180a0001000100010bdc15d5c5d5c5d5c5d5cbdc4001000900010c40090" ++
    "c180a0001000100010bdc180a0001000100010bdc15d5c5d5c5d5c5d5cbd8c8d8ec12d7c7dc8c47e0000000000000000" ++
    "00000000000000006070717273747576";

const notechar_hex =
    "5b80818283848586878889898b80818283848586878889898b80818283848586" ++
    "878889898b80818283848586878889898b80818283848586878889898b808182" ++
    "83848586878889898b80818283848586878889898b8081828384858687888989" ++
    "8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f0000000000000000aaababacacaf5fbb";

const octachar_hex =
    "5ca0b0a0b0a0a0b0a0b0a0b0a0a1b1a1b1a1a1b1a1b1a1b1a1a2b2a2b2a2a2b2" ++
    "a2b2a2b2a2a3b3a3b3a3a3b3a3b3a3b3a3a4b4a4b4a4a4b4a4b4a4b4a4a5b5a5" ++
    "b5a5a5b5a5b5a5b5a5a6b6a6b6a6a6b6a6b6a6b6a6a7b7a7b7a7a7b7a7b7a7b7" ++
    "101112131415161718191a1b1c1d1e1f" ++ "0000000000000000baadaeadaeaf60bc";

// -- static colour RAM (iniscrn ColoRow, features all ON) --------------------
// The asm's X counts screen rows downwards (X=24 is row 0); the branches below
// carry the same comparisons. Cols 0..29 default to fxcol everywhere; the
// instrument panel (cols 30..39) gets the differentiated scheme. Rows 0..23
// cols 0..29 are later re-coloured dynamically (stpdisp/mutesolodisp), row 24
// by row25back.
fn colCell(row: usize, col: usize) u4 {
    if (col < 30) return palette.fx; // Cpattn: horizontal division at col 30
    const x = 24 - row; // iniscrn's row counter
    if (x == 0) return palette.ipa; // SiPanel: row 24 (row25back re-differentiates)
    if (x == 19) return palette.itahdr; // SiTbHdr: row 5, c>=37 keeps itahdr (chChdSu)
    if (x > 19) { // rows 0..4: CiName/CiHeadr
        if (x == 24) { // row 0: instrument number + name
            return if (col >= 32) palette.ina else palette.instnum;
        }
        if (col < 32) return palette.ipa; // CiHeadr value-titles' edge columns
        const emph: u4 = if (x == 22 or x == 20) palette.ita else palette.itaemph;
        if (col < 38) return if (col < 36) emph else palette.disable;
        // c 38..39: fx colour (12) except the HRTY value (row 2, col 38,
        // `stx COLRPOS+2*40+38`); verified against cram dumped from VICE.
        return if (x == 22 and col == 38) palette.ita else palette.fx;
    }
    if (x == 5) return palette.itahdr; // row 19 (Cchdtmp beq, TEMPOPRGSUPP on)
    if (x < 5) { // rows 20..23: CtempoT (tempo table)
        if (col < 35) return palette.ita; // SiTable
        if (col < 37) return palette.fltkt; // c35/36: FILTKBTRACK on (X<10)
        return if (col == 37) palette.ipa else palette.ita; // c37 beq keeps ipacol
    }
    // rows 6..18: CchordT (chord table)
    if (col == 34 and x == 10) return palette.itahdr; // PULSEKT's 'E' (VICE cram)
    if (col < 35) return palette.ita;
    if (col < 37) return if (x < 10) palette.pwtkt else palette.detut; // cpx #10: bpl taken on equal
    return if (col == 37) palette.ipa else palette.ita; // c37 chChdSu keeps ipacol
}

/// The editor's colour RAM as iniscrn leaves it, before the dynamic passes.
const colortable: [ROWS][COLS]u4 = blk: {
    @setEvalBranchQuota(10000);
    var t: [ROWS][COLS]u4 = undefined;
    for (0..ROWS) |r| {
        for (0..COLS) |c| t[r][c] = colCell(r, c);
    }
    // the post-loop pre-sets (features all ON keep the "pre-set" colours)
    t[5][35] = 13; // DETUNESUPPORT: detune-table header colour 13
    t[5][36] = 13;
    t[14][35] = palette.pwtkt; // PWKBEYBTRACK
    t[14][36] = palette.pwtkt;
    t[19][35] = palette.fltkt; // FILTKBTRACK
    t[19][36] = palette.fltkt;
    break :blk t;
};

// -- pattern area (ptndisp/stpdisp/mutedis/row25back) -------------------------

/// One pattern row's 8 cells at track `t`, display row `r`, pattern bytes at
/// `off` (rowdlop). Returns the bytes consumed, or 0 if the row was the
/// pattern-end string (ptendch; the caller then blanks the rows below).
fn rowCells(scr: *Screen, t: usize, r: usize, base: []const u8, off: usize) usize {
    const col = 10 * t + 1; // trk(t)plc: cells at cols 10t+1..10t+8
    const v = base[off];
    if (v & 0x7f == 0x7f) { // ptnend: the whole row is the end string
        for (0..8) |k| putCh(scr, r, col + k, ptn_end_str[k]);
        return 0;
    }
    putCh(scr, r, col, notechar[v & 0x7f]);
    putCh(scr, r, col + 1, octachar[v & 0x7f]);
    var n: usize = 2;
    if (v & 0x80 != 0) { // instrument column follows
        const ins = base[off + 1];
        if (ins & 0x7f == 0) { // instrument $00 displays as blank pair
            putCh(scr, r, col + 2, 0xbd);
            putCh(scr, r, col + 3, 0xbd);
        } else {
            putCh(scr, r, col + 2, (ins & 0x7f) >> 4); // raw hi nybble digit
            putCh(scr, r, col + 3, 0x10 | (ins & 0x0f));
        }
        n = 4;
        if (ins & 0x80 != 0) { // fx column follows
            const fx = base[off + 2];
            putCh(scr, r, col + 4, fx >> 4);
            putCh(scr, r, col + 5, 0x10 | (fx & 0x0f));
            n = 6;
            if (fx & 0xe0 == 0) { // small fx: value column follows
                const fv = base[off + 3];
                putCh(scr, r, col + 6, fv >> 4);
                putCh(scr, r, col + 7, 0x10 | (fv & 0x0f));
                n = 8;
            }
        }
    }
    // filrlop: fill the empty tail (positions n..7) with the dash pairs
    while (n < 8) : (n += 1) {
        const ch: u8 = switch (n) {
            2, 3 => 0xbd,
            else => if (n & 1 == 0) 0x5d else 0x5e,
        };
        putCh(scr, r, col + n, ch);
    }
    return rowSize(base, off);
}

/// ptndisp: the three tracks' pattern rows.
fn patternDisp(song: *const swm.Song, view: *const View, scr: *Screen) void {
    for (0..3) |t| {
        const ptn = clampPtn(view.curptn1[t]);
        const base: []const u8 = if (ptn == 0) &[_]u8{ 0, 0xff } else &song.pats[ptn - 1];
        const start = walkPtn(base, view.prowpos[t]);
        var off: usize = start;
        var r: usize = 0;
        while (r < ROWS) : (r += 1) {
            if (off > swm.ptn_bound - 4) { // corrupt pattern: no endmark found
                var rr = r;
                while (rr < ROWS) : (rr += 1) {
                    for (0..8) |k| putCh(scr, rr, 10 * t + 1 + k, 0xbd);
                }
                break;
            }
            const n = rowCells(scr, t, r, base, off);
            if (n == 0) { // afterptn: blank every row below the endmark
                var rr = r + 1;
                while (rr < ROWS) : (rr += 1) {
                    for (0..8) |k| putCh(scr, rr, 10 * t + 1 + k, 0xbd);
                }
                break;
            }
            off += n; // rowdlop's zpvari3 walk (clamped by walkPtn's guard)
        }
    }
}

const hexchar = "0123456789ABCDEF"; // commonsubs.hexchar (ASCII, .enc "screen")

fn putCh(scr: *Screen, r: usize, c: usize, ch: u8) void {
    scr.chars[r][c] = ch;
}

fn putCl(scr: *Screen, r: usize, c: usize, col: u4) void {
    scr.colours[r][c] = col;
}

/// A row's byte count in pattern memory (getdelamount): 1 + instrument + fxval.
pub fn rowSize(base: []const u8, i: usize) usize {
    var n: usize = 1;
    if (base[i] & 0x80 == 0) return n; // note only
    n += 1;
    if (base[i + 1] & 0x80 == 0) return n; // note+inst
    n += 1;
    if (base[i + 2] & 0xe0 != 0) return n; // note+inst+bigfx
    return n + 1; // note+inst+fx+fxvalue
}

/// Byte index of display row `row` in pattern memory (setrpos/detmemp walk).
/// The C64 walks blindly into the next pattern's memory past the endmark; here
/// the walk stops at the $ff delimiter (deviation, see NOTES.md).
pub fn walkPtn(base: []const u8, row: u8) u8 {
    var i: u8 = 0;
    var r: u8 = 0;
    while (r < row) : (r += 1) {
        if (base[i] == swm.ptn_end or i >= swm.ptn_bound - 4) break; // endmark: stay put
        i +%= @intCast(rowSize(base, i)); // the asm wraps at the page boundary
    }
    return i;
}

/// stpdisp: the step-number characters ($c0|position) and their colours in the
/// number columns 0/10/20, all 25 rows. The played-row highlight only shows
/// when the played pattern equals the displayed one (player.CURPTN check).
fn stpDisp(view: *const View, scr: *Screen) void {
    var played: [3]u8 = undefined;
    var mod: [3]u8 = undefined;
    var tick: [3]u8 = undefined;
    for (0..3) |t| {
        played[t] = if (view.played_curptn[t] == view.curptn1[t])
            view.ptrowpos[t] -% view.prowpos[t]
        else
            0xff; // "if not, doesn't show playmarker"
        tick[t] = @max(view.stptick, 1); // the asm divides by 0 -> garbage
        mod[t] = view.prowpos[t] % tick[t];
    }
    for (0..ROWS) |r| {
        for (0..3) |t| {
            const col = 10 * t;
            putCh(scr, r, col, (view.prowpos[t] +% @as(u8, @intCast(r))) | 0xc0);
            var c: u4 = palette.ptrownum;
            if (mod[t] == 0) c = palette.downbeat;
            if (played[t] == @as(u8, @intCast(r))) c = palette.playposi;
            putCl(scr, r, col, c);
            mod[t] +%= 1;
            if (mod[t] == tick[t]) mod[t] = 0;
        }
    }
}

/// stpdisp's colour decision for one row (shared with row25back's COLtemp
/// restore, which needs row 24's colour after the 26th-row trick erased it).
fn stepColour(view: *const View, t: usize, r: usize) u4 {
    const played: u8 = if (view.played_curptn[t] == view.curptn1[t])
        view.ptrowpos[t] -% view.prowpos[t]
    else
        0xff;
    if (played == r) return palette.playposi;
    if ((view.prowpos[t] +% @as(u8, @intCast(r))) % @max(view.stptick, 1) == 0) return palette.downbeat;
    return palette.ptrownum;
}

/// mutesolodis (displayer2) + row25back: the track columns 10t+1..10t+4 of
/// rows 0..23. Note pair and instrument pair colour separately (confbits
/// bit7 clear = separate colours). mutesolo bit0 SET = unmuted (editor.asm
/// inits $FF; msolocol: mutecol,15 / mutecol,3 for the muted index 0).
fn muteColours(m: u8) struct { note: u4, inst: u4 } {
    const normal = m & 1 != 0;
    return .{
        .note = if (normal) palette.notecolu else palette.mutecol,
        .inst = if (normal) palette.instcolu else palette.mutecol,
    };
}

fn muteSoloDisp(view: *const View, scr: *Screen) void {
    for (0..3) |t| {
        const mc = muteColours(view.mutesolo[t]);
        for (0..ROWS - 1) |r| { // 24 rows (0..23)
            for (0..2) |k| putCl(scr, r, 10 * t + 1 + k, mc.note);
            for (2..4) |k| putCl(scr, r, 10 * t + 1 + k, mc.inst);
        }
    }
}

/// row25back: row 24's colours after the 26th-row trick — track columns get
/// the saved step colours (stpdisp's row-24 decision, irq.inc COLtemp) and
/// the mute colours, the panel area the static ones.
fn row25Back(view: *const View, scr: *Screen) void {
    const r = ROWS - 1;
    for (0..3) |t| {
        putCl(scr, r, 10 * t, stepColour(view, t, r)); // COLtemp restore
        const mc = muteColours(view.mutesolo[t]);
        putCl(scr, r, 10 * t + 1, mc.note);
        putCl(scr, r, 10 * t + 2, mc.note);
        putCl(scr, r, 10 * t + 3, mc.inst);
        putCl(scr, r, 10 * t + 4, mc.inst);
    }
    putCl(scr, r, 30, palette.ipa); // COLRPOS+$3de..$3e0
    putCl(scr, r, 31, palette.ipa);
    putCl(scr, r, 32, palette.ipa);
    putCl(scr, r, 33, palette.itahdr); // $3c0+$21
    for (34..37) |c| putCl(scr, r, c, palette.ipa);
    for (37..39) |c| putCl(scr, r, c, palette.itahdr);
    putCl(scr, r, 39, palette.ipa);
}

// -- instrument panel (insdisp + commonsubs.ihexdis/hexdis2/wf1disp) ----------

const vibtype = [8]u8{ 0x6f, 0x70, 0x6e, 0x70, 0x6e, 0x71, 0x6e, 0x72 }; // displayer1
const imainpos = [_]u8{ 0x70, 0x72, 0x48, 0x4a, 0x98, 0x9a, 0xc0, 0xc2 }; // vidram offsets

/// The selected instrument's data (clampPtn-style; 1..36 usable).
fn clampInst(n: u8) u8 {
    return if (n == 0 or n > swm.inst_count) 1 else n;
}

fn insPanel(song: *const swm.Song, view: *const View, scr: *Screen) void {
    const ins: []const u8 = &song.insts[clampInst(view.selinst)];
    // selinst number: hexdis2 gives hi in A, lo in X; both ASCII hexchar
    putCh(scr, 0, 30, hexchar[view.selinst >> 4]);
    putCh(scr, 0, 31, hexchar[view.selinst & 0x0f]);
    if (!view.namemode) { // name hidden while typing a new one
        for (0..8) |k| putCh(scr, 0, 32 + k, ins[swm.inst_usable + k]);
    }
    wf1Disp(scr, ins);
    insCtl(scr, ins);
    // numeric main data (ihexdis loop, y=1..8)
    inline for (1..9) |k| {
        const pos = imainpos[k - 1];
        const r: usize = pos / COLS;
        const c: usize = pos % COLS;
        const lo: u8 = if (k >= 6) 0x10 | (ins[k] & 0x0f) else ins[k] & 0x0f;
        putCh(scr, r, c, ins[k] >> 4); // hi nybble, raw digit
        putCh(scr, r, c + 1, lo);
    }
    // octave (ins[9] signed): sign at $c6, div12 quotient|$30 at $c7
    const oct = ins[9];
    const neg = oct & 0x80 != 0;
    const val: u8 = if (neg) 0 -% oct else oct; // sec/sbc #1/eor $ff = -oct
    const sign: u8 = if (oct == 0) ' ' else if (neg) '-' else '+';
    putCh(scr, 4, 38, sign);
    putCh(scr, 4, 39, 0x30 | (val / 12));
    insTables(scr, ins, view);
}

/// wf1disp: 1st frame waveform (ins[15]) into waform1, displayed by the
/// control-byte bits 3 (conad[3]/[4] cells; off values are $69,$69).
fn wf1Disp(scr: *Screen, ins: []const u8) void {
    const ctrl = ins[0];
    const wf1 = ins[15];
    const hi: u8 = wf1 >> 4; // waform1[0]
    const lo: u8 = 0x90 | (wf1 & 0x0f); // waform1[1]
    const on = ctrl & 8 != 0;
    putCh(scr, 1, 38, if (on) hi else 0x69); // conad[3] = vidram+$4e
    putCh(scr, 1, 39, if (on) lo else 0x69); // conad[4] = vidram+$4f
}

/// condisa: the instrument control byte's bits as colours/glyphs.
fn insCtl(scr: *Screen, ins: []const u8) void {
    const ctrl = ins[0];
    // bit7 ($80): rows 19 c30-33; bit6 ($40): row 14 c30-33. conboff/conbons:
    // off = 15 (ina), on = 11 (the "gate" highlight colour).
    const b7: u4 = if (ctrl & 0x80 != 0) palette.gateoff else palette.ina;
    const b6: u4 = if (ctrl & 0x40 != 0) palette.gateoff else palette.ina;
    for (30..34) |c| {
        putCl(scr, 19, c, b7);
        putCl(scr, 14, c, b6);
    }
    putCh(scr, 2, 39, if (ctrl & 4 != 0) 0x79 else 0x7f); // conad[2] = vidram+$77
    putCh(scr, 2, 38, 0x30 | (ctrl & 3)); // HR timer digit (vidram+$76)
    const vi: usize = (ctrl >> 3) & 6; // vibtype index (lsr x3, and #6)
    putCh(scr, 3, 38, vibtype[vi]); // vidram+$9e/$9f
    putCh(scr, 3, 39, vibtype[vi + 1]);
}

// -- instrument tables (displayer1 tablecommon) -------------------------------

const dot1: u8 = 0x61; // tablp1's dot characters
const dot2: u8 = 0x62;
const dot3: u8 = 0x63;
const rule1: u8 = 0xbb; // the $ff endsignal string
const rule2: u8 = 0xbc;

/// Reads the instrument slot with the 6502's 8-bit wrap folded back into the
/// slot (the C64 would walk into the next instrument's memory past 127 —
/// deviation, see NOTES.md).
fn insByte(ins: []const u8, off: u8) u8 {
    return ins[off & (swm.inst_size - 1)];
}

/// One table's rows (wf: 8 rows at row6 c30, pw: 4 at row15 c30, ctf: 4 at
/// row20 c30). `dstart`/`gateoff`/`jbase` in instrument-slot byte units; all
/// u8 arithmetic wraps like the 6502's 8-bit pointer walks.
fn tableCommon(scr: *Screen, ins: []const u8, row0: usize, nrows: usize, x0: u8, dstart: u8, gateoff: u8, jbase: u8) void {
    const goff = (gateoff -% jbase) / 3; // div3acu'd gateoff row number
    var x: u8 = x0; // displayed table-position numbers
    var d: u8 = dstart; // data pointer (zpvari2)
    var ended: bool = false; // zpvari5
    for (0..nrows) |r| {
        const rr = row0 + r;
        // numbering cell (tablp1): ipacol, gateoffcol at the gateoff row
        putCl(scr, rr, 30, if (x == goff) palette.gateoff else palette.ipa);
        putCh(scr, rr, 30, x | 0xc0);
        x +%= 1;
        // col1: value $00 dots, $ff endsignal rule + "ended" for later rows
        const v1 = insByte(ins, d);
        d +%= 1;
        if (ended) {
            putCh(scr, rr, 31, dot1);
            putCh(scr, rr, 32, dot2);
        } else if (v1 == 0) {
            putCh(scr, rr, 31, dot1);
            putCh(scr, rr, 32, dot2);
        } else if (v1 == 0xff) {
            ended = true;
            putCh(scr, rr, 31, rule1);
            putCh(scr, rr, 32, rule2);
        } else {
            putCh(scr, rr, 31, v1 >> 4); // instant hexa display
            putCh(scr, rr, 32, 0x10 | (v1 & 0x0f));
        }
        // col2: a $fe in col1 displays the divided jump target, else dots/hex
        const v2 = insByte(ins, d);
        d +%= 1;
        if (ended) {
            putCh(scr, rr, 33, dot1);
            putCh(scr, rr, 34, dot3);
        } else if (v2 == 0) {
            putCh(scr, rr, 33, dot1);
            putCh(scr, rr, 34, dot3);
        } else {
            const val: u8 = if (v1 == 0xfe) (v2 -% jbase) / 3 else v2;
            putCh(scr, rr, 33, val >> 4);
            putCh(scr, rr, 34, 0x90 | (val & 0x0f));
        }
        // col3: dots when 0 or when col1 was a $fe jump command (no00c3)
        const v3 = insByte(ins, d);
        d +%= 1;
        if (ended or v3 == 0 or v1 == 0xfe) {
            putCh(scr, rr, 35, dot1); // last0di
            putCh(scr, rr, 36, dot2);
        } else {
            putCh(scr, rr, 35, v3 >> 4);
            putCh(scr, rr, 36, 0x10 | (v3 & 0x0f));
        }
    }
}

// -- out-of-range View fields clamp, never crash ------------------------------

fn clampPtn(n: u8) u8 {
    return if (n > swm.ptn_count) swm.ptn_count else n; // 0 keeps the dummy
}

fn clampRow(n: u8) u8 {
    return @min(n, ROWS - 1); // subwpos3[0] is 0..24 in the editor
}

fn clampTrack(n: u8) u8 {
    return @min(n, 2); // subwpos1[0..1], subwpos2[1] etc.
}

fn clampSubt(n: u8) u8 {
    return @min(n, swm.max_subtune - 1); // selsubt 0..7
}

fn clampChor(n: u8) u8 {
    return @min(n, swm.max_chord - 1); // selchor 1..32 (0 unused by the editor)
}

fn clampTemp(n: u8) u8 {
    return @min(n, swm.max_tempopg - 1); // seltemp 1..63
}

/// insdisp's three tableCommon calls (wf/pw/ctf subtables).
fn insTables(scr: *Screen, ins: []const u8, view: *const View) void {
    tableCommon(scr, ins, 6, 8, view.wfarpos, // wfplace: WF/ARP/DETUNE table
        view.wfarpos *% 3 +% WFTABLEPOS, ins[12], WFTABLEPOS);
    tableCommon(scr, ins, 15, 4, view.pwtbpos, // pwplace: PW/KT table
        view.pwtbpos *% 3 +% ins[10], ins[13], ins[10]);
    tableCommon(scr, ins, 20, 4, view.ctftpos, // ctplace: FILTER/KT table
        view.ctftpos *% 3 +% ins[11], ins[14], ins[11]);
}

// -- chord & tempo programs (displayer1 chtmdis + incptr2) --------------------

const chd_rows = 13; // chtmdis ldy #$0d
const ctm_rows = 4; // incptr2 ldy #4

/// CHDPTR cache (depkinsch's inchdpt as toC64 builds it): chord n's start
/// index in chords[]; unwritten slots keep the last written value.
pub fn chordStart(song: *const swm.Song, selin: u8) u8 {
    const sel = clampChor(selin);
    if (sel <= 1) return sel; // CHDPTR[0]=0 (NOP), CHDPTR[1]=1 (editor init)
    var x: u8 = 1; // slot counter; slot 1 = chords[1] (editor init)
    var val: u8 = 1;
    for (1..swm.chord_len) |k| {
        if (song.chords[k] == swm.chord_end1 or song.chords[k] == swm.chord_end2) {
            x += 1;
            if (x < swm.max_chord) val = @intCast(k + 1 & 0xff);
            if (x == sel) return val;
        }
    }
    return val;
}

/// TEMPTR cache (depktempo): tempo program n's index in tempo[]; TEMPTR holds
/// TEMPOTBL-relative lo bytes (page aligned, RESTEMP = +8), so the Song index
/// is ptr - 9. Programs 0 and 1 both sit at tempo[0].
pub fn tempoStart(song: *const swm.Song, selin: u8) u8 {
    const sel = clampTemp(selin);
    if (sel <= 1) return 0; // TEMPTR[0]/[1] = RESTEMP+1 = tempo[0] ("need not be set")
    var t: u8 = 1; // slot counter; slots 0/1 = tempo[0] ("need not be set")
    var val: u8 = 0;
    for (0..swm.tempo_len) |y| {
        if (song.tempo[y] >= 0x80) { // depktempo: only delimiters stack pointers
            t += 1;
            if (t < swm.max_tempopg) val = @intCast(y + 1);
            if (t == sel) return val;
        }
    }
    return val;
}

/// incptr2: one table's row (number at c37, value pair at c38/39). Number
/// mode (confbits bit6 clear): values display as raw hi / $90|lo digits;
/// $7e/$7f (chord) resp. any bit7 (tempo) byte ends the program.
fn chTmCell(scr: *Screen, rr: usize, x: u8, ended: bool, v: u8, chord: bool) void {
    putCh(scr, rr, 37, x | 0xc0);
    if (ended) {
        putCh(scr, rr, 38, dot1); // aftertb
        putCh(scr, rr, 39, dot3);
        return;
    }
    const end: bool = if (chord)
        v == swm.chord_end1 or v == swm.chord_end2
    else
        v >= 0x80;
    const disp: u8 = if (chord and v >= 0x80) v else v & 0x7f; // and #$7f / raw
    if (end) {
        putCh(scr, rr, 38, disp >> 4); // dispnum
        putCh(scr, rr, 39, 0x90 | (disp & 0x0f));
        return;
    }
    // decidtb: BMI (chord v>=0x80) or BPL (tempo v<0x80) land in chNoteM ->
    // clc/bcc dispnum (NoteArp's note mode is compiled out in this build)
    putCh(scr, rr, 38, v >> 4);
    putCh(scr, rr, 39, 0x90 | (v & 0x0f));
}

/// chtmdis: chord program table (13 rows at row6 c37) + tempo program table
/// (4 rows at row20 c37), plus the selected-program markers. The numbering
/// chars wrap from the $c0|pos seed (X inx at $ff rolls to $00); once a
/// program ends, every later row displays dots (zpvari4's $ff).
fn chTmDisp(song: *const swm.Song, view: *const View, scr: *Screen) void {
    const cstart = chordStart(song, view.selchor);
    var x: u8 = view.chorpos | 0xc0; // chorpos ora #$c0 = the numbering seed
    var ended = false;
    for (0..chd_rows) |r| {
        const v = song.chords[cstart +% @as(u8, @intCast(r))];
        chTmCell(scr, 6 + r, x, ended, v, true);
        ended = ended or v == swm.chord_end1 or v == swm.chord_end2;
        x +%= 1;
    }
    putCh(scr, 5, 39, view.selchor | 0xc0); // selchor marker (vidram+$ef)
    const tstart = tempoStart(song, view.seltemp);
    x = view.temppos | 0xc0;
    ended = false;
    for (0..ctm_rows) |r| {
        const idx: usize = @min(tstart +% @as(u8, @intCast(r)), swm.tempo_len - 1);
        const v = song.tempo[idx];
        chTmCell(scr, 20 + r, x, ended, v, false);
        ended = ended or v >= 0x80;
        x +%= 1;
    }
    putCh(scr, 19, 39, view.seltemp | 0xc0); // seltemp marker (vidram+$31f)
}

const WFTABLEPOS = 16; // globalconstants.inc (settings.cfg)

// -- misc / row 26 / upper border --------------------------------------------

/// miscdis: the selected subtune's number and its funk tempo pair at the
/// panel's bottom row (stplace/vidram+$3e5/$3e6). The editor's RESTEMP words
/// hold the current subtune's funk pair (playadapter copies it on subtune
/// switch), so the values come from funk[selsubt].
fn miscDisp(song: *const swm.Song, view: *const View, scr: *Screen) void {
    const st: usize = clampSubt(view.selsubt);
    putCh(scr, 24, 33, view.selsubt | 0xc0); // stplace
    const f = song.funk[st];
    putCh(scr, 24, 37, f[0] | 0xc0); // vidram+$3e5
    // bit7 set: the speed is a plain $20 space; else the second tempo's char
    putCh(scr, 24, 38, if (f[0] & 0x80 != 0) 0x20 else f[1] | 0xc0); // $3e6
}

/// seqdisp: the orderlist position numbering in the hidden 26th row; the
/// pair matching olstart[0] is displayed with ASCII hexchar glyphs.
fn seqDisp(view: *const View, over: *Overlay) void {
    over.row26_title = false;
    over.row26_mark = 0xff;
    for (0..20) |i| {
        const pos: u8 = view.seqposdisp +% @as(u8, @intCast(i));
        var hi: u8 = pos >> 4;
        var lo: u8 = 0x90 | (pos & 0x0f);
        if (pos == view.olstart[0]) { // cmp playadapter.olstart: ASCII pair
            over.row26_mark = @intCast(i);
            hi |= 0x30;
            lo = hexchar[pos & 0x0f];
        }
        over.row26[i * 2] = hi;
        over.row26[i * 2 + 1] = lo;
    }
}

const authorilen = 40; // settings.cfg (header author-info length)

/// dispaut (menu.inc): the tune's author/title text in row 26 after a load,
/// until the first keypress (view.titledi).
fn dispAut(song: *const swm.Song, view: *const View, over: *Overlay) void {
    over.row26_title = true;
    for (0..authorilen - 2) |i| over.row26[i] = song.header[swm.H_AUTHOR + i];
    over.row26[38] = 0xbd; // separator
    over.row26[39] = drvsig[view.drvidx % drvsig.len];
}

/// ordldis: the 20 orderlist values per track read for the low-border
/// sprites, plus the played-position underline. Values are read at
/// (seqposdisp + k) & 0x7f (the C64's Y wraps into the next slot — clamped,
/// see NOTES.md). The underline shows only on tracks whose olstart differs
/// from track 0's (markpos $c0 sentinel otherwise).
fn ordlDis(song: *const swm.Song, view: *const View, over: *Overlay) void {
    for (0..3) |t| {
        const st: usize = @as(usize, clampSubt(view.selsubt)) * 3 + t;
        const seq: []const u8 = &song.seqs[st];
        for (0..20) |k| {
            const idx: u8 = (view.seqposdisp +% @as(u8, @intCast(k))) & 0x7f;
            over.ordl_val[t][k] = seq[idx];
        }
        // markpos: skip track 0 and tracks sharing track 0's position
        over.ordl_mark[t] = -1;
        if (t != 0 and view.olstart[t] != view.olstart[0]) {
            const col = view.olstart[t] -% view.seqposdisp;
            if (col < 20) over.ordl_mark[t] = @intCast(col);
        }
    }
}

const curcols = [_]u8{
    0x00, 0x0b, 0x06, 0x04, 0x0e, 0x0c, 0x03, 0x0f, 0x0d, 0x07, 0x07, 0x01,
    0x07, 0x01, 0x01, 0x07, 0x01, 0x07, 0x07, 0x0d, 0x0f, 0x0a, 0x0c, 0x08,
    0x02, 0x0b, 0x09, 0x00, 0x09, 0x00, 0x00, 0x09,
}; // cursord's flasher table

const iswposx = [4]u8{ 32, 31, 31, 31 }; // instrument-window X base positions
const iswposy = [4]u8{ 1, 6, 15, 20 }; //   ...Y base positions (common,wf,pw,ctf)

/// cursord: the editor cursor's sprite coordinates, size and flash colour.
fn cursorDis(song: *const swm.Song, view: *const View, over: *Overlay) void {
    var x: u16 = 0;
    var y: u16 = 0;
    var wide = false;
    // The 6502 writes raw row/col bytes into the sprite registers (wrapping at
    // 256 on real hardware); the port clamps them to the visible screen
    // instead (deviation, see NOTES.md).
    if (view.namemode) { // namemode: instrument-name typing row
        x = @as(u16, @min(32 +% view.inamepos, 39)) * 8 + 24;
        y = 34; // cury 0
    } else switch (view.curwind) {
        0 => { // pattern window
            y = @as(u16, clampRow(view.subwpos3[0])) * 8 + 34;
            const s2 = view.subwpos2[0];
            wide = s2 == 0;
            const t: u8 = clampTrack(view.subwpos1[0]);
            const col: u8 = @as(u8, @intCast(10 * t)) +% (if (s2 != 0) @min(s2, 8) + 1 else 0);
            x = @as(u16, col) * 8 + 24;
        },
        1 => { // orderlist window: raw Y (0..2, PAL rows), no *8+34
            y = clampTrack(view.subwpos1[1]);
            x = @as(u16, @min(view.subwpos2[1], 39)) * 8 + 24;
        },
        2 => { // instrument window: 4 subwindows 0..3
            const w: u8 = @min(view.subwpos1[2], 3);
            var col: u8 = view.inswXbuf[w] +% iswposx[w];
            if (w == 0 and col >= 36) col +%= 2; // noiwin0 quirk
            x = @as(u16, @min(col, 39)) * 8 + 24;
            y = @as(u16, @min(view.inswYbuf[w] +% iswposy[w], 24)) * 8 + 34;
        },
        3 => { // chord table
            y = @as(u16, @min(view.subwpos1[3] +% 6, 24)) * 8 + 34;
            x = @as(u16, @min(38 +% view.subwpos2[3], 39)) * 8 + 24;
            wide = song.header[swm.H_CBIT] & 0x40 != 0; // note-mode = double-wide
        },
        else => { // tempo table (4)
            y = @as(u16, @min(view.subwpos1[4] +% 20, 24)) * 8 + 34;
            x = @as(u16, @min(38 +% view.subwpos2[4], 39)) * 8 + 24;
        },
    }
    over.cursor_x = x;
    over.cursor_y = y;
    over.cursor_2x = wide;
    over.cursor_col = curcols[view.curcolc % curcols.len];
}

/// upbordisp: the upper-border sprite readouts (play-runtime values are left
/// as the host presetts them in the Overlay).
fn upbordDis(song: *const swm.Song, view: *const View, over: *Overlay) void {
    for (0..3) |t| {
        const ptn = clampPtn(view.curptn1[t]);
        over.upbord_patnum[t] = view.curptn1[t];
        over.upbord_ptnsize[t] = song.ptn_size[ptn] -% 1; // sec/sbc #1
    }
    over.upbord_octave = view.octave +% 1; // jamoctave ldy #4; iny
    over.upbord_autoadv = view.autoadv != 0;
}

// -- top level ----------------------------------------------------------------

/// render(): the editor's 25x40 text screen (screen codes + colour RAM),
/// exactly as displayer1/displayer2 paint it. Pure: no I/O, no globals.
pub fn render(song: *const swm.Song, view: *const View, screen: *Screen) void {
    // iniscrn: the static template + ColoRow scheme every frame starts from
    for (0..ROWS) |r| {
        for (0..COLS) |c| {
            screen.chars[r][c] = template[r * COLS + c];
            screen.colours[r][c] = colortable[r][c];
        }
    }
    patternDisp(song, view, screen); // ptndisp
    stpDisp(view, screen); // stpdisp (chars + colours of the number columns)
    muteSoloDisp(view, screen); // mutesolodisp
    insPanel(song, view, screen); // insdis (the right-side instrument panel)
    miscDisp(song, view, screen); // miscdis (subtune number + speeds)
    chTmDisp(song, view, screen); // chtmdis (chord + tempo program tables)
    row25Back(view, screen); // row25back (row 24 colours after the trick)
}

/// overlayRender(): the data behind what the editor shows with sprites: the
/// hidden 26th row, the low-border orderlist columns, the cursor sprite and
/// the upper-border readouts. Pure; play-runtime Overlay fields (songtime,
/// PW/cutoff meters) must be presetted by the host and are left untouched.
pub fn overlayRender(song: *const swm.Song, view: *const View, over: *Overlay) void {
    // display's order: seqdisp (unless titledi) -> ordldis -> upbordisp ->
    // cursord; the screen-side passes live in render().
    if (view.titledi) dispAut(song, view, over) else seqDisp(view, over);
    ordlDis(song, view, over);
    // ptncurs: rowdlop's byte index under the cursor row (setrpos + the
    // rowdlop zpvari3 store; absolute index = walkPtn of the absolute row)
    for (0..3) |t| {
        const ptn = clampPtn(view.curptn1[t]);
        const base: []const u8 = if (ptn == 0) &[_]u8{ 0, 0xff } else &song.pats[ptn - 1];
        // ptnMpos = walk(prowpos), ptncurs = walk(prowpos+row) - ptnMpos:
        // display-relative index exactly as rowdlop/setrpos track them.
        const mpos = walkPtn(base, view.prowpos[t]);
        over.ptncurs[t] = walkPtn(base, view.prowpos[t] +% clampRow(view.subwpos3[0])) -% mpos;
    }
    upbordDis(song, view, over);
    cursorDis(song, view, over);
}

// -- the file dialog's screen (Part 4) ---------------------------------------

fn textAt(scr: *Screen, r: usize, c: usize, text: []const u8, col: u4) void {
    for (text, 0..) |ch, i| {
        if (c + i >= COLS) break;
        scr.chars[r][c + i] = ch; // ASCII straight into screen RAM
        scr.colours[r][c + i] = col;
    }
}

/// filerRender: the dialog's text screen (filedialog/dismenu in menu.inc).
/// The KERNAL directory reader and its exact painting are host-side; this
/// shows the same information (name field, author field, three file columns,
/// status line) from filer.State. Pure.
pub fn filerRender(view: *const View, scr: *Screen) void {
    const st = &view.filer;
    for (0..ROWS) |r| {
        for (0..COLS) |c| {
            scr.chars[r][c] = ' ';
            scr.colours[r][c] = file_fg;
        }
    }
    // menu.inc filetx1/filetx2: the layout of the C editor's own dialog (its character-ROM look is the host's font)
    textAt(scr, 0, 0, "FILENAME:", file_fg);
    const ext: []const u8 = switch (st.kind) {
        .tune => ".SWM)",
        .instrument => ".SWI)",
        .config => ".CFG)",
    };
    textAt(scr, 0, 22, "|(FILETYPE:*", file_fg);
    textAt(scr, 0, 34, ext, file_fg);
    typer(scr, 0, 10, &st.name, st.window == .name_typer, st.name_pos);
    for (0..COLS) |c| for ([_]usize{ 1, 3, 23 }) |r| {
        scr.chars[r][c] = '-';
    };
    if (st.editauth) typer(scr, 2, 0, &st.author, st.window == .author_typer, st.author_pos);
    for (0..st.count) |i| {
        const row = 4 + i % filer.page_rows;
        const col = 1 + (i / filer.page_rows) * 13;
        const e = st.entries[i];
        const n = @min(e.len, filer.max_name);
        const sel = st.window == .selector and i == st.sel;
        const colr: u4 = if (sel) file_sel else file_fg;
        if (e.name[0] == 0x7F) { // a folder: its name after a slash
            scr.chars[row][col] = '/';
            textAt(scr, row, col + 1, e.name[1..n], colr);
            scr.colours[row][col] = colr;
        } else textAt(scr, row, col, e.name[0..n], colr);
    }
    textAt(scr, 24, 0, "DR:", file_fg);
    textAt(scr, 24, 3, std.mem.trimEnd(u8, &view.filer_loc, " "), file_fg);
    textAt(scr, 24, 28, "F1,F3:DIR", file_fg);
    const status = switch (st.status) {
        .ok => "",
        .no_device => " NO DISK OR DRIVE PRESENT!!! ",
        .not_found => " FILE NOT FOUND! PRESS SPACE.",
        .version => " WRONG VERSION0! PRESS SPACE.",
        .save_error => " SAVING ERROR 0! PRESS SPACE. ",
    };
    textAt(scr, 1, 0, status, file_sel);
}

pub const file_fg: u4 = 11; // fileFGcolor
pub const file_bg: u4 = 15; // fileBGcolor
const file_sel: u4 = 1;

/// A typed field: its text, white while it is the active window, an underline at the cursor.
fn typer(scr: *Screen, row: usize, col: usize, buf: []const u8, active: bool, pos: u8) void {
    const colr: u4 = if (active) file_sel else file_fg;
    for (buf, 0..) |ch, i| {
        scr.chars[row][col + i] = if (ch == 0x7F) '/' else ch; // a folder's mark
        scr.colours[row][col + i] = colr;
    }
    if (active and pos < buf.len) {
        scr.chars[row][col + pos] = if (buf[pos] == ' ') '_' else buf[pos];
    }
}
