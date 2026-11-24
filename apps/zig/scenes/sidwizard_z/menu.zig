// --------------------------------------------------------------------------
// menu.zig — SID-Wizard 1.97 main menu (Part 4).
// Port of asm/include/menu.inc: the 22x19 menu block (dispmenu/menutxt), its
// per-row editors (menuinc/menudec, IncDriv/DecDriv, IncPtln/DecPtln,
// IncFspd, KeyLayout, the eorconf toggles), the "are you sure" dialog
// (RyouSur/YesOrNo) and the two kill items (CINITUN/CININST).
//
// Split of duties (the asm has no such split): this module owns the menu's
// state transitions and its pure rendering; the host owns file I/O, so the
// SAVE/LOAD rows only report an Action. Menu state lives in display.View so
// keys.zig can drive it without importing this file from display.zig.
//
// No globals, no allocator, no floats.
// --------------------------------------------------------------------------

const swm = @import("swm.zig");
const dsp = @import("display.zig");

// -- geometry (settings.cfg menuxpos/menuypos; menu.inc derived values) ------
pub const xpos = 9; // menuxpos
pub const ypos = 2; // menuypos (MIDI off, 1SID build)
pub const cols = 19; // menuxsize
pub const rows = 22; // menuysize
pub const help_rows = 20; // helpYsize
pub const firstcpos = 3; // firstcpos: the SAVE TUNE row
pub const lastcrpos = 20; // lastcrpos: the INSTANT HELP! row
pub const drivemenupt = 7; // drivemenupt: row of SELECT DRIVE
pub const ptlenmenupt = 10; // ptlenmenupt: row of DEF.PATT.LEN

// -- limits (settings.cfg / editor.asm) --------------------------------------
pub const min_device = 8; // MINDEVICE
pub const max_device = 30; // MAXDEVICE
pub const min_ptn_len = 1; // minptnlen
pub const max_ptn_len = 249; // maxptnlen
pub const pal_max_framesp = 8; // PALmaxframespeed (1SID build)
pub const theme_count = 9; // (ColorThemesEnd-ColorThemes)/(ColorSetEnd-ColorSet)

// -- "are you sure" dialog state (menu.menuprompt) ---------------------------
pub const prompt_none = 0;
pub const prompt_tune = 1; // initunt -> RyouSur -> CINITUN
pub const prompt_inst = 2; // iniinsc -> RyouSur -> CININST

/// What a menu row asks the host to do. `.redraw` covers every row that only
/// edits editor state (the menu stays open, as in the asm's `jmp mainloop`).
pub const Action = enum {
    none,
    redraw,
    close_redraw, // kill item finished: menu closed, editor repainted
    save_tune,
    load_tune,
    save_inst,
    load_inst,
    save_config, // SaveConfig returns to the open menu (cfgstat reports)
};

// -- rendering data ----------------------------------------------------------

/// menutxt..menutxtend (menu.inc), 22 rows of 19 screen codes. The dynamic
/// fields carry their asm default text and are overwritten by fillDynamic.
const menu_text = [rows][]const u8{
    "*******************",
    "*  - MAIN MENU -  *",
    "* --------------- *",
    "*    SAVE TUNE    *",
    "*    LOAD TUNE    *",
    "* SAVE INSTRUMENT *",
    "* LOAD INSTRUMENT *",
    "* SELECT DRIVE:08 *",
    "* SAV.AUT.DIR:OFF *",
    "* FRAMESPEED: 1X  *",
    "* DEF.PATT.LEN:00 *",
    "* KILL TUNE&TEMPO *",
    "* KILL INST&CHORD *",
    "* COLOR: ORIGINAL *",
    "* KEY-LAYOUT:SIDW *",
    "* AUTO-INSTR: OFF *",
    "* AUTOFOLLOW: OFF *",
    "* HIDE RBARS: ON  *",
    "* CHORD-NOTE: ON  *",
    "*   SAVE CONFIG   *",
    "*  INSTANT HELP!  *",
    "*******************",
};

/// helptxt..helptxend (menu.inc), 20 rows of 19 screen codes. The last row's
/// year comes from settings.cfg's ^Year.
const help_text = [help_rows][]const u8{
    "F1/F2 PLAY ALL/MARK",
    "F3/F4 PLAYPATT/STOP",
    " <-   FAST-FORWARD ",
    "F5/F6 PATT/ORDERLST",
    "SPACE EDIT/JAM MODE",
    " F7   EDIT INSTRUM.",
    "+ / - SELECT INSTR.",
    "C=+,/. SET SUBTUNE ",
    "RETURN NOTEOFF/SEL.",
    "SH+1..3 MUTE/UNMUTE",
    "C=+1..8 SET OCTAVE ",
    "SHIFT+N NAME INSTR.",
    "C=F5/F7 CHORD/TEMPO",
    "C=X/C/V COPY/PASTE ",
    "SH+SPACE PLACE MARK",
    "SHIFT+F/G FRAMESPD.",
    "SHIFT+Q/W TRANSPOSE",
    "FX1,2,3:SLIDE,PORTA",
    "-------------------",
    " 2026 HERMIT SOFT. ",
};

/// ThemeNames (displayer2.inc): 9 names, 8 screen codes each.
const theme_names = "DEFAULT BRIGHTERGREENISHTURKISH  BLUISH  PURPLE BROWNISHRED&GREYAMISH :)";

/// KeyTypes (menu.inc): 4 layouts, 4 screen codes each. dispmenu indexes it
/// with Config.KeybTyp & $1f (0, $2c, $44, $88 -> 0, 12, 4, 8).
const key_types = "SIDW DMC SDI JANK";

/// ColorThemes: per theme only the menu colours (indices 14/15 of each
/// 16-colour set) and fxcol (index 3, the colour the asm puts back under a
/// cleared menu) matter here. Full editor-palette switching stays in the
/// displayer (Palette is the theme-0 set in Part 2).
const ThemeMenu = struct { bg: u4, cur: u4, fx: u4 };
const theme_menu = [theme_count]ThemeMenu{
    .{ .bg = 14, .cur = 15, .fx = 12 }, // DEFAULT
    .{ .bg = 14, .cur = 13, .fx = 12 }, // BRIGHTER
    .{ .bg = 13, .cur = 3, .fx = 5 }, // GREENISH
    .{ .bg = 3, .cur = 1, .fx = 5 }, // TURKISH
    .{ .bg = 14, .cur = 3, .fx = 6 }, // BLUISH
    .{ .bg = 4, .cur = 7, .fx = 4 }, // PURPLE
    .{ .bg = 8, .cur = 7, .fx = 9 }, // BROWNISH
    .{ .bg = 2, .cur = 10, .fx = 2 }, // RED&GREY
    .{ .bg = 12, .cur = 1, .fx = 15 }, // AMISH :)
};

// row indices (menupoint = row - firstcpos + 1)
const r_drive = 7;
const r_autodir = 8;
const r_frspd = 9;
const r_ptlen = 10;
const r_theme = 13;
const r_keyb = 14;
const r_autoins = 15;
const r_autofollow = 16;
const r_rasterbar = 17;
const r_chordnote = 18;
const r_cfgstat = 19;

// column offsets of the dynamic fields inside a row
const c_drive = 15; // drivetx (2 digits)
const c_autodir = 15; // audirtx ("N " / "FF")
const c_frspd = 14; // frspdtx (one digit, then the literal 'X')
const c_ptlen = 15; // ptlentx (2 hex digits)
const c_theme = 9; // themetx (8 chars)
const c_keyb = 13; // keybttx (4 chars)
const c_toggle = 15; // autistx/autfltx/rastbtx/notectx ("N " / "FF")
const c_cfgstat = 16; // cfgstat ("!" on a failed config save)

// -- small formatters --------------------------------------------------------

/// commonsubs.decdis2: two decimal digits (Y = tens, A = units).
fn dec2(v: u8) [2]u8 {
    const d = v % 100;
    return .{ '0' + d / 10, '0' + d % 10 };
}

/// commonsubs.hexdis2: two hex digits (A = high, X = low).
fn hex2(v: u8) [2]u8 {
    const digits = "0123456789ABCDEF";
    return .{ digits[v >> 4], digits[v & 0x0f] };
}

/// diOnOff/diOnOf2: X/Y after testing a confbits bit (SET -> "N ", clear ->
/// "FF"; the row text already ends in the 'O').
fn onOff(bit: u8) [2]u8 {
    return if (bit != 0) .{ 'N', ' ' } else .{ 'F', 'F' };
}

fn themeName(n: u8) *const [8]u8 {
    return theme_names[@as(usize, n % theme_count) * 8 ..][0..8];
}

fn keyType(k: u8) *const [4]u8 {
    // the asm would read past KeyTypes for an invalid layout; clamp instead
    const i = @min(@as(usize, k & 0x1f), key_types.len - 4);
    return key_types[i..][0..4];
}

// -- rendering ---------------------------------------------------------------

fn putRow(scr: *dsp.Screen, r: usize, row: []const u8, col: u4) void {
    for (0..cols) |c| {
        scr.chars[r][xpos + c] = row[c]; // dispmenu copies menutxt verbatim (ASCII)
        scr.colours[r][xpos + c] = col;
    }
}

fn putText(row: []u8, col: usize, text: []const u8) void {
    for (text, 0..) |ch, i| row[col + i] = ch;
}

/// dispmenu's tail: write the live values into the menu block.
fn fillDynamic(song: *const swm.Song, view: *const dsp.View, b: *[rows][cols]u8) void {
    const drive = dec2(view.devicen); // dispdev
    putText(&b[r_drive], c_drive, &drive);
    const autodir = onOff(view.confbits2 & 1); // disAdir
    putText(&b[r_autodir], c_autodir, &autodir);
    b[r_frspd][c_frspd] = '0' + view.framesp % 10; // disFspd (decdis2's A)
    const ptlen = hex2(song.header[swm.H_DEFLEN]); // defptlen
    putText(&b[r_ptlen], c_ptlen, &ptlen);
    putText(&b[r_theme], c_theme, themeName(view.themeno)); // dThName
    putText(&b[r_keyb], c_keyb, keyType(view.keybtyp)); // disKbTy
    const autoins = onOff(view.confbits & 0x80); // disAins
    putText(&b[r_autoins], c_toggle, &autoins);
    const autofollow = onOff(view.confbits & 0x04); // disFoll
    putText(&b[r_autofollow], c_toggle, &autofollow);
    const rasterbar = onOff(view.confbits & 0x02); // disRbar
    putText(&b[r_rasterbar], c_toggle, &rasterbar);
    const chordnote = onOff(view.confbits & 0x40); // disChNo
    putText(&b[r_chordnote], c_toggle, &chordnote);
    b[r_cfgstat][c_cfgstat] = view.cfgstat;
}

/// dispmenu: paint the menu block at (menuxpos, menuypos) into the 25x40
/// screen. Help mode paints the 20-row help text with the cursor colour only.
/// The host calls this when view.menumode is set (and repaints the editor
/// otherwise, so the asm's clearmenu/$bd erase path is not needed).
pub fn draw(song: *const swm.Song, view: *const dsp.View, scr: *dsp.Screen) void {
    const theme = theme_menu[view.themeno % theme_count];
    if (view.helpmode) {
        for (0..help_rows) |r| putRow(scr, ypos + r, help_text[r], theme.cur);
        return;
    }
    var block: [rows][cols]u8 = undefined;
    for (0..rows) |r| @memcpy(&block[r], menu_text[r]);
    fillDynamic(song, view, &block);
    // menucurpos can be anything after a hand-made View; only the option rows
    // (firstcpos..lastcrpos) highlight.
    const cursor: u8 = if (view.menucurpos >= firstcpos and view.menucurpos <= lastcrpos)
        view.menucurpos
    else
        0xff;
    for (0..rows) |r| {
        const col: u4 = if (r == cursor) theme.cur else theme.bg;
        putRow(scr, ypos + r, &block[r], col);
    }
}

/// RyouSur: the 17x4 "ARE YOU SURE?" box over the menu (rows ypos+9..+12,
/// columns xpos+1..+17). Only drawn while a kill item waits for Y/N.
pub fn drawPrompt(view: *const dsp.View, scr: *dsp.Screen) void {
    if (view.menuprompt == prompt_none) return;
    const top = ypos + rows / 2 - 2; // RyouYpos
    const left = xpos + 1; // RyouXpos
    const col: u4 = 1; // RyouCol
    for (0..17) |i| {
        scr.chars[top][left + i] = '*';
        scr.chars[top + 3][left + i] = '*';
        scr.colours[top][left + i] = col;
        scr.colours[top + 1][left + i] = col;
        scr.colours[top + 2][left + i] = col;
        scr.colours[top + 3][left + i] = col;
    }
    for ("* ARE YOU SURE? *", 0..) |ch, i| scr.chars[top + 1][left + i] = ch; // RyouSurTx (ASCII)
    for ("*  (Y/N) (I/N)  *", 0..) |ch, i| scr.chars[top + 2][left + i] = ch; // RyouSurT2 (ASCII)
}

// -- row editors (menu.menuinc / menu.menudec) -------------------------------

/// IncDriv: device number up, 30 -> 8 (MAXDEVICE/MINDEVICE inclusive).
fn incDrive(view: *dsp.View) void {
    view.devicen = if (view.devicen >= max_device) min_device else view.devicen + 1;
}

/// DecDriv: device number down, 8 -> 30.
fn decDrive(view: *dsp.View) void {
    view.devicen = if (view.devicen >= min_device + 1) view.devicen - 1 else max_device;
}

/// IncPtln: defptlen up, rolling 248 -> 1 when the increment hits maxptnlen.
fn incPtLen(song: *swm.Song) void {
    const n = song.header[swm.H_DEFLEN] +% 1;
    song.header[swm.H_DEFLEN] = if (n == max_ptn_len) min_ptn_len else n;
}

/// DecPtln: defptlen down, rolling 1 -> 249 -> 248.
fn decPtLen(song: *swm.Song) void {
    var n = song.header[swm.H_DEFLEN];
    if (n == min_ptn_len) n = max_ptn_len;
    song.header[swm.H_DEFLEN] = n - 1;
}

/// keyhandler.IncFspd: frame speed up, 8 -> 1.
fn incFramespeed(view: *dsp.View) void {
    view.framesp = if (view.framesp >= pal_max_framesp) 1 else view.framesp + 1;
}

/// KeyLayout: SIDW(0) -> JANK($2c) -> DMC($44) -> SDI($88) -> SIDW.
fn nextKeyLayout(k: u8) u8 {
    if (k & 0x80 != 0) return 0; // SDI (bit7 set)
    if (k == 0) return 0x2c; // SIDW -> Janko
    if (k & 0x40 == 0) return 0x44; // Janko -> DMC
    return 0x88; // DMC (bit6 set) -> SDI
}

/// menu.menuinc: `+`/cursor-right edits the row under the cursor. Returns
/// true when the row has its own editor; false means the caller falls back to
/// pluser.incinst (instrument select).
pub fn inc(song: *swm.Song, view: *dsp.View) bool {
    if (view.menucurpos == drivemenupt) {
        incDrive(view);
        return true;
    }
    if (view.menucurpos == ptlenmenupt) {
        incPtLen(song);
        return true;
    }
    return false;
}

/// menu.menudec: `-`/cursor-left; false means minuser.decinst.
pub fn dec(song: *swm.Song, view: *dsp.View) bool {
    if (view.menucurpos == drivemenupt) {
        decDrive(view);
        return true;
    }
    if (view.menucurpos == ptlenmenupt) {
        decPtLen(song);
        return true;
    }
    return false;
}

// -- row actions (menujmp / runmenup) ----------------------------------------

fn closeMenu(view: *dsp.View) void {
    view.menumode = false;
    view.helpmode = false;
    view.menuprompt = prompt_none;
}

/// retsubt's view reset after CINITUN: subtune 0, unsolo, first instrument,
/// chord and tempo program, copy end signal, undo type cleared, playback
/// orderlist positions back to the top.
fn resetAfterKill(view: *dsp.View) void {
    view.selsubt = 0;
    view.solosta = 0;
    view.copyptn = 0; // copytobuf.copyptn+1 = 0 (no copy in progress)
    view.selinst = 1;
    view.selchor = 1;
    view.seltemp = 1;
    view.undo_type = 0xff;
    for (0..3) |t| view.olstart[t] = 0;
}

/// runmenup: execute view.menupoint (1..18) and clear it. Menu rows that only
/// change editor state leave the menu open, exactly like the asm's mainloop.
pub fn run(song: *swm.Song, view: *dsp.View) Action {
    const point = view.menupoint;
    view.menupoint = 0;
    switch (point) {
        1 => { // savetun
            closeMenu(view); // the file dialog returns through retoedi
            return .save_tune;
        },
        2 => { // loadtun
            closeMenu(view);
            return .load_tune;
        },
        3 => { // saveins
            closeMenu(view);
            return .save_inst;
        },
        4 => { // loadins
            closeMenu(view);
            return .load_inst;
        },
        5 => { // seldriv: RETURN also steps the drive
            incDrive(view);
            return .redraw;
        },
        6 => { // AutoDir: confbits2 bit0
            view.confbits2 ^= 0x01;
            return .redraw;
        },
        7 => { // SetFspd
            incFramespeed(view);
            return .redraw;
        },
        8 => { // SetDefPtLen
            incPtLen(song);
            return .redraw;
        },
        9 => { // initunt: ask first
            view.menuprompt = prompt_tune;
            return .none;
        },
        10 => { // iniinsc: ask first
            view.menuprompt = prompt_inst;
            return .none;
        },
        11 => { // SwitchTheme
            view.themeno = (view.themeno + 1) % theme_count;
            return .redraw;
        },
        12 => { // KeyLayout
            view.keybtyp = nextKeyLayout(view.keybtyp);
            return .redraw;
        },
        13 => { // AutoIns: eorconf $80
            view.confbits ^= 0x80;
            return .redraw;
        },
        14 => { // AutoFollow: eorconf $04
            view.confbits ^= 0x04;
            return .redraw;
        },
        15 => { // RasterBar: eorconf $02
            view.confbits ^= 0x02;
            return .redraw;
        },
        16 => { // ChordNoteMode: eorconf $40
            view.confbits ^= 0x40;
            return .redraw;
        },
        17 => return .save_config, // SaveConfig stays in the menu
        18 => { // Helper: help instead of the menu
            view.helpmode = !view.helpmode;
            return .redraw;
        },
        else => return .none, // dummymp
    }
}

/// YesOrNo's answer: Y (or I) accepts, N (or V) refuses. Both paths return to
/// the editor (the asm's backtoe/retoedi), so the menu always closes.
pub fn resolvePrompt(song: *swm.Song, view: *dsp.View, accept: bool) Action {
    const which = view.menuprompt;
    closeMenu(view);
    if (accept) switch (which) {
        prompt_tune => {
            swm.killTune(song);
            resetAfterKill(view);
        },
        prompt_inst => swm.killInsts(song),
        else => {},
    };
    return .close_redraw;
}

/// SaveConfig's cfgstat cell: '!' when the host's save failed, ' ' otherwise.
pub fn setCfgStat(view: *dsp.View, ok: bool) void {
    view.cfgstat = if (ok) ' ' else '!';
}
