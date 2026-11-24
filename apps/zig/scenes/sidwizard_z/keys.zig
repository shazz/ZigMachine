//! keys.zig — the editor keyboard state machine (Part 3).
//! Port of asm/include/keyhandler.inc + the datawriter/insdelcopy routines it
//! calls: every key the C64 scan delivers runs through one handler and either
//! mutates Song/View or reports a host action through Effect.
//!
//! Key model: the C64 keyboard matrix is scanned column by column
//! (keyhandler.keyer keylp2/keylp1); a pressed key reports code = col*8+row
//! (cols $FE..$7F = 0..7, rows 0..7) and Shift/C= are separate signals
//! (shcbget modkeyc/modkeyr). The keyjmp table routes codes 0..63.
//!
//! No globals, no allocator, no floats: all state lives in swm.Song and
//! dsp.View. See NOTES.md for the Part-3 deviation list.
const std = @import("std");
const swm = @import("swm.zig");
const dsp = @import("display.zig");
const menu = @import("menu.zig");
const filer = @import("filer.zig");

// -- editor constants (settings.cfg 1SID block, COMPILEDAPP=1) ---------------
const max_subt = 7; // maxsubtuneamount: subtune numbers 0..7
const max_ptn = 100; // maxptnamount as Part 1 modelled it (patterns 1..100)
const max_inst = 36; // maxinstamount-1: instruments 1..36
const max_chord = 32; // MAXCHORDAMOUNT (incl. dummy 0)
const max_tempo = 64; // MAXTEMPOPRAMOUNT (incl. dummy 0)
const tempo_len = 0x80; // TempoTableLen
const maxchordlen = 32; // maxchordlength
const maxtempolen = 32; // maxtempolength
const minptnlen = 1; // minptnlen: patterns never shrink below 1 row
const maxrows = 25; // pattern display height (25 rows)
const seqlen = 126; // seqlength: max orderlist bytes before the $FE
const tblwidth = 3; // tblwidth: instrument-table row size (WF/ARP)
const lastinstpt = 117; // lastinstpt: lastbladdr(120) - (101%3) - 1; last row's 1st column
const wftablepos = 16; // WFTABLEPOS: WF/ARP table base in instrument data
const swi_defchord = 8; // SWI_DEFCHORD_POS: default-chord pointer position
const mainstrw = [8]u8{ 3, 1, 5, 7, 4, 2, 6, 8 }; // commonsubs mainstrw
const iswmaxy = [4]u8{ 3, 7, 3, 3 }; // inswmaxy: subwindow Y bounds
const octmuls = [8]u8{ 0, 12, 24, 36, 48, 60, 72, 84 }; // OCTMULS
const pal_max_framesp = 8; // PALmaxframespeed (1SID build)
const ffwdspeed = 4; // ffwdspeed (1SID build): ← fast-forward multiplier
const maxadvancesteps = 25; // maxadvancesteps: paste auto-advance cap
const instnamelength = 8; // instnamelength: instrument-name field size

// note-column FX opcodes (globalconstants.inc)
const vib_fx = 0x60; // VIBRATOFX: vibrato (amplitude in high nybble)
const portam_fx = 0x78; // PORTAMFX: auto-portamento
const syncon_fx = 0x79; // SYNCONFX
const syncoff_fx = 0x7a; // SYNCOFFFX
const ringon_fx = 0x7b; // RINGONFX
const ringoff_fx = 0x7c; // RINGOFFFX
const gate_on = 0x7d; // gateon
const gate_off = 0x7e; // gateoff

// NoteOfY (datawriter.inc): hex-digit key Y -> note value ($80+ = no note).
const note_of_y = [16]u8{
    28, 0, 14, 16, 0x92, 19, 21, 23, 0x9a, 26, 0, 8, 5, 4, 17, 0x86,
};

// keychar (menu.inc): nametype character per key code (screen codes;
// $f5..$fe are control signs: home/insert/backspace/sideways/down/exit).
const keychar = [64]u8{
    0xfd, 0xff,    0xfc,    0xfe, 0xf8,    0xf9,    0xfe,    0xfb,
    51,   23 + 64, 1 + 64,  52,   26 + 64, 19 + 64, 5 + 64,  0xf6,
    53,   18 + 64, 4 + 64,  54,   3 + 64,  6 + 64,  20 + 64, 24 + 64,
    55,   25 + 64, 7 + 64,  56,   2 + 64,  8 + 64,  21 + 64, 22 + 64,
    57,   9 + 64,  10 + 64, 48,   13 + 64, 11 + 64, 15 + 64, 14 + 64,
    43,   16 + 64, 12 + 64, 45,   46,      0x3a,    0x00,    0x2c,
    0xf7, 0,       0x3b,    0xf5, 0xf6,    0x3d,    0xf9,    0x2f,
    49,   0xfe,    0xfa,    50,   32,      0,       17 + 64, 0xfe,
};

// -- keys --------------------------------------------------------------------
/// One keyboard event as keyhandler.keyer/shcbget deliver it: the matrix code
/// plus the Shift/C= signals (the shift keys themselves, codes 15/52/61, are
/// filtered out before keyjmp and never reach the handlers).
pub const Key = struct {
    code: u6, // C64 matrix col*8+row, 0..63
    shift: bool = false,
    cbm: bool = false,
};

// keyjmp order (col*8+row): col 0 = DEL,RET,CR→,F7,F1,F3,F5,CR↓ ...
pub const del = 0; // DEL/INST
pub const ret_ = 1; // RETURN
pub const crsr_r = 2; // cursor right
pub const f7 = 3;
pub const f1 = 4;
pub const f3 = 5;
pub const f5 = 6;
pub const crsr_d = 7; // cursor down
pub const k3 = 8;
pub const w_ = 9;
pub const a_ = 10;
pub const k4 = 11;
pub const z_ = 12;
pub const s_ = 13;
pub const e_ = 14;
pub const k5 = 16;
pub const r_ = 17;
pub const d_ = 18;
pub const k6 = 19;
pub const c_ = 20;
pub const f_ = 21;
pub const t_ = 22;
pub const x_ = 23;
pub const k7 = 24;
pub const y_ = 25;
pub const g_ = 26;
pub const k8 = 27;
pub const b_ = 28;
pub const h_ = 29;
pub const u_ = 30;
pub const v_ = 31;
pub const k9 = 32;
pub const i_ = 33;
pub const j_ = 34;
pub const k0 = 35;
pub const m_ = 36;
pub const k_ = 37;
pub const o_ = 38;
pub const n_ = 39;
pub const plus = 40;
pub const p_ = 41;
pub const l_ = 42;
pub const minus = 43;
pub const dot = 44;
pub const colon = 45;
pub const at_ = 46;
pub const comma = 47;
pub const pound = 48; // £ (INSERT on PC)
pub const star = 49;
pub const semic = 50;
pub const home = 51;
pub const equal_ = 53;
pub const uparr = 54; // ↑ (page-down on PC)
pub const slash = 55; // / (page-up)
pub const k1 = 56;
pub const backarrow = 57; // ← fast-forward
pub const ctrl = 58; // TAB
pub const k2 = 59;
pub const space = 60;
pub const q_ = 62;
pub const stop = 63; // RUN/STOP (ESC)

/// What the host should do after handle() (keyhandler runs inside the editor
/// main loop; play actions go through playadapter, dialogs through Part 4).
/// Which file a host dialog should handle (menu.inc savetun/loadtun/saveins/
/// loadins/SaveConfig; the extensions are .SWM, .SWI and the config file).
pub const FileKind = enum { tune, instrument, config };

pub const Effect = union(enum) {
    none, // pure Song/View state change; host just redraws
    redraw, // force a display refresh (insrefr/hilrefr/msorefr style)
    play_song: bool, // F1: play whole tune from beginning (payload: follow)
    play_markers: bool, // shift+F1: play from orderlist markers
    play_pattern: bool, // F3 / shift+SPACE: play pattern(s) from cursor
    stop_or_cont, // shift+F3, RUN/STOP: pause playback, or continue if paused
    fastfwd: u8, // ←: play this many times faster (0 cancels)
    menu, // shift+F7: open the menu (Part 4)
    need_listing, // filer: host reads the directory, then calls filerListing()
    load_file: FileRef, // filer: host reads the bytes and calls swm.load + filerResult()
    save_file: FileRef, // filer: host writes the bytes and calls filerResult()
    close_filer, // STOP/ESC in the filer: back to the editor, no file operation
    load_dialog: FileKind, // kept for hosts that drive the dialog themselves
    save_dialog: FileKind, // kept for hosts that drive the dialog themselves
    quit, // menu item (Part 4)
    nametype, // cbm+N: enter name-typing mode; host feeds keys to handle()
};

/// A file the dialog registered (regname): the tune/instrument/config kind and
/// the name with its extension (.SWM/.SWI/.CFG) already appended.
pub const FileRef = struct {
    kind: FileKind,
    name: filer.Name,
};

// -- small clamps (display.zig keeps its own private copies) ------------------
fn clampPtn(n: u8) u8 {
    return if (n == 0 or n > max_ptn) 1 else n;
}

fn clampRow(n: u8) u8 {
    return @min(n, maxrows - 1);
}

fn clampTrack(n: u8) u8 {
    return @min(n, 2);
}

fn clampSubt(n: u8) u8 {
    return @min(n, max_subt);
}

fn clampInst(n: u8) u8 {
    return if (n == 0) 1 else @min(n, max_inst);
}

// -- pattern memory addressing (setptnptr/getcurnote/compcur) ------------------
/// The dummy pattern 0's read-only body (editor.asm PTN0: $00,$FF).
const ptn0_body = [2]u8{ 0, swm.ptn_end };

/// A pattern's memory as the reader routines see it (PPTRLO/HI).
fn ptnBase(song: *const swm.Song, ptn: u8) []const u8 {
    return if (ptn == 0) &ptn0_body else &song.pats[ptn - 1];
}

/// ptnMpos: byte index of the display window's top row (setrpos walk).
fn ptnMpos(song: *const swm.Song, view: *const dsp.View, t: usize) u8 {
    const ptn = view.curptn1[clampTrack(@intCast(t))];
    return dsp.walkPtn(ptnBase(song, clampPtn(ptn)), view.prowpos[clampTrack(@intCast(t))]);
}

/// ptncurs: byte index of the cursor row relative to the display top
/// (displayer1 rowdlop store). Absolute index = ptnMpos + ptncurs.
fn ptnCur(song: *const swm.Song, view: *const dsp.View, t: usize) u8 {
    const ptn = view.curptn1[clampTrack(@intCast(t))];
    const base = ptnBase(song, clampPtn(ptn));
    const mpos = dsp.walkPtn(base, view.prowpos[clampTrack(@intCast(t))]);
    const row = clampRow(view.subwpos3[0]);
    return dsp.walkPtn(base, view.prowpos[clampTrack(@intCast(t))] +% row) -% mpos;
}

/// compcur: A=prowpos+subwpos3 with 16-bit compare against ptnlength;
/// returns the absolute row of the cursor and whether it is inside the
/// pattern (carry clear in the asm).
fn compcur(song: *const swm.Song, view: *const dsp.View) struct { row: u8, inside: bool } {
    const t = clampTrack(view.subwpos1[0]);
    const ptn = clampPtn(view.curptn1[t]);
    const sum = view.prowpos[t] +% view.subwpos3[0];
    if (@addWithOverflow(view.prowpos[t], view.subwpos3[0])[1] != 0) {
        return .{ .row = sum, .inside = false }; // 16-bit carry: past the end
    }
    return .{ .row = sum, .inside = sum < song.ptn_len[ptn] };
}

/// getcurnote: the byte at the cursor's row (note column).
fn curNote(song: *const swm.Song, view: *const dsp.View, t: usize) u8 {
    const ptn = clampPtn(view.curptn1[t]);
    const base = ptnBase(song, ptn);
    return base[ptnCur(song, view, t) +% ptnMpos(song, view, t)];
}

/// instpt2 for the pattern under the cursor: writes need a mutable slice, so
/// pattern-0 protection (deviation: the asm would corrupt PTN0) is upfront.
fn ptnMut(song: *swm.Song, view: *const dsp.View, t: usize) ?[]u8 {
    const ptn = clampPtn(view.curptn1[t]);
    if (ptn == 0) return null; // pattern 0 is read-only (see NOTES.md)
    return &song.pats[ptn - 1];
}

// -- hex-digit merging (commonsubs writehex1/writehex2) -----------------------
/// writehex1 (commonsubs): merge the typed digit into the HIGH nybble.
fn writeHex1(val: u8, digit: u8) u8 {
    return ((digit & 0x0f) << 4) | (val & 0x0f);
}

/// writehex2 (commonsubs): merge the typed digit into the LOW nybble.
fn writeHex2(val: u8, digit: u8) u8 {
    return (val & 0xf0) | (digit & 0x0f);
}

// -- orderlist addressing (setseqptr/seqaddb/getcurptn) -----------------------
/// Current orderlist slot: subtune*3 + track (getsubaddr/setsep2).
fn seqIndex(view: *const dsp.View) usize {
    const s: usize = clampSubt(view.selsubt);
    const t: usize = clampTrack(view.subwpos1[1]);
    return s * 3 + t;
}

/// getcurptn: byte index under the orderlist cursor (col/2 + seqdpos).
fn seqByte(view: *const dsp.View) u8 {
    return (view.subwpos2[1] >> 1) +% view.seqposdisp;
}

/// The orderlist bytes as setseqptr/seqaddb see them.
fn seqOf(song: *swm.Song, view: *const dsp.View) *[swm.seq_bound]u8 {
    return &song.seqs[seqIndex(view)];
}

/// Recompute the stored sequence length after a mutation (decoseq scan).
fn rescanSeq(song: *swm.Song, si: usize) void {
    song.seq_len[si] = @intCast(swm.scanSeq(&song.seqs[si]));
}

// -- pattern insert/delete (insdelcopy.inc) -----------------------------------
/// insertpt: shift the pattern tail forward by `y_in` bytes starting after
/// position `x` (x is display-relative, as every caller passes it); zeroval=1
/// (bigFX) inserts one extra zero byte. Returns the shift applied, $ff when
/// the pattern is full (asm contract: callers branch on Y=$ff).
/// Semantics (verbatim): base[x+1]=0, base[x+2]=0 for bigFX, then y-1 bytes
/// of $80 filled downward from x (NOP placeholders inside a row).
fn insertPt(song: *swm.Song, view: *const dsp.View, base: []u8, x: u8, y_in: u8, zeroval: u8) u8 {
    const t = clampTrack(view.subwpos1[0]);
    const ptn = clampPtn(view.curptn1[t]);
    var y: u8 = y_in;
    if (zeroval == 1) y +%= 1; // bigFX needs one more byte
    const size = song.ptn_size[ptn];
    if (size >= swm.ptn_len_max + 2) return 0xff; // cmp #maxptnlen+2
    const sum = @addWithOverflow(size, y);
    if (sum[1] != 0) return 0xff; // carry: would run past $ff
    song.ptn_size[ptn] = sum[0];
    const mpos = ptnMpos(song, view, t);
    // movpfwd: move the tail (incl. the stray byte past the endmark) forward;
    // x and the end are relative to ptnMpos (pattpt1/ptnzptr addressing).
    const end_rel = sum[0] -% mpos;
    var i: usize = end_rel;
    while (true) {
        const src = mpos + i;
        const dst = mpos + i + y;
        if (src < base.len and dst < base.len) base[dst] = base[src];
        if (i <= x) break;
        i -= 1;
    }
    // zero out the new places, then fill $80 placeholders downward
    var k: usize = x;
    if (mpos + k + 1 < base.len) base[mpos + k + 1] = 0;
    if (zeroval == 1) {
        if (mpos + k + 2 < base.len) base[mpos + k + 2] = 0;
    }
    var n: u8 = y_in -% 1; // fill count: the asm patches insamo2 with the
    // ORIGINAL Y (before the bigfx +1) - one $80 per extra byte below [x]
    while (n > 0) : (n -= 1) {
        if (mpos + k < base.len) base[mpos + k] = 0x80;
        k -%= 1;
    }
    return y;
}

/// delbackpt: delete `y` bytes at display-relative position `x`, moving the
/// rest back. Borrow (y > ptnsize) = no-op (asm xstode2 branch). The copy
/// length is lenstor = (newsize - mpos) + y (ystode3 is patched with the
/// delete amount AFTER the clc - it covers the stray byte past the old
/// endmarker); the loop runs with u8 wrap while dst != lenstor.
fn delBackPt(song: *swm.Song, view: *const dsp.View, base: []u8, x: u8, y: u8) void {
    const t = clampTrack(view.subwpos1[0]);
    const ptn = clampPtn(view.curptn1[t]);
    const size = song.ptn_size[ptn];
    if (y > size) return; // sec/sbc borrow: no process
    const newsize = size -% y;
    song.ptn_size[ptn] = newsize;
    const mpos = ptnMpos(song, view, t);
    const lenstor = newsize -% mpos +% y; // u8 (asm wraps)
    var d: u8 = x; // dst-relative position
    while (d != lenstor) : (d +%= 1) {
        const dst: usize = mpos +% d;
        const src: usize = mpos +% d +% y;
        if (dst < base.len and src < base.len) base[dst] = base[src];
    }
}

/// getdelamount: rows occupy 1..4 bytes (note / +inst / +fx / +fxvalue),
/// exactly dsp.rowSize. The fxvalue only exists for smallFX.
fn rowLenAt(base: []const u8, i: usize) u8 {
    return @intCast(dsp.rowSize(base, i));
}

/// SaveUndo (single level, deviation: the asm only snapshots on the first
/// press of a key repeat; we always save before a mutation).
fn saveUndo(song: *swm.Song, view: *dsp.View) void {
    view.undo_type = view.curwind;
    switch (view.curwind) {
        0 => { // SavPatU: whole pattern memory incl. the endmark
            const t = clampTrack(view.subwpos1[0]);
            const ptn = clampPtn(view.curptn1[t]);
            view.undo_item = ptn;
            view.undo_len = song.ptn_len[ptn];
            view.undo_size = song.ptn_size[ptn];
            @memcpy(view.undo_buf[0 .. @as(usize, song.ptn_size[ptn]) + 1], song.pats[ptn - 1][0 .. @as(usize, song.ptn_size[ptn]) + 1]);
        },
        1 => { // SavSeqU: 127 bytes of the current orderlist
            const si = seqIndex(view);
            view.undo_item = @intCast(si);
            @memcpy(view.undo_buf[0..127], song.seqs[si][0..127]);
        },
        2 => { // SavInsU: the whole instrument slot
            const inst = clampInst(view.selinst);
            view.undo_item = inst;
            @memcpy(view.undo_buf[0..swm.inst_size], song.insts[inst][0..swm.inst_size]);
        },
        else => view.undo_type = 0xff, // windows 3/4 save nothing
    }
}

/// Undo: restore the snapshot (Undo procedure).
fn doUndo(song: *swm.Song, view: *dsp.View) void {
    switch (view.undo_type) {
        0 => { // UndoPat
            if (view.followp) return; // endUndo guard
            const ptn = clampPtn(view.undo_item);
            const n: usize = @as(usize, view.undo_size) + 1;
            song.ptn_len[ptn] = view.undo_len;
            song.ptn_size[ptn] = view.undo_size;
            @memcpy(song.pats[ptn - 1][0..n], view.undo_buf[0..n]);
            view.curwind = 0;
            chkcury(song, view);
        },
        1 => { // orderlist: copy the 127 bytes back, re-scan, sseqend
            const si: usize = view.undo_item;
            if (si >= swm.seq_slots) return;
            @memcpy(song.seqs[si][0..127], view.undo_buf[0..127]);
            rescanSeq(song, si);
            _ = sseqend(song, view);
        },
        2 => { // UndoIns
            const inst = clampInst(view.undo_item);
            @memcpy(song.insts[inst][0..swm.inst_size], view.undo_buf[0..swm.inst_size]);
            instInit(view);
        },
        else => {},
    }
}

/// commonsubs.instinit: zero the instrument cursor/scroll positions at
/// instrument switch (the play-runtime resetJamIns part is host-side).
fn instInit(view: *dsp.View) void {
    for (0..4) |w| {
        view.inswXbuf[w] = 0;
        view.inswYbuf[w] = 0;
    }
    view.wfarpos = 0;
}

/// chkcury: keep the cursor inside the pattern after scroll/pattern changes.
fn chkcury(song: *const swm.Song, view: *dsp.View) void {
    const cc = compcur(song, view);
    if (cc.inside) return;
    const t = clampTrack(view.subwpos1[0]);
    const ptn = clampPtn(view.curptn1[t]);
    const len = song.ptn_len[ptn];
    const sub = len -% view.prowpos[t]; // sbc prowpos
    if (sub >= 0x80) { // borrow in the asm (bcs + / lda 0)
        view.prowpos[t] = len;
        view.subwpos3[0] = 0;
        return;
    }
    view.subwpos3[0] = sub;
}

// -- note/value entry (datawriter.inc) ---------------------------------------
/// commonsubs.jamming: note below $60 becomes the jammed note.
fn jamming(view: *dsp.View, note: u8) void {
    if (note <= swm.note_max) view.jamnote = note;
}

/// commonsubs.calcoct: add the selected octave*12 to the note; false when
/// the result leaves the note range (asm: cmp SWM_NOTE_MAX+1, bpl).
fn calcoct(view: *const dsp.View, note: u8) ?u8 {
    var a: u8 = note;
    var o: u8 = view.octave;
    while (o > 0) : (o -= 1) a +%= 12; // OCTMULS walk (asm loops)
    if (a > swm.note_max) return null; // cmp #$60
    return a;
}

/// datawriter.noterep/notewri: type a note (X) into the pattern's note column.
/// Also handles vibrato-amplitude editing and confbits auto-append/autoadvance.
fn noteEntry(song: *swm.Song, view: *dsp.View, note_in: u8) Effect {
    if (view.followp) return .none; // endnotw guard
    const t = clampTrack(view.subwpos1[0]);
    const base = ptnMut(song, view, t) orelse return .none;
    saveUndo(song, view);
    const note_pos = ptnCur(song, view, t);
    const old = curNote(song, view, t);
    if (old & 0x70 == vib_fx) { // vibrato: digit edits the amplitude
        var v: u8 = old;
        if (note_in == 0) v = old & 0x80; // 0 deletes the vibrato
        base[note_pos] = writeHex2(v, note_in);
        return .none;
    }
    if (note_in == 0) {
        base[note_pos] = old & 0x80;
        return .none;
    } // NOP
    if (note_in >= 0x80) return .none; // no note for this key
    if (note_in > swm.note_max) {
        base[note_pos] = (old & 0x80) | note_in;
    } else {
        const n = calcoct(view, note_in) orelse return .none; // octave cap
        base[note_pos] = (old & 0x80) | n;
    }
    return autoIns(song, view, base, note_pos, t);
}

/// datawriter.autoins: append the selected instrument after the typed note
/// (confbits bit7) and run Config.autoadv godownp steps.
fn autoIns(song: *swm.Song, view: *dsp.View, base: []u8, note_pos: u8, t: usize) Effect {
    _ = t; // (kept for call-site symmetry; the asm re-derives the track)
    const note = base[note_pos] & 0x7f;
    if (note == 0 or note > swm.note_max) return .none;
    if (view.confbits & 0x80 == 0) return .none; // auto-append off
    if (base[note_pos] & 0x80 == 0) { // no instrument column yet: make one
        const y = insertPt(song, view, base, note_pos, 1, 0);
        if (y == 0xff) return .none;
        base[note_pos] |= 0x80;
    }
    const ins_pos = note_pos + 1;
    base[ins_pos] = (base[ins_pos] & 0x80) | clampInst(view.selinst);
    return autoAdvDown(song, view);
}

/// noteadv: Config.autoadv godownp repetitions (uncapped for note entry; the
/// maxadvancesteps cap belongs to the paste routine only).
fn autoAdvDown(song: *swm.Song, view: *dsp.View) Effect {
    var n: u8 = view.autoadv;
    while (n > 0) : (n -= 1) godownp(song, view);
    return .none;
}

/// datawriter.notecol: entry for the musical keys (W/Q/R/S/...). Outside the
/// pattern's note column (or in jam mode) the key jams instead of typing.
fn notecol(song: *swm.Song, view: *dsp.View, note: u8) Effect {
    if (view.curwind == 3) { // chkchdn: chord table note-mode
        if (view.confbits & 0x40 == 0) {
            jamming(view, note);
            return .none;
        }
        if (view.followp) return .none;
        chordNoteEntry(song, view, note);
        return .none;
    }
    if (view.curwind != 0) {
        jamming(view, note);
        return .none;
    }
    if (view.subwpos2[0] != 0) {
        jamming(view, note);
        return .none;
    }
    if (view.jammode) {
        jamming(view, note);
        return .none;
    }
    jamming(view, note); // noterep jams the raw note even at the endmark
    const cc = compcur(song, view);
    if (!cc.inside) return .none;
    return noteEntry(song, view, note);
}

// -- cursor-advance helpers (keyhandler ptncuri/inswiri/chtmrig) ---------------
/// ptncuri: one column right in the pattern window; at the last column of
/// track 2 it switches to the instrument window instead (SID_AMOUNT==1).
fn ptnCurRight(song: *swm.Song, view: *dsp.View) Effect {
    if (view.subwpos2[0] != 6) {
        view.subwpos2[0] += 1;
        return .none;
    }
    view.subwpos2[0] = 0;
    if (view.subwpos1[0] < 2) {
        tabPtnFwd(song, view);
        return .none;
    }
    view.curwind = 2; // f7er.setInsW
    return .none;
}

/// inswiri: one column right in the instrument window; the last column of a
/// table subwindow switches to the chord (w 1/2, via swtochd+chdzero) or
/// tempo (w 3, via swtotmp) window.
fn inswiri(view: *dsp.View) Effect {
    const w = @min(view.subwpos1[2], 3);
    if (view.inswXbuf[w] != 5) {
        view.inswXbuf[w] += 1;
        return .none;
    }
    if (w == 0) return .none; // main window: stay at column 5
    if (w == 3) { // f7er.swtotmp
        view.curwind = 4;
        return .none;
    }
    // f5er.swtochd: remember the window and reset chord cursor + scroll
    view.prevwin = view.curwind;
    view.curwind = 3;
    view.subwpos1[3] = 0;
    view.chorpos = 0;
    return .none;
}

/// chtmrig: one column right in the chord/tempo window (2 digits per cell).
fn chtmrig(view: *dsp.View) Effect {
    const x = @min(view.curwind, 4);
    if (view.subwpos2[x] != 1) view.subwpos2[x] += 1;
    return .none;
}

/// tabptfw/tabptbk (SID_AMOUNT==1): rotate track 0..2, then chkcury.
fn tabPtnFwd(song: *swm.Song, view: *dsp.View) void {
    view.subwpos1[0] = if (view.subwpos1[0] >= 2) 0 else view.subwpos1[0] + 1;
    chkcury(song, view);
}

fn tabPtnBack(song: *swm.Song, view: *dsp.View) void {
    view.subwpos1[0] = if (view.subwpos1[0] == 0) 2 else view.subwpos1[0] - 1;
    chkcury(song, view);
}

// -- pattern reader/writer under the cursor (instpt1/instpt2 with setptnptr) --
const PCtx = struct {
    base: []u8,
    mpos: u8, // ptnMpos: byte index of the display top row
    x: u8, // ptncurs: cursor row relative to mpos
    ptn: u8,
};

fn pctx(song: *swm.Song, view: *const dsp.View) ?PCtx {
    const t = clampTrack(view.subwpos1[0]);
    const ptn = clampPtn(view.curptn1[t]);
    if (ptn == 0) return null; // pattern 0 read-only (NOTES.md)
    return .{
        .base = &song.pats[ptn - 1],
        .mpos = ptnMpos(song, view, t),
        .x = ptnCur(song, view, t),
        .ptn = ptn,
    };
}

fn rdP(c: PCtx, off: u8) u8 {
    const i = @as(usize, c.mpos) + off;
    if (i >= c.base.len) return swm.ptn_end;
    return c.base[i];
}

fn wrP(c: PCtx, off: u8, v: u8) void {
    const i = @as(usize, c.mpos) + off;
    if (i < c.base.len) c.base[i] = v;
}

/// chptful: carry=1 (full) if ptnsize reached maxptnlen (4-byte rows possible).
fn ptnFull(song: *const swm.Song, ptn: u8) bool {
    return song.ptn_size[ptn] >= swm.ptn_len_max;
}

// -- datawriter.isincol: hex typing into instrument/fx columns -----------------
fn isincol(song: *swm.Song, view: *dsp.View, digit: u8) Effect {
    if (view.followp) return .none;
    const c = pctx(song, view) orelse return .none;
    saveUndo(song, view);
    const col = view.subwpos2[0];
    if (col == 1) return instLeft(song, view, c, digit);
    if (col == 2) return instRight(song, view, c, digit);
    if (col == 3) return fxLeft(song, view, c, digit);
    if (col == 4) return fxRight(song, view, c, digit);
    return fxValue(song, view, c, digit);
}

/// insapp1 (col 1): type the high digit of the instrument number.
fn instLeft(song: *swm.Song, view: *dsp.View, c: PCtx, digit: u8) Effect {
    if (digit >= 8) return .none; // cpy #8; bpl noptnwr
    const note = rdP(c, c.x);
    if (note & 0x80 == 0) { // no instrument column yet
        if (digit == 0) return ptnCurRight(song, view); // justadv
        if (insertPt(song, view, c.base, c.x, 1, 0) == 0xff) return .none;
        wrP(c, c.x, note | 0x80);
    }
    const xi = c.x +% 1;
    const newv = writeHex1(rdP(c, xi), digit);
    if (rdP(c, xi) & 0x80 != 0) {
        wrP(c, xi, newv | 0x80); // keep the fx-marker bit
    } else if (newv != 0) {
        wrP(c, xi, newv);
    } else { // typed 00: delete the instrument column (delinst)
        delBackPt(song, view, c.base, xi, 1);
        wrP(c, c.x, rdP(c, c.x) & 0x7f);
    }
    return ptnCurRight(song, view); // justadv
}

/// insapp2 (col 2): the low digit; no cursor advance afterwards (the asm's
/// jmp instpt2/rts stack-trick returns straight to the main loop).
fn instRight(song: *swm.Song, view: *dsp.View, c: PCtx, digit: u8) Effect {
    const note = rdP(c, c.x);
    if (note & 0x80 == 0) { // notebit7: sign the note + make room
        if (digit == 0) return .none;
        if (insertPt(song, view, c.base, c.x, 1, 0) == 0xff) return .none;
        wrP(c, c.x, note | 0x80);
    }
    const xi = c.x +% 1;
    const newv = writeHex2(rdP(c, xi), digit);
    if (newv != 0) {
        wrP(c, xi, newv);
    } else { // typed 00: delete the column (falls into delinst)
        delBackPt(song, view, c.base, xi, 1);
        wrP(c, c.x, rdP(c, c.x) & 0x7f);
    }
    return .none;
}

/// checkinsert: ensure the fx column exists; returns how many bytes still
/// have to be inserted (asm Y: 0 = exists, 1 = +inst, 2 = +inst+fx, $ff = no).
const FxNeed = enum { exists, need_inst, need_inst_fx, refuse };

fn checkinsert(song: *swm.Song, view: *const dsp.View, c: PCtx, digit: u8) FxNeed {
    _ = view;
    const note = rdP(c, c.x);
    if (note & 0x80 == 0) { // no instrument column: need inst + fx
        if (ptnFull(song, c.ptn) or digit == 0) return .refuse;
        wrP(c, c.x, note | 0x80);
        return .need_inst_fx;
    }
    const inst = rdP(c, c.x +% 1);
    if (inst & 0x80 == 0) { // instrument column exists, no fx: need fx
        if (ptnFull(song, c.ptn) or digit == 0) return .refuse;
        wrP(c, c.x +% 1, inst | 0x80);
        return .need_inst;
    }
    return .exists;
}

/// decideval (common part): a new fx needs a value byte when digit <= 1.
fn fxNeedsValue(digit: u8) bool {
    return digit <= 1;
}

/// fxtypwr (col 3): the high digit of the fx type.
fn fxLeft(song: *swm.Song, view: *dsp.View, c: PCtx, digit: u8) Effect {
    const ci = checkinsert(song, view, c, digit);
    if (ci == .refuse) return ptnCurRight(song, view); // justadv
    const xi = c.x +% 1;
    if (ci != .exists) {
        const need: u8 = if (ci == .need_inst_fx) 2 else 1;
        if (insertPt(song, view, c.base, xi, need, @intFromBool(fxNeedsValue(digit))) == 0xff) {
            return .none;
        }
        return fxCommon(song, view, c, xi +% 1, digit); // decided: inx
    }
    // fx column existed: form conversion around the typed digit (smallfx/bigfx)
    const xf = xi +% 1;
    const oldfx = rdP(c, xf);
    if (oldfx & 0xe0 != 0) { // smallfx (no value byte): digit <= 1 converts to bigfx
        const merged = writeHex1(oldfx, digit);
        if (digit < 2 and merged != 0) { // zeroing is handled by freemem instead
            if (insertPt(song, view, c.base, xf, 1, 0) == 0xff) return .none;
        }
    } else if (digit >= 2) { // bigfx: digit >= 2 drops the value byte
        delBackPt(song, view, c.base, xf +% 1, 1);
    }
    return fxCommon(song, view, c, xf, digit);
}

/// decide2/freemem: write the merged digit; on zero, free the fx bytes. The
/// delete amount comes from the OLD fx byte (asm loads Y=1/2 before the form
/// conversions: 2 when the fx carries a value byte, 1 otherwise).
fn fxCommon(song: *swm.Song, view: *dsp.View, c: PCtx, xf: u8, digit: u8) Effect {
    const oldfx = rdP(c, xf);
    const newv = writeHex1(oldfx, digit);
    if (newv != 0) {
        wrP(c, xf, newv);
        return ptnCurRight(song, view);
    }
    // freemem: fx zeroed out - delete fx (+value, +inst if inst==0)
    var y: u8 = if (oldfx & 0xe0 == 0) 2 else 1;
    const inst = rdP(c, xf -% 1);
    if (inst & 0x7f == 0) {
        wrP(c, xf -% 2, rdP(c, xf -% 2) & 0x7f); // clear the note marker
        y += 1;
        delBackPt(song, view, c.base, xf -% 1, y);
    } else {
        wrP(c, xf -% 1, inst & 0x7f); // switch off the inst marker bit
        delBackPt(song, view, c.base, xf, y);
    }
    return ptnCurRight(song, view);
}

/// fxtywri (col 4): the low digit of the fx type.
fn fxRight(song: *swm.Song, view: *dsp.View, c: PCtx, digit: u8) Effect {
    const ci = checkinsert(song, view, c, digit);
    if (ci == .refuse) return ptnCurRight(song, view);
    const xi = c.x +% 1;
    if (ci != .exists) {
        const need: u8 = if (ci == .need_inst_fx) 2 else 1;
        if (insertPt(song, view, c.base, xi, need, @intFromBool(fxNeedsValue(digit))) == 0xff) {
            return .none;
        }
        wrP(c, xi +% 1, writeHex2(0, digit));
        return fxRightAdv(song, view, c, xi +% 1);
    }
    const xf = xi +% 1;
    const newv = writeHex2(rdP(c, xf), digit);
    if (newv != 0) {
        wrP(c, xf, newv);
        return fxRightAdv(song, view, c, xf);
    }
    // typed 00: delete fx column (+ value byte if one follows)
    const y: u8 = if (rdP(c, xf) & 0xe0 == 0) 2 else 1;
    fxZeroOut(song, view, c, xf, y);
    return .none;
}

fn fxRightAdv(song: *swm.Song, view: *dsp.View, c: PCtx, xf: u8) Effect {
    if (rdP(c, xf) & 0xe0 != 0) return .none; // no value byte: no advance
    return ptnCurRight(song, view);
}

/// freemem shared by the col-4 zero path.
fn fxZeroOut(song: *swm.Song, view: *dsp.View, c: PCtx, xf: u8, y: u8) void {
    const inst = rdP(c, xf -% 1);
    if (inst & 0x7f == 0) {
        wrP(c, xf -% 2, rdP(c, xf -% 2) & 0x7f);
        delBackPt(song, view, c.base, xf -% 1, y + 1);
    } else {
        wrP(c, xf -% 1, inst & 0x7f);
        delBackPt(song, view, c.base, xf, y);
    }
}

/// fxvawri (col 5/6): the bigfx value digits (only exists for fx & $e0 == 0).
fn fxValue(song: *swm.Song, view: *dsp.View, c: PCtx, digit: u8) Effect {
    if (rdP(c, c.x) & 0x80 == 0) return .none; // no instrument column
    if (rdP(c, c.x +% 1) & 0x80 == 0) return .none; // no fx column
    const xf = c.x +% 2;
    if (rdP(c, xf) & 0xe0 != 0) return .none; // not a value-carrying fx
    const xv = xf +% 1;
    const col = view.subwpos2[0];
    if (col == 5) {
        wrP(c, xv, writeHex1(rdP(c, xv), digit));
        return ptnCurRight(song, view);
    }
    wrP(c, xv, writeHex2(rdP(c, xv), digit));
    return .none;
}

// -- writevalue: the hex-digit dispatcher (datawriter.inc) ---------------------
/// writevalue: a hex digit (0..15) typed with no Shift/C=. X = NoteOfY[digit]
/// is stashed for the chord note-writer (chkptnw.notsto2), then the window
/// dispatch happens (chkptnw -> ptnwrit / wrordli).
fn writevalue(song: *swm.Song, view: *dsp.View, digit: u8) Effect {
    // NoteOfY lookup + the per-key fixups (datawriter.inc): the asm edits X
    // after the table read, so key A types C (1), key D types E (5), key E
    // types D# (4) and key F types F (6) - verbatim quirk, see NOTES.md.
    const note = switch (digit) {
        0x0a => 1, // cpy #$A; inx
        0x0d => 5, // cpy #$D; inx
        0x0e => 4, // cpy #$E; ldx #$04
        0x0f => 6, // cpy #$F; ldx #$06
        else => note_of_y[digit],
    };
    if (view.curwind != 0) return wrordli(song, view, digit);
    if (view.subwpos2[0] != 0) return isincol(song, view, digit);
    if (view.jammode) { // hex digits jam in jam mode (ptnwrit's note-column gate)
        jamming(view, note);
        return .none;
    }
    return noteEntry(song, view, note);
}

// -- wrordli: orderlist hex typing (datawriter.inc) ----------------------------
fn wrordli(song: *swm.Song, view: *dsp.View, digit: u8) Effect {
    if (view.curwind != 1) return chwrinw(song, view, digit);
    saveUndo(song, view);
    const seq = seqOf(song, view);
    const idx = @as(usize, seqByte(view));
    const prev: u8 = if (idx == 0) 0 else seq[idx - 1]; // asm wraps to seq[$ff..]
    const even = view.subwpos2[1] & 1 == 0;
    if (prev == swm.seq_end_loop) { // typing into a loop-jump address
        const old = seq[idx];
        const newv = if (even) writeHex1(old, digit) else writeHex2(old, digit);
        if (newv < 0x80) {
            // jump target must stay inside the sequence (before the $ff)
            // even refuse: notwri1 still advances; odd refuse: notwrid stops
            if (newv >= idx - 1) return if (even) seqStepR(song, view, true) else .none;
        } else if (newv > max_subt + 0x80) {
            return wrordStore(song, view, seq, idx, max_subt + 0x80, even);
        }
        return wrordStore(song, view, seq, idx, newv, even);
    }
    if (prev == swm.seq_end_stop) return .none; // lal2/lal3: no write after $fe
    const cur = seq[idx];
    if (cur == 0) return .none; // pattern 00 is protected
    if (cur >= 0xfe) { // endmarker under cursor
        const newv = if (even) writeHex1(cur, digit) else writeHex2(cur, digit);
        if (newv < 0xfe) return .none; // chkfeff refuse / notwrid
        if (!even and newv == 0xfe and idx + 1 < seq.len) { // chbfeff: clear jump addr
            seq[idx] = newv;
            seq[idx + 1] = 0;
            rescanSeq(song, seqIndex(view));
            return .none; // no advance, no valuecont (jmp seqaddc trick)
        }
        return wrordStore(song, view, seq, idx, newv, even);
    }
    var newv = if (even) writeHex1(cur, digit) else writeHex2(cur, digit);
    if (newv == 0) newv = 1; // pattern numbers can't be 0
    if (newv >= 0x80) { // orderlist-fx/transpose range: $fe/$ff stay untypable
        if (newv >= 0xfe) return if (even) seqStepR(song, view, true) else .none;
    } else if (newv > max_ptn) { // plain numbers: cap at 100
        newv = max_ptn;
    }
    return wrordStore(song, view, seq, idx, newv, even);
}

/// wroldat/wrolda2: store the merged byte. Even digits always advance one
/// column (wroldat falls through into notwri1); odd digits advance only when
/// Config.autoadv is set (wrolda2 checks it before seqstpr2).
fn wrordStore(song: *swm.Song, view: *dsp.View, seq: *[swm.seq_bound]u8, idx: usize, v: u8, even: bool) Effect {
    seq[idx] = v;
    view.valuecont +%= 1; // continuous typing across scrolling
    if (!even and view.autoadv == 0) return .none;
    return seqStepR(song, view, even);
}

/// seqstpr1/seqstpr2 + noseqend: advance the orderlist cursor one digit right,
/// refusing to step onto/over an endmarker. The guard loop reads seq[y0] and
/// seq[y0-1] (y0 = idx-1 for even/seqstpr1, idx for odd/seqstpr2): $fe in
/// either blocks, and a $ff at seq[y0-1] (cursor sits behind a jump command)
/// blocks as well.
fn seqStepR(song: *swm.Song, view: *dsp.View, even: bool) Effect {
    const seq = seqOf(song, view);
    const idx = @as(usize, seqByte(view));
    const y0: usize = if (even) idx -% 1 else idx;
    if (seq[y0 & (swm.seq_bound - 1)] == swm.seq_end_stop) return .none;
    const y1 = (y0 -% 1) & (swm.seq_bound - 1);
    if (seq[y1] == swm.seq_end_stop or seq[y1] == swm.seq_end_loop) return .none;
    return seqAdv(view);
}

/// noseqend: inc column; at the right edge scroll and (while typing) park the
/// cursor at column 38 for continuous entry.
fn seqAdv(view: *dsp.View) Effect {
    if (view.subwpos2[1] != 39) {
        view.subwpos2[1] += 1;
        return .none;
    }
    view.seqposdisp +%= 1;
    if (view.valuecont == 0) return .none;
    view.subwpos2[1] = 38;
    view.valuecont = 0;
    return .none;
}

// -- chwrinw: instrument-window hex typing (datawriter.inc) --------------------
/// jmtbase/getitbi table base for subwindow w (reftpos keeps inst[10]/[11]).
fn tblBase(song: *const swm.Song, inst: usize, w: u8) u8 {
    return if (w == 1) wftablepos else song.insts[inst][8 + w]; // PW=inst[10], CTF=inst[11]
}

fn chwrinw(song: *swm.Song, view: *dsp.View, digit: u8) Effect {
    if (view.curwind != 2) return chwrchw(song, view, digit);
    saveUndo(song, view);
    const w = @min(view.subwpos1[2], 3);
    if (w != 0) return instbl(song, view, digit, w);
    return mainWin(song, view, digit);
}

/// main instrument panel (subwindow 0): pairs of columns per data byte,
/// HR-timer column 4, waveform-hi col4/col5-row0, octave column 5 row 3.
fn mainWin(song: *swm.Song, view: *dsp.View, digit: u8) Effect {
    const inst: usize = clampInst(view.selinst);
    const col = view.inswXbuf[0];
    const row = view.inswYbuf[0];
    if (col >= 4) return mainCols45(song, view, digit, col, row);
    const pos: usize = mainstrw[@as(usize, col >> 1) * 4 + @as(usize, @min(row, 3))];
    const old = song.insts[inst][pos];
    if (col & 1 == 0) {
        song.insts[inst][pos] = writeHex1(old, digit);
        return inswiri(view);
    }
    song.insts[inst][pos] = writeHex2(old, digit);
    if (col < 3) return inswiri(view);
    return .none;
}

fn mainCols45(song: *swm.Song, view: *dsp.View, digit: u8, col: u8, row: u8) Effect {
    const inst: usize = clampInst(view.selinst);
    if (col == 4) {
        if (row == 0) return wf1(song, view, digit, true);
        if (row != 1 or digit >= 3) return .none; // HR-timer takes 0..2
        song.insts[inst][0] = (song.insts[inst][0] & 0xfc) | digit;
        return .none;
    }
    // col 5
    if (row == 0) return wf1(song, view, digit, false);
    if (row != 3 or digit >= 8) return .none; // max octave shift = 7
    const old = song.insts[inst][9];
    if (old < 0x80) {
        song.insts[inst][9] = octmuls[digit];
        return .none;
    }
    song.insts[inst][9] = (octmuls[digit] -% 1) ^ 0xff; // negative (two's comp)
    return .none;
}

/// WF1left/right (col 4/5 row 0): gated by the WF1-enable bit in inst[0].
fn wf1(song: *swm.Song, view: *dsp.View, digit: u8, left: bool) Effect {
    const inst: usize = clampInst(view.selinst);
    if (song.insts[inst][0] & 8 == 0) return .none; // chkFR1
    const old = song.insts[inst][0x0f];
    const newv = if (left) writeHex1(old, digit) else writeHex2(old, digit);
    if (newv == 0) return .none; // don't allow 00 in SW1.x
    song.insts[inst][0x0f] = newv;
    if (left) return inswiri(view);
    return .none;
}

/// instbl: the WF/ARP/PW/CTF tables (3-byte rows, $fe jump rows).
fn instbl(song: *swm.Song, view: *dsp.View, digit: u8, w: u8) Effect {
    const inst: usize = clampInst(view.selinst);
    const col = view.inswXbuf[w];
    const odd = col & 1 != 0;
    const base: u8 = tblBase(song, inst, w);
    const row = @as(usize, tblScroll(view, w).* +% view.inswYbuf[w]);
    const row0pos: usize = base + row * 3;
    if (row0pos >= swm.inst_size) return .none; // past the table area (asm reads on)
    const row0 = song.insts[inst][row0pos];
    if (row0 == 0xff) return .none; // end-of-table row
    const xi = row0pos + (col >> 1);
    if (xi >= swm.inst_size) return .none; // (asm would read into the next slot)
    const is1st = col < 2;
    const is3rd = col >= 4;
    if (is3rd and row0 == 0xfe) return .none; // 3rd column blocked on jump rows
    if (!is1st and !is3rd and row0 == 0xfe) { // jump-address arithmetic
        const cur = song.insts[inst][xi];
        var rown: u8 = cur -% base; // div3acu
        var q: u8 = 0;
        while (rown >= 3) : (rown -= 3) q += 1;
        rown = q;
        const merged = if (odd) writeHex2(rown, digit) else writeHex1(rown, digit);
        song.insts[inst][xi] = merged *% 3 +% base; // multi3b + jmtbase
    } else {
        const newv = if (odd) writeHex2(song.insts[inst][xi], digit) else writeHex1(song.insts[inst][xi], digit);
        if (is1st) {
            if (newv == 0xff) return .none; // don't write an endsignal
            if (newv == 0xfe) { // jump row: zero-init the jump address
                song.insts[inst][xi] = 0xfe;
                if (xi + 1 < swm.inst_size) song.insts[inst][xi + 1] = base;
                return inswiri(view);
            }
        }
        song.insts[inst][xi] = newv;
    }
    if (odd and col == 5) return .none; // last column: no advance
    return inswiri(view);
}

// -- chwrchw: chord-table hex typing (datawriter.inc) --------------------------
fn chwrchw(song: *swm.Song, view: *dsp.View, digit: u8) Effect {
    if (view.curwind != 3) return tmptbwr(song, view, digit);
    const even = view.subwpos2[3] == 0;
    const pos: usize = @as(usize, dsp.chordStart(song, @min(view.selchor, max_chord - 1))) +
        view.chorpos +% view.subwpos1[3];
    if (pos >= swm.chord_len) return .none;
    const cur = song.chords[pos];
    const noteMode = view.confbits & 0x40 != 0;
    if (noteMode) return chordNoteCommon(song, view, digit, pos);
    // number mode
    const newv = if (even) writeHex1(cur, digit) else writeHex2(cur, digit);
    if (cur == 0x7e or cur == 0x7f) { // end signals: only 7e/7f overwrite
        if (newv != 0x7e and newv != 0x7f) return .none;
        song.chords[pos] = newv;
        return if (even) chtmrig(view) else .none;
    }
    if (newv == 0x7e or newv == 0x7f) return .none; // don't type endsignals
    song.chords[pos] = newv;
    if (even) return chtmrig(view);
    return chordNextRow(song, view);
}

/// notemod (chord note-mode): jam + calcoct + BasNote, store the note.
fn chordNoteCommon(song: *swm.Song, view: *dsp.View, digit: u8, pos: usize) Effect {
    const even = view.subwpos2[3] == 0;
    const cur = song.chords[pos];
    const raw = note_of_y[digit];
    jamming(view, raw); // notsto2 note jams before anything
    if (cur == 0x7e or cur == 0x7f) { // 7e/7f: only writehex digit >= that
        const newv = if (even) writeHex1(cur, digit) else writeHex2(cur, digit);
        if (newv == 0x7e or newv == 0x7f) song.chords[pos] = newv;
        return if (even) chtmrig(view) else .none;
    }
    if (view.jammode) return .none;
    const n = calcoct(view, raw) orelse return .none; // bcs noctwr
    const rel = n -% view.basnote; // sec sbc BasNote
    if (rel >= 0x7e) return .none; // filt accidental loop/jump commands
    song.chords[pos] = rel;
    if (view.autoadv == 0) return .none;
    return chordNextRow(song, view);
}

/// nextrow (chord window): column 0, cursor down.
fn chordNextRow(song: *swm.Song, view: *dsp.View) Effect {
    view.subwpos2[3] = 0;
    return norcrdn(song, view);
}

// -- tmptbwr: tempo-table hex typing (datawriter.inc) --------------------------
fn tmptbwr(song: *swm.Song, view: *dsp.View, digit: u8) Effect {
    const even = view.subwpos2[4] == 0;
    const pos: usize = @as(usize, dsp.tempoStart(song, @min(view.seltemp, max_tempo - 1))) +
        view.temppos +% view.subwpos1[4];
    if (pos >= swm.tempo_len) return .none;
    const cur = song.tempo[pos];
    if (even) {
        var d = digit;
        if (cur >= 0x80) d |= 0x08; // end-of-program digit keeps the marker set
        if (digit >= 8) return .none; // 1st digit caps at 7
        song.tempo[pos] = writeHex1(cur, d);
        return chtmrig(view);
    }
    song.tempo[pos] = writeHex2(cur, digit);
    // carretn: back to column 0 and one row down (retdown -> norcrdn)
    view.subwpos2[4] = 0;
    return norcrdn(song, view);
}

// == cursor movement (keyhandler cursori/norcrri/norcrle/cursrdn/norcrup) ======

// -- menu cursor rows (menucup/menucdn; the item actions are Part 4) ----------
const menu_firstcpos = menu.firstcpos; // menu.firstcpos: the SAVE TUNE row
const menu_lastcrpos = menu.lastcrpos; // menu.lastcrpos: the INSTANT HELP! row

/// menucup: menu cursor up, wrapping to the last row. Help mode does not
/// scroll (menucup checks menu.helpmode+1 first).
fn menuUp(view: *dsp.View) Effect {
    if (view.helpmode) return .none;
    view.menucurpos = if (view.menucurpos <= menu_firstcpos) menu_lastcrpos else view.menucurpos - 1;
    return .none;
}

/// menucdn: menu cursor down, wrapping to the first row.
fn menuDown(view: *dsp.View) Effect {
    if (view.helpmode) return .none;
    view.menucurpos = if (view.menucurpos >= menu_lastcrpos) menu_firstcpos else view.menucurpos + 1;
    return .none;
}

/// cursori (key code 2): cursor right, or cursor left when SHIFT is held.
fn cursori(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) return cursorLeft(song, view, key.cbm);
    return cursorRight(song, view);
}

/// norcrri: one column right in the current window.
fn cursorRight(song: *swm.Song, view: *dsp.View) Effect {
    if (view.menumode) return menuInc(song, view); // menu.menuinc (Part 4 item edit)
    switch (view.curwind) {
        0 => return ptnCurRight(song, view),
        1 => return olirigh(song, view),
        2 => return inswiri(view),
        else => return chtmrig(view),
    }
}

/// olirigh: orderlist cursor right; refuses to step past the end signals.
fn olirigh(song: *swm.Song, view: *dsp.View) Effect {
    const idx = @as(usize, seqByte(view));
    if (idx >= seqlen + 1) return .none; // cmp #seqlength+1
    return seqStepR(song, view, true); // seqstpr1 (always with the initial dey)
}

/// norcrle: one column left in the current window.
fn cursorLeft(song: *swm.Song, view: *dsp.View, cbm: bool) Effect {
    _ = cbm; // cbm+left has no separate handler (shcbget feeds the same path)
    if (view.menumode) return menuDec(song, view); // menu.menudec (Part 4)
    switch (view.curwind) {
        0 => return ptnCurLeft(song, view),
        1 => return oliLeft(view),
        2 => return insCurLeft(song, view),
        else => return chtCurLeft(song, view),
    }
}

/// norcrle window-0 branch: at column 0 jump back to the previous track.
fn ptnCurLeft(song: *swm.Song, view: *dsp.View) Effect {
    if (view.subwpos2[0] != 0) {
        view.subwpos2[0] -= 1;
        return .none;
    }
    if (view.subwpos1[0] == 0) return .none; // keyrtbb: track 0 stops here
    view.subwpos2[0] = 6;
    tabPtnBack(song, view);
    return .none;
}

/// olileft/seqleft: orderlist cursor left; at column 0 scroll the display.
fn oliLeft(view: *dsp.View) Effect {
    if (view.subwpos2[1] != 0) {
        view.subwpos2[1] -= 1;
        return .none;
    }
    if (view.seqposdisp != 0) view.seqposdisp -%= 1; // seqleft
    return .none;
}

/// noseqle: instrument-window cursor left; wrapping at column 0 leaves the
/// window back to the pattern editor (f5er.ptnwsel).
fn insCurLeft(song: *swm.Song, view: *dsp.View) Effect {
    const w = @min(view.subwpos1[2], 3);
    if (view.inswXbuf[w] > 0) {
        view.inswXbuf[w] -= 1;
        return .none;
    }
    return ptnwsel(song, view);
}

/// chktmpl/tabtoin: chord/tempo cursor left at column 0 jumps back into the
/// instrument window (subwindow 2 from chord, subwindow 4 from tempo).
fn chtCurLeft(song: *swm.Song, view: *dsp.View) Effect {
    const x = @min(view.curwind, 4);
    if (view.subwpos2[x] != 0) {
        view.subwpos2[x] -= 1;
        return .none;
    }
    return tabtoin(song, view);
}

/// tabtoin/goInsWi/setInsW: re-enter the instrument window on the PW/CTF side.
fn tabtoin(song: *swm.Song, view: *dsp.View) Effect {
    _ = song;
    view.subwpos1[2] = @as(u8, @min(view.curwind, 4)) *% 2 -% 4; // txa; asl; sbc #4
    view.curwind = 2;
    return .none;
}

/// f5er.ptnwsel: leave the instrument/chord/tempo window for the pattern
/// editor (columns carried over when coming from window 1..3).
fn ptnwsel(song: *swm.Song, view: *dsp.View) Effect {
    _ = song;
    view.curwind = 0;
    return .none;
}

/// cursrdn (key code 7): cursor down, or cursor up when SHIFT is held.
fn cursrdn(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) return norcrup(song, view);
    return norcrdn(song, view);
}

/// norcrup: cursor up in the current window.
fn norcrup(song: *swm.Song, view: *dsp.View) Effect {
    if (view.menumode) return menuUp(view);
    if (view.curwind != 0) return noptcup(song, view);
    // ptcurup
    if (view.subwpos3[0] != 0) {
        view.subwpos3[0] -= 1;
        return .none;
    }
    return nodecpu(song, view); // at the screen top: scroll the track
}

/// nodecpu: scroll the current track's display up. With track-binding on, the
/// asm loops tracks 2..1 and then falls THROUGH into ptscrup with X=0, so all
/// three tracks scroll (the "X is 0 here, to do 1st track too" comment).
fn nodecpu(song: *swm.Song, view: *dsp.View) Effect {
    if (view.confbits & 1 != 0) {
        var x: u8 = 2; // ldx #CHN_AMOUNT-1
        while (x != 0) : (x -= 1) ptscrup(song, view, x);
        ptscrup(song, view, 0); // loop fall-through: bne - failed at X=0
        return .none;
    }
    ptscrup(song, view, clampTrack(view.subwpos1[0]));
    return .none;
}

/// ptscrup: prowpos-- when not at 0.
fn ptscrup(song: *swm.Song, view: *dsp.View, t: u8) void {
    _ = song;
    const tt: usize = clampTrack(t);
    if (view.prowpos[tt] != 0) view.prowpos[tt] -= 1;
}

/// noptcup: cursor up in windows 1..4.
fn noptcup(song: *swm.Song, view: *dsp.View) Effect {
    if (view.curwind == 1) return oliup(song, view);
    if (view.curwind == 2) return insUp(song, view);
    return noiscup(song, view); // windows 3/4
}

/// oliup: orderlist cursor up a track; at track 0 wrap to track 2, then move
/// the cursor onto a writable position (sseqend).
fn oliup(song: *swm.Song, view: *dsp.View) Effect {
    if (view.subwpos1[1] != 0) {
        view.subwpos1[1] -= 1;
    } else {
        view.subwpos1[1] = 2; // CHN_AMOUNT-1
    }
    return sseqend(song, view);
}

/// noptcup instrument branch: up inside the instrument window.
fn insUp(song: *swm.Song, view: *dsp.View) Effect {
    const w = @min(view.subwpos1[2], 3);
    if (view.inswYbuf[w] != 0) {
        view.inswYbuf[w] -= 1;
        return .none;
    }
    return nodeciu(song, view);
}

/// nodeciu: cursor at the top row of instrument window.
fn nodeciu(song: *swm.Song, view: *dsp.View) Effect {
    const w = @min(view.subwpos1[2], 3);
    if (w == 0) return nametypeEnter(song, view); // nkeysub.InsName: rename
    if (tblScroll(view, w).* == 0) return isubwup(song, view); // table top
    tblScroll(view, w).* -= 1; // scroll the table up
    return .none;
}

/// isubwup: move up into the previous instrument subwindow, carrying the
/// column over. Only subwindow 1 adjusts (skip columns 0 and 4: the WF table
/// has no gate column there), and the store target is inswXbuf[x-1] because
/// tbinsbk decrements the subwindow right after (asm quirk, ported verbatim).
fn isubwup(song: *swm.Song, view: *dsp.View) Effect {
    _ = song;
    const w = @min(view.subwpos1[2], 3);
    var col = view.inswXbuf[w];
    if (w == 1 and col != 0) {
        col -%= 1;
        if (col == 4) col = 3; // sbc #1 again: skip the 4th column
    }
    view.inswXbuf[w - 1] = col; // sta inswXbuf-1,x
    return tbinsbk(view);
}

/// noiscup: cursor up in the chord/tempo window; at the top scroll, and at
/// scroll position 0 switch windows (4->3, 3->2).
fn noiscup(song: *swm.Song, view: *dsp.View) Effect {
    _ = song; // (window state only; kept for call-site symmetry)
    const x = @min(view.curwind, 4);
    if (view.subwpos1[x] != 0) {
        view.subwpos1[x] -= 1;
        return .none;
    }
    // chscrup: scroll position (chorpos for window 3, temppos for window 4)
    const scroll = if (x == 3) &view.chorpos else &view.temppos;
    if (scroll.* != 0) {
        scroll.* -= 1;
        return .none;
    }
    view.curwind -= 1; // dec curwind: 4->3, 3->2
    if (x == 3) { // came from the tempo window into the chord window
        view.inswXbuf[0] = 4;
        view.subwpos1[2] = 0;
    }
    return .none;
}

/// norcrdn: cursor down in the current window.
fn norcrdn(song: *swm.Song, view: *dsp.View) Effect {
    if (view.menumode) return menuDown(view);
    if (view.curwind != 0) return noptcdn(song, view);
    return ptcurdn(song, view);
}

/// ptcurdn: one row down in the pattern; at the pattern end scroll instead.
fn ptcurdn(song: *swm.Song, view: *dsp.View) Effect {
    const cc = compcur(song, view);
    if (!cc.inside) return .none; // at the endsignal: nothing moves
    if (view.subwpos3[0] != 25 - 1) { // cmp #24
        view.subwpos3[0] += 1;
        return .none;
    }
    return noincpu(song, view); // last screen row: scroll the track down
}

/// godownp: go down in the pattern after a data modifier (repeater hint only).
fn godownp(song: *swm.Song, view: *dsp.View) void {
    _ = ptcurdn(song, view);
}

/// noincpu: scroll the display down. With track-binding on, all three tracks
/// scroll (loop + fall-through, see nodecpu).
fn noincpu(song: *swm.Song, view: *dsp.View) Effect {
    if (view.confbits & 1 != 0) {
        var x: u8 = 2;
        while (x != 0) : (x -= 1) ptscrdn(song, view, x);
        ptscrdn(song, view, 0); // loop fall-through: bne - failed at X=0
        return .none;
    }
    ptscrdn(song, view, clampTrack(view.subwpos1[0]));
    return .none;
}

/// ptscrdn: prowpos++ while the pattern is longer than the display position.
fn ptscrdn(song: *swm.Song, view: *dsp.View, t: u8) void {
    const tt: usize = clampTrack(t);
    const ptn = clampPtn(view.curptn1[tt]);
    if (song.ptn_len[ptn] != view.prowpos[tt]) view.prowpos[tt] +%= 1;
}

/// noptcdn: cursor down in windows 1..4.
fn noptcdn(song: *swm.Song, view: *dsp.View) Effect {
    if (view.curwind == 1) return olidown(song, view);
    if (view.curwind == 2) return insDown(song, view);
    return noiscdn(song, view);
}

/// olidown: orderlist cursor down a track, wrapping track 2 -> 0, then sseqend.
fn olidown(song: *swm.Song, view: *dsp.View) Effect {
    if (view.subwpos1[1] < 2) {
        view.subwpos1[1] += 1;
    } else {
        view.subwpos1[1] = 0; // $ff + 1 wrap
    }
    return sseqend(song, view);
}

/// noseqdn: cursor down in the instrument window.
fn insDown(song: *swm.Song, view: *dsp.View) Effect {
    const w = @min(view.subwpos1[2], 3);
    if (w != 0) { // tables: check the endsignal under the cursor first
        const inst: usize = clampInst(view.selinst);
        const pos: usize = @as(usize, tblBase(song, inst, w)) +
            @as(usize, tblScroll(view, w).* +% view.inswYbuf[w]) * 3;
        if (pos < swm.inst_size and song.insts[inst][pos] == 0xff) return isubwdn(song, view);
    }
    if (view.inswYbuf[w] != iswmaxy[w]) {
        view.inswYbuf[w] += 1;
        return .none;
    }
    return noinciu(song, view);
}

/// isubwdn: move down into the next instrument subwindow, carrying the column
/// over (inswXbuf+1,x store before tbinsfw increments the subwindow).
fn isubwdn(song: *swm.Song, view: *dsp.View) Effect {
    _ = song;
    const w = @min(view.subwpos1[2], 3);
    if (w == 3) return .none; // cpx #3: the CTF table is the last one
    var col = view.inswXbuf[w];
    if (w == 0) col +%= 1; // clc; adc #1 for the main window
    view.inswXbuf[w + 1] = col;
    return tbinsfw(view);
}

/// noinciu: cursor at the bottom row of instrument window.
fn noinciu(song: *swm.Song, view: *dsp.View) Effect {
    const w = @min(view.subwpos1[2], 3);
    if (w == 0) { // main window: below the table start (col < 4) go to WF
        if (view.inswXbuf[0] < 4) return isubwdn(song, view);
        view.curwind = 3; // f5er.swtochd
        view.prevwin = 2;
        view.subwpos1[3] = 0;
        view.chorpos = 0;
        return .none;
    }
    tblScroll(view, w).* +%= 1; // scroll the table down
    return .none;
}

/// noiscdn: cursor down in the chord/tempo window; a chord endsignal ($7e/$7f
/// or >= $80) hands over to the tempo window.
fn noiscdn(song: *swm.Song, view: *dsp.View) Effect {
    if (view.curwind == 3) {
        const pos: usize = @as(usize, dsp.chordStart(song, @min(view.selchor, max_chord - 1))) +
            view.chorpos +% view.subwpos1[3];
        if (pos < swm.chord_len) {
            const v = song.chords[pos];
            if (v >= 0x7e) { // bmi / cmp #$7e: end or loop byte
                view.curwind = 4; // f7er.swtotmp
                return .none;
            }
        }
        if (view.subwpos1[3] != 12) {
            view.subwpos1[3] += 1;
            return .none;
        }
        view.chorpos +%= 1; // chscrol
        return .none;
    }
    if (view.curwind == 4) {
        const pos: usize = @as(usize, dsp.tempoStart(song, @min(view.seltemp, max_tempo - 1))) +
            view.temppos +% view.subwpos1[4];
        if (pos < swm.tempo_len and song.tempo[pos] >= 0x80) return .none; // bmi keyretc
        if (view.subwpos1[4] != 3) {
            view.subwpos1[4] += 1;
            return .none;
        }
        view.temppos +%= 1; // tmscrol
    }
    return .none;
}

/// cSeqLop: true when the orderlist byte before the cursor is a $ff jump.
fn cSeqLop(song: *swm.Song, view: *const dsp.View) bool {
    const idx = @as(usize, seqByte(view));
    if (idx == 0) return false;
    return seqOf(song, view)[idx - 1] == swm.seq_end_loop;
}

/// sseqend: after moving to a shorter/other sequence, if the byte under the
/// cursor is $00, re-place the cursor at the sequence's end signal (and scroll
/// the display if the end lies before it).
fn sseqend(song: *swm.Song, view: *dsp.View) Effect {
    if (cSeqLop(song, view)) return .none;
    const seq = seqOf(song, view);
    const idx: usize = seqByte(view);
    if (seq[idx & (swm.seq_bound - 1)] != 0) return .none;
    var end: u8 = 0;
    var y: usize = 0;
    while (y < seqlen) : (y += 1) { // seek the first $fe/$ff
        if (seq[y] >= swm.seq_end_stop) {
            end = @intCast(y);
            break;
        }
    }
    if (end >= view.seqposdisp) { // end inside the screen: move the cursor
        view.subwpos2[1] = (end -% view.seqposdisp) *% 2;
        return .none;
    }
    view.seqposdisp = end; // end before the display: scroll back
    view.subwpos2[1] = 0;
    return .none;
}

// -- CTRL/TAB (ctrler) and HOME (homer) ---------------------------------------

/// The three table-scroll bytes the asm addresses as wfarpos-1,x (they are
/// adjacent in zero page): w=1 WF/ARP, w=2 PW, w=3 CTF.
fn tblScroll(view: *dsp.View, w: u8) *u8 {
    return switch (w) {
        1 => &view.wfarpos,
        2 => &view.pwtbpos,
        else => &view.ctftpos,
    };
}

/// ctrler (key code 58): TAB between tracks/subwindows; SHIFT tabs back.
fn ctrler(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) {
        switch (view.curwind) {
            0 => tabPtnBack(song, view),
            2 => {
                _ = tbinsbk(view);
            },
            3, 4 => _ = tabtoin(song, view),
            else => {},
        }
        return .none;
    }
    switch (view.curwind) {
        0 => tabPtnFwd(song, view),
        2 => {
            _ = tbinsfw(view);
        },
        3, 4 => view.curwind = 0, // tabtopt: back to the pattern window
        else => {},
    }
    return .none;
}

/// tbinsbk: previous instrument subwindow, wrapping 0 -> 3.
fn tbinsbk(view: *dsp.View) Effect {
    view.subwpos1[2] = if (view.subwpos1[2] == 0) 3 else view.subwpos1[2] - 1;
    return .none;
}

/// tbinsfw: next instrument subwindow, wrapping 3 -> 0.
fn tbinsfw(view: *dsp.View) Effect {
    view.subwpos1[2] = if (view.subwpos1[2] >= 3) 0 else view.subwpos1[2] + 1;
    return .none;
}

/// homer (key code 51): home the cursor; SHIFT homes the orderlist fully.
fn homer(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (view.menumode) { // menpini: jump to the first menu row
        view.menucurpos = menu_firstcpos;
        return .none;
    }
    if (key.shift) { // full orderlist home
        view.curwind = 1;
        view.subwpos2[1] = 0; // homeOl1
        view.seqposdisp = 0; // homeOl2
        return .none;
    }
    switch (view.curwind) {
        0 => return homePtn(song, view),
        1 => { // window 1: column 0, then display 0
            if (view.subwpos2[1] != 0) view.subwpos2[1] = 0 else view.seqposdisp = 0;
            return .none;
        },
        2 => { // instrument window: zero scroll + cursor of the subwindow
            const w = @min(view.subwpos1[2], 3);
            if (w != 0) tblScroll(view, w).* = 0;
            view.inswYbuf[w] = 0;
            view.inswXbuf[w] = 0;
            return .none;
        },
        else => { // chthome: zero cursor + scroll of chord (3) / tempo (4)
            const x = @min(view.curwind, 4);
            view.subwpos1[x] = 0;
            if (x == 3) view.chorpos = 0 else view.temppos = 0;
            return .none;
        },
    }
}

/// homePtn: small home zeroes the in-screen cursor; at (0,0) it scrolls the
/// pattern display to the top (all tracks when binding is on).
fn homePtn(song: *swm.Song, view: *dsp.View) Effect {
    _ = song; // confbits lives in the view
    if (view.subwpos2[0] | view.subwpos3[0] != 0) {
        view.subwpos3[0] = 0;
        view.subwpos2[0] = 0;
        return .none;
    }
    const t = clampTrack(view.subwpos1[0]);
    view.prowpos[t] = 0;
    if (view.confbits & 1 != 0) {
        view.prowpos[0] = 0;
        view.prowpos[1] = 0;
        view.prowpos[2] = 0;
    }
    return .none;
}

// == INSERT / DELETE family (keyhandler inskeye 2888, deleter 2610, delordl) ==
const tblamoun = 3; // tblamoun: instrument subtable count

/// getlast/detmemp: byte offset (mpos-relative) of the pattern's last row,
/// walking rowSize over (ptn_len - prowpos - 1) rows from the display top.
fn getLastOff(song: *swm.Song, view: *const dsp.View, t: usize) u8 {
    const ptn = clampPtn(view.curptn1[t]);
    const rows = song.ptn_len[ptn] -% view.prowpos[t];
    var y: u8 = rows -% 1; // detmemp tay; dey
    var off: u8 = 0;
    const base = ptnBase(song, ptn);
    var guard: usize = 256;
    while (y != 0 and guard > 0) : ({
        y -%= 1;
        guard -= 1;
    }) { // xdetlop
        off +%= rowLenAt(base, @as(usize, ptnMpos(song, view, t)) +% off);
    }
    return off;
}

/// deleter.dellast: delete the pattern's last row (no guards - the caller
/// insinpt only runs inside a pattern that has rows).
fn dellast(song: *swm.Song, view: *dsp.View, c: PCtx) void {
    const t = clampTrack(view.subwpos1[0]);
    const off = getLastOff(song, view, t);
    const pos: usize = c.mpos +% off;
    delBackPt(song, view, c.base, @intCast(pos), rowLenAt(c.base, pos));
}

/// inskeye (£ code 48, or SHIFT+DEL): insert a row/column.
fn inskeye(song: *swm.Song, view: *dsp.View, cbm: bool) Effect {
    if (view.curwind != 0) return olinser(song, view, cbm);
    if (view.followp) return .none; // playadapter.followp gate
    saveUndo(song, view);
    const c = pctx(song, view) orelse return .none; // pattern 0 read-only
    const cc = compcur(song, view);
    if (cc.inside) { // insinpt: new empty row at the cursor, last row drops
        dellast(song, view, c);
        // insertpt(X = notepos-1, Y = 1, zeroval = 0): the new slot appears
        // at [notepos] (insertpt leaves [x] and zeroes [x+1])
        _ = insertPt(song, view, c.base, c.x -% 1, 1, 0);
        return .none; // asm jmp insertpt: no cursor move
    }
    return insAtEnd(song, view); // at the endsignal: grow the pattern
}

/// inskeye at-end path: append a NOP row + $ff endmarker (absolute PPTR
/// addressing), size/length++.
fn insAtEnd(song: *swm.Song, view: *dsp.View) Effect {
    const t = clampTrack(view.subwpos1[0]);
    const ptn = clampPtn(view.curptn1[t]);
    if (ptn == 0) return .none; // beq retpnto: no insert into pattern 0
    const size = song.ptn_size[ptn];
    if (size >= swm.ptn_len_max) return .none; // cmp #maxptnlen; bcs
    song.ptn_size[ptn] +%= 1;
    song.ptn_len[ptn] +%= 1;
    const base = &song.pats[ptn - 1];
    base[size - 1] = 0; // NOP over the old endmarker
    base[size] = swm.ptn_end; // new endmarker
    godownp(song, view);
    return .none;
}

/// seqInst, with an explicit orderlist track (moreSeqInst types into all 3).
fn seqInstTrack(song: *swm.Song, view: *const dsp.View, track: u8) Effect {
    const ti = @as(usize, clampSubt(view.selsubt)) * 3 + clampTrack(track);
    const seq = &song.seqs[ti];
    if (seq[seqlen - 1] >= swm.seq_end_stop) return .none; // full (cmp #$fe; bcs)
    const idx = @as(usize, (view.subwpos2[1] >> 1) +% view.seqposdisp);
    if (seq[idx] == 0) return .none; // pattern 00 protected
    if (seq[(idx -% 1) & (swm.seq_bound - 1)] == swm.seq_end_loop) return .none; // jump operand
    var x: usize = seqlen - 1; // olinsrt/olinsrb: [idx..seqlen-1] -> [+1..]
    var y: usize = seqlen;
    while (x >= idx) : ({
        x -= 1;
        y -= 1;
    }) seq[y] = seq[x];
    seq[idx] = 1; // seqaddc: new pattern number 1
    return .none;
}

/// moreSeqInst.adjust: after an orderlist insert, step the cursor right past
/// the inserted digit (two seqstpr1 steps; one when parked at column 39).
fn moreSeqAdj(song: *swm.Song, view: *dsp.View) Effect {
    const idx = @as(usize, seqByte(view));
    if (seqOf(song, view)[idx +% 1] < swm.seq_end_stop) return .none; // cmp #$fe; bcc
    if (view.subwpos2[1] != 39) _ = seqStepR(song, view, true);
    return seqStepR(song, view, true);
}

/// olinser: insert in the orderlist (window 1), instrument (2), chord (3)
/// or tempo (4) window.
fn olinser(song: *swm.Song, view: *dsp.View, cbm: bool) Effect {
    if (view.curwind == 1) {
        if (cbm) { // moreSeqInst: all three tracks, NOT undoable
            const save = view.subwpos1[1];
            var tr: u8 = 2; // CHN_AMOUNT-1
            while (true) : (tr -= 1) {
                _ = seqInstTrack(song, view, tr);
                if (tr == 0) break;
            }
            view.subwpos1[1] = save;
            return moreSeqAdj(song, view);
        }
        saveUndo(song, view);
        _ = seqInstTrack(song, view, view.subwpos1[1]);
        return moreSeqAdj(song, view);
    }
    if (view.curwind == 2) return insinst(song, view);
    if (view.curwind == 3) return inschrd(song, view);
    return instmptIns(song, view); // window 4
}

/// getitbi: the current table row's start index inside insts[selinst]
/// ((wfarpos + inswYbuf) * 3 + table base).
fn getitbi(song: *swm.Song, view: *dsp.View) u8 {
    const w = @min(view.subwpos1[2], 3);
    const inst: usize = clampInst(view.selinst);
    const row = tblScroll(view, w).* +% view.inswYbuf[w];
    return tblBase(song, inst, w) +% row *% 3;
}

/// insinst: insert a 3-byte row into the instrument table under the cursor,
/// shifting the table up and fixing the table/gateoff pointers and $fe jump
/// addresses that point at/after the insertion position.
fn insinst(song: *swm.Song, view: *dsp.View) Effect {
    saveUndo(song, view); // before the subwindow check (asm order)
    if (view.subwpos1[2] == 0) return .none; // main settings: no insertion
    const inst: usize = clampInst(view.selinst);
    const pos: u8 = getitbi(song, view);
    const ins = &song.insts[inst];
    if (ins[lastinstpt] != 0) return .none; // last row occupied: table full
    var x: u8 = lastinstpt - tblwidth; // move data up by 3 (tblstart..end)
    var y: u8 = lastinstpt;
    while (x >= pos) : ({
        x -%= 1;
        y -%= 1;
    }) {
        ins[y] = ins[x];
        if (x == 0) break; // u8 underflow safety (asm wraps)
    }
    var i: usize = 0;
    while (i < 3) : (i += 1) { // zero the inserted row
        if (pos + i < swm.inst_size) ins[pos + i] = 0;
    }
    // shift the table pointers of tables after this one (+3): inst[10]/[11]
    var yy: u8 = 11;
    var xx: u8 = @min(view.subwpos1[2], 3);
    while (xx < tblamoun) : ({
        xx += 1;
        yy -%= 1;
    }) {
        ins[yy] +%= tblwidth;
        if (yy == 0) break;
    }
    // gateoff pointers (inst[12..14]) pointing at/after pos: +3
    var g: usize = 12;
    while (g < 12 + tblamoun) : (g += 1) {
        if (ins[g] >= pos) ins[g] +%= tblwidth;
    }
    return instJumpFix(song, ins, pos, true);
}

/// instJumpFix (insinst/delitbl tail): walk the table rows; for $fe rows the
/// jump-address shifts by tblwidth when it points after (add) / strictly
/// after (sub) the changed position. $ff rows advance 1 byte.
fn instJumpFix(song: *swm.Song, ins: *[swm.inst_size]u8, pos: u8, add: bool) Effect {
    _ = song;
    var y: u8 = pos;
    var guard: usize = 128;
    while (y < lastinstpt and guard > 0) : (guard -= 1) {
        const v = ins[y];
        if (v == 0xfe) {
            const tgt = ins[y + 1];
            const fix = if (add) tgt >= pos else tgt > pos;
            if (fix) ins[y + 1] = if (add) tgt +% tblwidth else tgt -% tblwidth;
            y +%= tblwidth;
        } else {
            y +%= if (v == 0xff) 1 else tblwidth;
        }
    }
    return .none;
}

/// chordLenAt: bytes occupied by the chord starting at `start` (next $7e/$7f
/// delimiter inclusive); unterminated = "too long" ($ff, refuse).
fn chordLenAt(song: *swm.Song, start: u8) u8 {
    var k: u8 = start;
    while (k < swm.chord_len) : (k +%= 1) {
        const v = song.chords[k];
        if (v == swm.chord_end1 or v == swm.chord_end2) return k +% 1 -% start;
    }
    return 0xff;
}

/// inschrd (curwind 3): insert one byte into the chord table at the cursor.
fn inschrd(song: *swm.Song, view: *dsp.View) Effect {
    if (song.chords[swm.chord_len - 2] != 0) return .none; // table full
    const start = dsp.chordStart(song, @min(view.selchor, max_chord - 1));
    if (chordLenAt(song, start) -% maxchordlen < 0x80) return .none; // len >= 32
    const pos: u8 = start +% view.chorpos +% view.subwpos1[3];
    var x: u8 = swm.chord_len - 1; // move [pos..254] up one
    while (x != pos) : (x -%= 1) song.chords[x] = song.chords[x -% 1];
    song.chords[pos] = 0; // empty inserted byte
    return .none;
    // (CHDPTR is derived from the delimiters in this port: +1 fixups implicit)
}

/// tempoLenAt: bytes of the tempo program starting at `start` (next byte with
/// bit7 inclusive); unterminated = "too long".
fn tempoLenAt(song: *swm.Song, start: u8) u8 {
    var k: u8 = start;
    while (k < swm.tempo_len) : (k +%= 1) {
        if (song.tempo[k] >= swm.tempo_end) return k +% 1 -% start;
    }
    return 0xff;
}

/// instmpt (curwind 4): insert one byte into the tempo table at the cursor.
/// The asm addresses TEMPOTBL pages offsets; song.tempo[] starts at page +9.
fn instmptIns(song: *swm.Song, view: *dsp.View) Effect {
    if (song.tempo[swm.tempo_len - 2] != 0) return .none; // page +126: full
    const start = dsp.tempoStart(song, @min(view.seltemp, max_tempo - 1));
    if (tempoLenAt(song, start) -% maxtempolen < 0x80) return .none; // len >= 32
    const pos: u8 = start +% view.temppos +% view.subwpos1[4];
    var x: u8 = swm.tempo_len - 1; // move [pos..last-2] up one (to page +126)
    while (x != pos) : (x -%= 1) song.tempo[x] = song.tempo[x -% 1];
    song.tempo[pos] = 0;
    return .none;
}

// -- DELETE key family (keyhandler deleter 2610) ------------------------------
/// deleter (key code 0): plain DEL deletes a row (SHIFT = insert via inskeye),
/// C= + DEL zeroes row content (delerow).
fn deleter(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.cbm) return delerow(song, view, key.shift);
    if (key.shift) return inskeye(song, view, false); // cInsert: shift held
    return delRow(song, view);
}

/// delRow (cInsert, plain DEL in the pattern window). Main path (delinpt):
/// delete the cursor row, then append NOP + endmarker at the absolute end -
/// ptnsize+1, NOP at [size-1], $ff at [size] in the port's inclusive-size
/// convention - with ptnlength (row count) untouched, and no cursor move
/// (the path ends at jmp instpt2). Windows other than 0 go to delordl.
fn delRow(song: *swm.Song, view: *dsp.View) Effect {
    if (view.curwind != 0) return delordl(song, view);
    if (view.followp) return .none; // followplay gate
    saveUndo(song, view);
    const c = pctx(song, view) orelse return .none;
    const cc = compcur(song, view);
    if (!cc.inside) return delLast(song, view); // compcur Z: at the endsignal
    // (asm edge: a 16-bit carry past $ff with a nonzero low byte falls into
    // this main path instead of dellast; the port routes it to dellast)
    delBackPt(song, view, c.base, c.x, rowLenAt(c.base, c.mpos +% c.x));
    const size = song.ptn_size[c.ptn]; // size after the delete (endmark at [size-1])
    if (size < swm.ptn_len_max) { // inc ptnsize (guard: the asm's flat
        song.ptn_size[c.ptn] +%= 1; // pattern memory needs none)
        c.base[size - 1] = 0; // NOP over the moved-up endmarker
        c.base[size] = swm.ptn_end; // new endmarker
    }
    return .none; // main path ends at jmp instpt2: no cursor move
}

/// deleter end-of-pattern branch (compcur Z: cursor on the endsignal).
/// Refuse when ptnlength is 1 or the cursor is at display row 0; otherwise
/// delete the last row's data (dellast: getlast + getdelamount + delbackpt),
/// dec ptnlength, then follow the endsignal up: scroll the display when the
/// cursor sits in the upper half of the screen (and isn't at the top), move
/// the cursor up otherwise.
fn delLast(song: *swm.Song, view: *dsp.View) Effect {
    const t = clampTrack(view.subwpos1[0]);
    const ptn = clampPtn(view.curptn1[t]);
    if (song.ptn_len[ptn] == 1) return .none; // cmp #minptnlen; beq delret
    if (view.subwpos3[0] == 0) return .none; // no ptncurs at display row 0
    const base = ptnMut(song, view, t) orelse return .none;
    const mpos = ptnMpos(song, view, t);
    const x = getlast(song, view) orelse return .none;
    delBackPt(song, view, base, x, rowLenAt(base, mpos +% x));
    song.ptn_len[ptn] -%= 1; // dec ptnlength
    if (view.prowpos[t] == 0) return upinptn(song, view);
    if (view.subwpos3[0] < 13) return nodecpu(song, view); // cmp #13
    return upinptn(song, view);
}

/// getlast (commonsubs): byte offset, relative to the display top row, of
/// the last row's data - walk ptn_len - prowpos - 1 rows down from the top.
fn getlast(song: *const swm.Song, view: *const dsp.View) ?u8 {
    const t = clampTrack(view.subwpos1[0]);
    const ptn = clampPtn(view.curptn1[t]);
    if (song.ptn_len[ptn] <= view.prowpos[t]) return null; // sbc borrow
    var x: u8 = 0;
    var y: usize = song.ptn_len[ptn] - view.prowpos[t] - 1;
    const base = ptnBase(song, ptn);
    const mpos = ptnMpos(song, view, t);
    while (y != 0) : (y -= 1) {
        x +%= @intCast(dsp.rowSize(base, mpos +% x));
    }
    return x;
}

/// upinptn: go up in pattern after a data modifier (the ptrdysi repeater
/// hint is a no-op here). ptcurup again: cursor up, or scroll at the top.
fn upinptn(song: *swm.Song, view: *dsp.View) Effect {
    if (view.subwpos3[0] != 0) {
        view.subwpos3[0] -= 1;
        return .none;
    }
    return nodecpu(song, view);
}

/// delerow (C= + DEL): zero row content. Note column only: keep the marker
/// bit (value zeroed). SHIFT also wipes the note value+marker; typing on
/// another column keeps the note value but clears the marker and deletes the
/// inst/fx columns (getdla2 entered with Y=0). Other windows: insert column.
fn delerow(song: *swm.Song, view: *dsp.View, shift: bool) Effect {
    if (view.curwind != 0) return olinser(song, view, true); // cbm held
    if (view.followp) return .none; // only allowed in the pattern window
    saveUndo(song, view);
    const c = pctx(song, view) orelse return .none;
    const note = rdP(c, c.x);
    if (shift) { // shiftsi branch: also zero out the note column
        wrP(c, c.x, note & 0x80);
        if (note & 0x80 == 0) { // A = $00 -> bpl advdelr: nothing follows
            if (view.autoadv != 0) godownp(song, view);
            return .none;
        }
    } else if (view.subwpos2[0] == 0) { // note column: keep the marker only
        wrP(c, c.x, note & 0x80);
        if (view.autoadv != 0) godownp(song, view);
        return .none;
    }
    // shared path (getdla2 with Y preset 0; A = $80 after the shift mask)
    const probe: u8 = if (shift) 0x80 else note;
    var y: u8 = 0; // bytes after the note column to delete
    if (probe >= 0x80) {
        const inst = rdP(c, c.x +% 1);
        if (inst & 0x80 != 0) {
            y = if (rdP(c, c.x +% 2) & 0xe0 == 0) 3 else 2;
        } else y = 1;
    }
    wrP(c, c.x, rdP(c, c.x) & 0x7f); // clear the note marker bit
    delBackPt(song, view, c.base, c.x +% 1, y);
    if (view.autoadv != 0) godownp(song, view); // advdelr
    return .none;
}

/// delordl (DEL in windows 1..4): orderlist delete, then the instrument/
/// chord/tempo table deleters.
fn delordl(song: *swm.Song, view: *dsp.View) Effect {
    if (view.curwind != 1) return delitbl(song, view);
    saveUndo(song, view);
    const seq = seqOf(song, view);
    if (seq[0] >= swm.seq_end_stop) return .none; // below-zero-length guard
    if (cSeqLop(song, view)) return .none; // loop-jump operand position
    const idx = @as(usize, seqByte(view));
    var delpos: usize = idx;
    if (seq[idx] >= swm.seq_end_stop) { // endmarker under cursor: backspace
        if (view.subwpos2[1] < 20 and view.seqposdisp != 0) {
            view.seqposdisp -%= 1; // scroll the display instead of the column
        } else {
            view.subwpos2[1] -%= 2;
        }
        delpos -%= 1; // backdel: delete the byte before the cursor
    }
    var y: usize = delpos; // oldelet/oldeleb: [delpos+1..127] -> [delpos..126]
    while (y != seqlen + 1) : (y += 1) seq[y] = seq[y + 1];
    return chkjadd(song, view);
}

/// chkjadd: walk to the first orderlist $ff loop command and clamp its jump
/// target to the last position before it ($fe before any $ff ends the walk;
/// subtune jumps >= $80 are left alone).
fn chkjadd(song: *swm.Song, view: *dsp.View) Effect {
    const seq = seqOf(song, view);
    var y: usize = 0;
    while (y < seqlen) : (y += 1) {
        if (seq[y] == swm.seq_end_stop) return .none; // cmp #$fe; beq delret
        if (seq[y] != swm.seq_end_loop) continue;
        const tgt = seq[y + 1];
        if (tgt >= 0x80) return .none; // bmi delret: subtune jump
        if (tgt >= y - 1) seq[y + 1] = @intCast(y - 1); // cmpjmp3 clamp
        return .none;
    }
    return .none;
}

/// delitbl (DEL in window 2): delete a 3-byte instrument table row, moving
/// the rest back and zeroing the freed last row; then shift the table/
/// gateoff pointers of later tables and fix $fe jump addresses.
fn delitbl(song: *swm.Song, view: *dsp.View) Effect {
    if (view.curwind != 2) return delchrd(song, view);
    saveUndo(song, view);
    if (view.subwpos1[2] == 0) return .none; // main settings: nothing to do
    const inst: usize = clampInst(view.selinst);
    const pos: u8 = getitbi(song, view);
    const ins = &song.insts[inst];
    if (pos +% tblwidth > lastinstpt or ins[pos] == 0xff) return .none;
    var x: u8 = pos; // move [pos+3..lastinstpt] back by 3
    var y: u8 = pos +% tblwidth;
    while (y <= lastinstpt) : ({
        x +%= 1;
        y +%= 1;
    }) ins[x] = ins[y];
    var i: usize = 0; // zero the freed last row (115..117)
    while (i < 3) : (i += 1) ins[lastinstpt - 2 + i] = 0;
    var yy: u8 = 11; // table pointers of later tables: -3
    var xx: u8 = @min(view.subwpos1[2], 3);
    while (xx < tblamoun) : ({
        xx += 1;
        yy -%= 1;
    }) ins[yy] -%= tblwidth;
    var g: usize = 12; // gateoff pointers strictly after pos: -3
    while (g < 12 + tblamoun) : (g += 1) {
        if (ins[g] > pos) ins[g] -%= tblwidth;
    }
    return instJumpFix(song, ins, pos, false);
}

/// delchrd (DEL in window 3): delete one chord-table byte at the cursor.
fn delchrd(song: *swm.Song, view: *dsp.View) Effect {
    if (view.curwind != 3) return deltmpt(song, view);
    const pos: usize = @as(usize, dsp.chordStart(song, @min(view.selchor, max_chord - 1))) +
        view.chorpos +% view.subwpos1[3];
    if (pos >= swm.chord_len) return .none;
    const v = song.chords[pos];
    if (v < 0x80 and v >= swm.chord_end1) return .none; // $7e/$7f: no delete
    var x: usize = pos; // move [pos+1..254] back one
    while (x < swm.chord_len - 1) : (x += 1) song.chords[x] = song.chords[x + 1];
    return .none;
}

/// deltmpt (DEL in window 4): delete one tempo-table byte at the cursor.
fn deltmpt(song: *swm.Song, view: *dsp.View) Effect {
    const pos: usize = @as(usize, dsp.tempoStart(song, @min(view.seltemp, max_tempo - 1))) +
        view.temppos +% view.subwpos1[4];
    if (pos >= swm.tempo_len) return .none; // bmi deret2: past the program
    var x: usize = pos; // move [pos+1..last-2] back one (asm runs to page +126)
    while (x < swm.tempo_len - 2) : (x += 1) song.tempo[x] = song.tempo[x + 1];
    return .none;
}

// -- clipboard: copy/cut/paste/transpose (insdelcopy.inc) ---------------------

/// movpfwd (insdelcopy.inc): copy pattern bytes downward. All indices are
/// display-relative (ptnzptr/pattpt1 point at the display top row); the range
/// [stop+1 .. src_end] is copied so that src_end lands at dst_end. stop=-1
/// reproduces the asm's xpostor=$ff wrap (intactpos1==0: copy down to byte 0).
fn movFwd(c: PCtx, src_end: u8, dst_end: u8, stop_at: i16) void {
    var x: i32 = src_end;
    var y: i32 = dst_end;
    while (x > stop_at) : ({
        x -= 1;
        y -= 1;
    }) {
        const si: usize = @as(usize, c.mpos) + @as(usize, @intCast(x));
        const di: usize = @as(usize, c.mpos) + @as(usize, @intCast(y));
        if (si >= c.base.len or di >= c.base.len) break; // page-wrap guard
        c.base[di] = c.base[si];
    }
}

/// movpbwd (insdelcopy.inc): copy pattern bytes forward from src to dst while
/// dst < len_end (lenstor). Safe forward copy: the caller only uses it with
/// dst < src.
fn movBak(c: PCtx, src: u8, dst: u8, len_end: u8) void {
    var x: usize = dst;
    var y: usize = src;
    while (x < len_end and x < c.base.len and y < c.base.len) : ({
        x += 1;
        y += 1;
    }) {
        c.base[x] = c.base[y];
    }
}

/// detmemp-style row walk (commonsubs.detmemp): accumulate the byte size of
/// `rows` consecutive rows starting at absolute index `start` (note / inst /
/// fx / fxvalue structure, like getdelamount). Returns the accumulated byte
/// count; the asm wraps X at the page edge - guarded at data.len here.
fn rowWalk(data: []const u8, start: usize, rows: u8) u8 {
    var x: usize = start;
    var y: u8 = rows;
    while (y != 0) : (y -%= 1) {
        if (x + 3 > data.len) break; // row reads span up to 3 more bytes
        x += rowLenAt(data, x);
    }
    return @intCast(x - start);
}

/// buftopt (pastebuf): copy `n` staged bytes from the pattern buffer into the
/// pattern at display-relative offset ptncurs (absolute mpos + ptncurs).
fn bufToPtn(c: PCtx, view: *const dsp.View, n: u8) void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const ai: usize = @as(usize, c.mpos) + c.x + i;
        if (ai >= c.base.len) break;
        c.base[ai] = view.ptnbuf[i];
    }
}

/// pastadv (pastebuf): auto-advance the cursor below the pasted area, capped
/// at maxadvancesteps rows.
fn pasteAdv(song: *swm.Song, view: *dsp.View) void {
    if (view.autoadv == 0) return; // lda Config.autoadv; beq
    if (view.ptnbuf_len >= maxadvancesteps) return; // cmp #maxadvancesteps; bcs
    var n: u8 = view.ptnbuf_len;
    while (n != 0) : (n -= 1) godownp(song, view);
}

/// copytobuf (insdelcopy.inc): copy pattern data from the cursor position to
/// the buffer. With shift (C= + C second press) it defines the end of the
/// copy area instead (copyends). Returns true when the buffer changed.
fn copyToBuf(song: *swm.Song, view: *dsp.View, shift: bool) bool {
    if (view.followp) return false; // no copying in follow-play mode
    const cc = compcur(song, view);
    if (!cc.inside) return false; // cursor at the endsignal: no process
    if (shift) return copyEnds(song, view);
    const c = pctx(song, view) orelse return false;
    view.copyrow = cc.row; // copy-start row
    view.copyptn = c.ptn; // copy-start pattern
    view.ptnbuf_len = song.ptn_len[c.ptn] -% cc.row; // eor ff; sec; adc ptnlength
    // copypos = ptncurs + ptnMpos (absolute byte index of the cursor)
    const copypos: u8 = c.x +% c.mpos;
    view.copypos = copypos;
    // sizesto = ptnsize - copypos - 1 bytes from the cursor to the endmarker
    const sizesto: u8 = song.ptn_size[c.ptn] -% copypos -% 1;
    var x: usize = 0;
    while (x < sizesto) : (x += 1) {
        const ai: usize = @as(usize, copypos) + x;
        if (ai >= c.base.len) break; // (ptnzptr),y page-wrap guard
        view.ptnbuf[x] = c.base[ai];
    }
    view.ptnbuf_size = @intCast(x); // bufsize = X
    return true;
}

/// copyends (insdelcopy.inc): shift+copy in the same pattern re-defines the
/// buffered area as rows [copyrow .. cursor]. Refused when the cursor pattern
/// differs, when the cursor is above the start row, or when the span covers
/// the whole buffer (cmp seqbufs-style guard). bufflen is INCLUSIVE of the
/// end row: clc/sbc then adc #0 (C=1) gives endrow - startrow + 1, so an
/// equal end yields 1 row (asm comment: end must not equal start).
fn copyEnds(song: *swm.Song, view: *dsp.View) bool {
    const cc = compcur(song, view);
    const t = clampTrack(view.subwpos1[0]);
    const ptn = clampPtn(view.curptn1[t]);
    if (ptn != view.copyptn) return false; // cpy copyptn; bne cendend
    if (cc.row < view.copyrow) return false; // clc; sbc copyrow; bcc
    view.ptnbuf_len = cc.row -% view.copyrow +% 1; // adc #0 (carry set)
    // bufsize = (ptncurs + ptnMpos) - copypos (sec; sbc)
    const cur: u8 = ptnCur(song, view, t) +% ptnMpos(song, view, t);
    view.ptnbuf_size = cur -% view.copypos;
    return true;
}

/// cutandcopy (insdelcopy.inc): copy to buffer, then blank the cut rows.
/// Pattern length stays intact (ptn_len untouched); ptnsize is recomputed so
/// the endmarker follows the blanked area, and copyptn resets so a later
/// shift+copy cannot corrupt the clipboard.
fn cutAndCopy(song: *swm.Song, view: *dsp.View, shift: bool) bool {
    if (view.followp) return false;
    if (!copyToBuf(song, view, shift)) return false; // copy first
    const cc = compcur(song, view);
    if (!cc.inside) return false; // beq cutcend
    saveUndo(song, view);
    const c = pctx(song, view) orelse return false; // pattern 0 read-only
    // ptnsize = ptncurs + ptnMpos + bufflen + 1 (chained adc = exact sum)
    const nsize: u8 = c.x +% c.mpos +% view.ptnbuf_len +% 1;
    song.ptn_size[c.ptn] = nsize;
    // zero bufflen bytes at the cursor, then the $ff endmarker
    var i: usize = @as(usize, c.mpos) + c.x;
    var n: usize = view.ptnbuf_len;
    while (n != 0) : (n -= 1) {
        if (i >= c.base.len) break;
        c.base[i] = 0;
        i += 1;
    }
    if (i < c.base.len) c.base[i] = swm.ptn_end;
    view.copyptn = 0; // stx copyptn (X=0 after the zero loop)
    return true;
}

/// pastebuf (insdelcopy.inc): paste the staged bytes at the cursor. Two cases:
/// - smallpa: the paste ends before the pattern end; the intact tail moves in
///   memory (movpfwd/movpbwd) and the pattern grows by the pasted size.
/// - ovrpast: the paste reaches/exceeds the end; only ptn_len - cursorRow
///   buffer rows are pasted (row-for-row replacement up to the old boundary,
///   xdetlo2 cpy #<cursorRow> stop), the endmarker follows, ptn_len intact.
/// Neither case changes ptn_len (the asm never touches ptnlength here).
fn pasteBuf(song: *swm.Song, view: *dsp.View) bool {
    if (view.followp) return false; // jmp pastend
    const cc = compcur(song, view);
    if (!cc.inside) return false; // beq pastend
    saveUndo(song, view);
    const c = pctx(song, view) orelse return false;
    const r: u8 = cc.row;
    const ovr = @addWithOverflow(r, view.ptnbuf_len);
    if (ovr[1] != 0 or ovr[0] >= song.ptn_len[c.ptn]) {
        return pasteOver(song, view, c, r); // carry or cmp ptnlength; bcs
    }
    // smallpa
    const t = clampTrack(view.subwpos1[0]);
    const endrow: u8 = ovr[0];
    // detmemp(endrow+1): intactpos1 = display-relative byte offset of endrow
    const intact1: u8 = rowWalk(c.base, c.mpos, endrow -% view.prowpos[t]);
    // intactsize = ptnsize - intactpos1 - ptnMpos (sec; sbc; sbc)
    const intactsize: u8 = song.ptn_size[c.ptn] -% intact1 -% c.mpos;
    const pastesize: u8 = view.ptnbuf_size; // bufsize; sta pastesize
    // intactpos2 = pastesize + ptncurs
    const intact2: u8 = pastesize +% c.x;
    // ptnsize = intactpos2 + intactsize (+C) + ptnMpos (+C); guards
    const s1 = @addWithOverflow(intact2, intactsize);
    if (s1[1] != 0) return true; // bcs pastend
    const s2 = @addWithOverflow(s1[0], c.mpos);
    if (s2[1] != 0) return true; // bcs pastend
    if (s2[0] >= swm.ptn_len_max + 1) return true; // cmp #maxptnlen+1; bcs
    song.ptn_size[c.ptn] = s2[0];
    // move the intact area; direction depends on pos1 vs pos2
    if (intact1 != intact2) {
        if (intact1 > intact2) {
            movBak(c, intact1, intact2, intact2 +% intactsize); // movibak
        } else {
            movFwd(c, intact1 +% intactsize, intact2 +% intactsize, intact1 -% 1);
        }
    }
    bufToPtn(c, view, pastesize); // inpaste: buftopt
    pasteAdv(song, view);
    return true;
}

/// ovrpast (pastebuf): paste over the pattern tail. The buffer walk stops at
/// the cursor row (the self-modified `cpy` operand), i.e. it measures the
/// bytes of ptn_len - cursorRow buffer rows - the pasted rows that replace old
/// rows one-for-one up to the old pattern boundary.
fn pasteOver(song: *swm.Song, view: *dsp.View, c: PCtx, r: u8) bool {
    const rows: u8 = song.ptn_len[c.ptn] -% r;
    const pastesize: u8 = rowWalk(view.ptnbuf[0..], 0, rows);
    // ptnsize = ptncurs + ptnMpos + pastesize (+chained carries) + 1
    const a1 = @addWithOverflow(c.x, c.mpos);
    const s2: u16 = @as(u16, a1[0]) + pastesize + a1[1];
    if (s2 > 255) return true; // bcs pastend (9-bit result)
    if (s2 >= swm.ptn_len_max) return true; // cmp #maxptnlen; bcs
    song.ptn_size[c.ptn] = @intCast(s2 + 1); // adc #1 (carry clear here)
    bufToPtn(c, view, pastesize); // buftopt
    // endmarker after the pasted area
    const ei: usize = @as(usize, c.mpos) + c.x + pastesize;
    if (ei < c.base.len) c.base[ei] = swm.ptn_end;
    pasteAdv(song, view);
    return true;
}

/// transptn (insdelcopy.inc): transpose the current pattern from the cursor
/// down. `amount` is the 2's-complement addend. Rows with a NOP ($00/$80) or
/// out-of-range low-7 note byte are left alone; a transposed note is stored
/// only when its low 7 bits stay inside 1..SWM_NOTE_MAX (marker bit kept by
/// the full-byte store). The row walk re-reads the byte to skip inst/fx/value
/// bytes (decidco/nextbyt).
fn transPtn(song: *swm.Song, view: *dsp.View, amount: u8) bool {
    if (view.followp or view.curwind != 0) return false;
    const cc = compcur(song, view);
    if (!cc.inside) return false; // beq tranret
    saveUndo(song, view);
    const c = pctx(song, view) orelse return false; // pattern 0 read-only
    var i: usize = @as(usize, c.mpos) + c.x;
    while (i < c.base.len) {
        const b = c.base[i];
        if (b == swm.ptn_end) break; // reached endsignal
        const lo7 = b & 0x7f;
        if (lo7 != 0 and lo7 <= swm.note_max) {
            const nv = b +% amount; // clc; adc amount
            const nl = nv & 0x7f;
            if (nl >= 1 and nl <= swm.note_max) c.base[i] = nv; // trstore
        }
        // row walk: skip the inst/fx/value bytes of this row
        i += 1;
        if (b & 0x80 != 0) { // inst byte follows
            if (i >= c.base.len) break;
            const inst = c.base[i];
            i += 1;
            if (inst & 0x80 != 0) { // fx byte follows
                if (i >= c.base.len) break;
                const fx = c.base[i];
                i += 1;
                if (fx & 0xe0 == 0) i += 1; // value byte follows
            }
        }
    }
    return true;
}

/// copyseq (insdelcopy.inc): copy the orderlist from the cursor position into
/// the sequence buffer. Refused when the byte before the cursor is $ff (a
/// loop-jump target; idx==0 treats the wrapped prev byte as 0, deviation).
/// With shift it re-defines the buffered span end (exclusive at the cursor;
/// refused if that would leave nothing or cover the whole buffer).
fn copySeq(song: *swm.Song, view: *dsp.View, shift: bool) bool {
    const seq = seqOf(song, view);
    const idx: u8 = seqByte(view);
    const prev: u8 = if (idx == 0) 0 else seq[idx - 1]; // deviation: asm wraps Y
    if (prev == swm.seq_end_loop) return false; // cmp #$ff; beq scpyend
    if (shift) { // scopyends
        if (idx < view.seqbuf_pos) return false; // sec; sbc scopypos; bcc
        const d: u8 = idx -% view.seqbuf_pos;
        if (d >= view.seqbuf_len) return false; // cmp seqbufs; bcs
        view.seqbuf_len = d;
        return true;
    }
    view.seqbuf_pos = idx; // scopypos
    var x: usize = 0;
    var y: usize = idx;
    while (true) {
        const v = seq[y]; // seqaddb
        view.seqbuf[x] = v; // stored even when >= $fe
        if (v >= swm.seq_end_stop) break; // cmp #$fe; bcs: not counted
        x += 1;
        y += 1;
        if (y >= seqlen or x >= view.seqbuf.len) break; // cpy #seqlength; bcc
    }
    view.seqbuf_len = @intCast(x);
    return true;
}

/// pasteseq (insdelcopy.inc): insert the staged sequence bytes at the cursor.
/// Refused when the buffer is empty, when the byte before the cursor is $ff,
/// or when any of the n+1 top slots that the move will crop holds an
/// endsignal ($fe/$ff). The existing data moves forward by n, then the buffer
/// is written into the freed window.
fn pasteSeq(song: *swm.Song, view: *dsp.View) bool {
    const n: usize = view.seqbuf_len;
    if (n == 0) return false; // lda seqbufs; beq
    saveUndo(song, view);
    const seq = seqOf(song, view);
    const idx: usize = seqByte(view);
    const prev: u8 = if (idx == 0) 0 else seq[idx - 1]; // deviation: asm wraps Y
    if (prev == swm.seq_end_loop) return false; // cmp #$ff; beq spstend
    // test loop: seq[x] for x = 126 down to 126-n inclusive (n+1 slots)
    var x: usize = seqlen;
    var y: usize = n;
    while (true) {
        if (seq[x] >= swm.seq_end_stop) return false; // cmp #$fe; bcs
        if (y == 0) break;
        x -= 1;
        y -= 1;
    }
    // move seq[xx] -> seq[xx+n] for xx = 126-n down to idx (spasteS/spasteD)
    var mx: usize = seqlen - n;
    var my: usize = seqlen;
    while (true) {
        seq[my] = seq[mx];
        if (mx == 0) break; // dex -> bmi (cursor position 0 case)
        mx -= 1;
        my -= 1;
        if (mx < idx) break; // cpx spstpos; bcc
    }
    // paste the buffer into the freed window at idx (spastlp/spasteW)
    var i: usize = 0;
    var px: usize = idx;
    while (i < n) : ({
        i += 1;
        px += 1;
    }) {
        if (px >= seq.len) break; // abs,x page-wrap guard (deviation)
        seq[px] = view.seqbuf[i];
    }
    rescanSeq(song, seqIndex(view)); // port convention (asm: seqrefr)
    return true;
}

/// CopyIns (insdelcopy.inc): snapshot the selected instrument (128 bytes).
fn copyIns(song: *swm.Song, view: *dsp.View) bool {
    const inst = clampInst(view.selinst);
    @memcpy(view.instbuf[0..swm.inst_size], song.insts[inst][0..swm.inst_size]);
    return true;
}

/// PasteIn (insdelcopy.inc): restore the buffered instrument over the
/// selected slot.
fn pasteIns(song: *swm.Song, view: *dsp.View) bool {
    saveUndo(song, view); // deviation: always snapshot before mutation
    const inst = clampInst(view.selinst);
    @memcpy(song.insts[inst][0..swm.inst_size], view.instbuf[0..swm.inst_size]);
    return true;
}

/// EmptIns (packdepack.inc): overwrite the selected instrument with the
/// dummy header, zeroed table area and '.' names.
const dummyihdr = [19]u8{
    0x1a, // CONTROL (HR TIMER/HRTYPE/VIBRATO-TYPE/TIED PW-CTF)
    0x0f, 0x00, // >DEFAULTHRADSR,<DEFAULTHRADSR
    0x00, 0xf0, // ADSR on notestart (gate-on)
    0x00, // vibrato freq+amp
    0x00, // vibrato delay / amp-increment speed
    0x00, // arpeggio & chord speed (0=1x)
    0x01, // default chord
    0x00, // octave shift
    0x11, 0x12, // PW / filter table pointers (pulsprog/filtprog offsets)
    0x00, 0x00, 0x00, // gateoff pointers WF/PW/FILT
    0x09, // 1st frame waveform
    0xff, // WF program (hardwired at $10 relative)
    0xff, 0xff, // PW / filter programs
};

fn emptIns(song: *swm.Song, view: *dsp.View) bool {
    saveUndo(song, view); // deviation: always snapshot before mutation
    const inst = clampInst(view.selinst);
    const ins = &song.insts[inst];
    @memcpy(ins[0..dummyihdr.len], dummyihdr[0..]);
    const namepos: usize = swm.inst_size - instnamelength;
    var y: usize = dummyihdr.len; // zero the table area, '.' in the name field
    while (y < swm.inst_size) : (y += 1) ins[y] = if (y < namepos) 0 else '.';
    return true;
}

// == play keys / window switches / +/- (keyhandler.inc) =======================

/// setFlwP (commonsubs.inc): follow-play on when configured default (confbits
/// bit2) or the CBM key is held.
fn setFlwP(song: *const swm.Song, view: *dsp.View, cbm: bool) void {
    _ = song; // confbits is editor config (View), not a tune-header byte
    view.followp = (view.confbits & 0x04 != 0) or cbm;
}

/// chdzero (keyhandler.inc): switch to the chord window and home it.
fn chdzero(view: *dsp.View) void {
    view.curwind = 3;
    view.subwpos1[3] = 0; // tblhome: cht home of window 3
    view.chorpos = 0;
}

/// incOctave/decOctave (commonsubs.inc): jam/typing octave 0..7 (shown +1).
fn incOctave(view: *dsp.View) void {
    if (view.octave < 7) view.octave += 1; // cmp #7; bpl skip
}

fn decOctave(view: *dsp.View) void {
    if (view.octave != 0) view.octave -= 1; // beq keyrett
}

/// noteRep (datawriter.inc noterep): jam the note, then write it into the
/// pattern's note column (refused at the endsignal).
fn noteRep(song: *swm.Song, view: *dsp.View, note: u8) Effect {
    jamming(view, note); // jams even at the endmark
    const cc = compcur(song, view);
    if (!cc.inside) return .none; // beq nonotew
    return noteEntry(song, view, note); // notewri
}

/// f1er: F1 plays the tune from the beginning; shift+F1 (f2er) plays from the
/// orderlist markers. Both reset follow-play first (PlayBeg). The host does
/// the rastime reset / playmod / ptploff when handling the effects.
fn f1er(song: *const swm.Song, view: *const dsp.View, key: Key) Effect {
    _ = song; // confbits lives in the view
    const follow = view.confbits & 0x04 != 0 or key.cbm;
    if (key.shift) return .{ .play_markers = follow }; // f2er: playMrk
    return .{ .play_song = follow }; // PlayBeg
}

/// f3er/f4er: F3 plays the displayed patterns from their beginnings (f3play);
/// shift+F3 (f4er pauseco) stops/continues playback, storing the old mode.
fn f3er(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    setFlwP(song, view, key.cbm); // f3play/pauseco both start with setFlwP
    if (key.shift) return .stop_or_cont;
    return .{ .play_pattern = view.followp };
}

/// f5er: window switcher. cbm: chord table (prevwin remembers where to
/// return); shift: orderlist; plain: pattern window <-> orderlist, and the
/// instrument/chord/tempo windows fall to the pattern window (ptnwsel).
fn f5er(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    _ = song; // window state only
    if (key.cbm) { // swtochd
        view.prevwin = view.curwind;
        view.curwind = 3;
        return .none;
    }
    if (key.shift) { // goorlis
        view.curwind = 1;
        return .none;
    }
    view.curwind = if (view.curwind == 0) 1 else 0; // ptnwsel: beq goorlis
    return .none;
}

/// f7er: menumode closes the menu; cbm: tempo table; shift: open the menu
/// (.menu); plain: instrument window.
fn f7er(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    _ = song; // window/menu state only
    if (view.menumode) {
        view.menumode = false; // inc menu.clearmenu
        view.helpmode = false; // dispmenu: clearing the menu ends help mode
        return .redraw;
    }
    if (key.cbm) { // swtotmp
        view.curwind = 4;
        return .none;
    }
    if (key.shift) { // menuer
        view.menumode = true;
        view.menupoint = 0; // nothing chosen yet
        view.titledi = true; // dispaut: show author/title until the next key
        return .menu;
    }
    view.curwind = 2; // setInsW
    return .none;
}

/// stopper (RUN/STOP): menumode closes the menu; otherwise follow = CBM and
/// jmp f4er (stop/continue).
fn stopper(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    _ = song; // (f4er's setFlwP re-derives follow from confbits + cbm)
    if (view.menumode) {
        view.menumode = false; // inc menu.clearmenu
        view.helpmode = false;
        return .redraw;
    }
    view.followp = key.cbm; // norStop (f4er's setFlwP re-derives it)
    return .stop_or_cont;
}

/// spacer: SPACE. shift: window 0 plays patterns from the cursor, window 1
/// sets the orderlist play markers, window 2 edits the sub-table's gateoff
/// pointer; cbm: window 0 same play, other windows set a per-track marker
/// (trkmark); plain: toggle edit/jam mode.
fn spacer(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) {
        switch (view.curwind) {
            0 => return patPtnMid(song, view, key.cbm), // ptnmidp: f3play
            1 => return olSpace(song, view, key.cbm), // olspace
            2 => {
                gateoffPtr(song, view);
                return .none;
            },
            else => return .none, // keyret3
        }
    }
    if (key.cbm) {
        if (view.curwind == 0) return patPtnMid(song, view, true); // ptnmidp
        // trkmark: marker only on the orderlist cursor's track
        view.olstart[clampTrack(view.subwpos1[1])] = seqByte(view);
        return .none; // inc seqrefr (host playback refresh)
    }
    view.jammode = !view.jammode; // normspc: toggle edit/jam
    return .none;
}

/// ptnmidp (spacer): play the displayed patterns from the cursor position.
/// The host reads prowpos/subwpos3/ptncurs when handling the effect.
fn patPtnMid(song: *swm.Song, view: *dsp.View, cbm: bool) Effect {
    setFlwP(song, view, cbm);
    return .{ .play_pattern = view.followp };
}

/// olspace (spacer shift, window 1): all three orderlist tracks get the play
/// marker at the cursor position. cbm (plymark) needs the player's SEQPOS
/// (host playback state) and is not modelled (deviation).
fn olSpace(song: *swm.Song, view: *dsp.View, cbm: bool) Effect {
    _ = song;
    _ = cbm; // plymark: host-side (player.SEQPOS)
    const idx = seqByte(view); // allmark
    view.olstart[0] = idx;
    view.olstart[1] = idx;
    view.olstart[2] = idx;
    return .none; // inc seqrefr
}

/// gateoffPtr (spacer shift, window 2): store the current table position into
/// the sub-table's gateoff pointer (ins[12/13/14]); pressing again on the
/// pointed cell clears it; pointing elsewhere overwrites it.
fn gateoffPtr(song: *swm.Song, view: *dsp.View) void {
    const w = @min(view.subwpos1[2], 3);
    if (w == 0) return; // main instrument data: nothing
    const cur: u8 = getitbi(song, view); // position of the cell under cursor
    const ins = &song.insts[clampInst(view.selinst)];
    const gi: usize = 11 + @as(usize, w); // $0c-1 + subwindow
    const ptr = ins[gi];
    ins[gi] = if (ptr == 0 or ptr != cur) cur else 0; // icurpst logic
}

/// bckarrow (left-arrow). cbm: toggle follow-play-default (autoFlw, confbits
/// bit2, editor config); shift: toggle follow-play while playing (the asm
/// only toggles during playback; view-only here, deviation); plain:
/// fast-forward while playing (ffwd: PAL gives ffwdspeed+1).
fn bckarrow(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    _ = song; // confbits lives in the view
    if (key.cbm) {
        view.confbits ^= 0x04; // eorconf $04
        return .none;
    }
    if (key.shift) {
        view.followp = !view.followp; // toggflw
        return .none;
    }
    return .{ .fastfwd = ffwdspeed + 1 }; // ffwd (host ignores when stopped)
}

/// incinst (pluser/minuser): instrument number +/-, capped at maxinstamount-1
/// (the last slot is the copy buffer); instinit resets the cursor.
fn instStep(song: *swm.Song, view: *dsp.View, up: bool) Effect {
    _ = song; // selinst lives in the view (asm: absolute page)
    if (up and view.selinst == max_inst) return .none; // cmp #maxinstamount-1
    if (!up and view.selinst == 1) return .none; // cmp #1
    if (up) view.selinst += 1 else view.selinst -= 1;
    instInit(view);
    return .none;
}

/// pluser (+). menumode: menu item edit (Part 4); shift: pattern number up in
/// window 0, else instrument up; cbm: octave up; plain: <3 instrument, 3
/// chord up (+ chdzero), 4 tempo-program up.
fn pluser(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (view.menumode) return menuInc(song, view);
    if (key.shift) {
        if (view.curwind != 0) return instStep(song, view, true); // incinst
        const t = clampTrack(view.subwpos1[0]);
        if (view.curptn1[t] < max_ptn) view.curptn1[t] += 1; // kyrettb
        return .none;
    }
    if (key.cbm) {
        incOctave(view); // C= + plus
        return .none;
    }
    if (view.curwind < 3) return instStep(song, view, true); // defaPlus
    if (view.curwind == 3) { // incchr2
        if (view.selchor != max_chord - 2) {
            view.selchor += 1;
            chdzero(view);
        }
        return .none;
    }
    if (view.seltemp != max_tempo - 2) view.seltemp += 1; // inctmpp
    return .none;
}

/// minuser (-). menumode: menu item edit (Part 4); shift: pattern number down
/// in window 0, else instrument down; cbm: octave down; plain mirrors pluser.
fn minuser(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (view.menumode) return menuDec(song, view);
    if (key.shift) {
        if (view.curwind != 0) return instStep(song, view, false); // decinst
        const t = clampTrack(view.subwpos1[0]);
        if (view.curptn1[t] >= 2) view.curptn1[t] -= 1; // cmp #1+1; bcc
        return .none;
    }
    if (key.cbm) {
        decOctave(view); // C= + minus
        return .none;
    }
    if (view.curwind < 3) return instStep(song, view, false); // defMinu
    if (view.curwind == 3) { // decchor
        if (view.selchor != 1) {
            view.selchor -= 1;
            chdzero(view);
        }
        return .none;
    }
    if (view.seltemp != 1) view.seltemp -= 1; // tkeyer.dectmpp
    return .none;
}

/// equaler (=): negate values. Instrument tables: the 2nd column of the cell
/// under the cursor ($ff row delimiter untouched). Chord table: the value
/// under the cursor ($7e/$7f end signals untouched; >= $80 always negated).
fn equaler(song: *swm.Song, view: *dsp.View) Effect {
    if (view.curwind == 2) { // NegItbl
        const w = @min(view.subwpos1[2], 3);
        if (w == 0) return .none; // main data: nothing
        const pos: usize = getitbi(song, view);
        const ins = &song.insts[clampInst(view.selinst)];
        if (pos >= ins.len or ins[pos] >= 0xff) return .none; // cmp #$ff; bcs
        if (pos + 1 < ins.len) ins[pos + 1] = (ins[pos + 1] ^ 0xff) +% 1; // negate
        return .none; // goirefr refresh
    }
    if (view.curwind == 3) { // NegChrd
        const pos: usize = @as(usize, dsp.chordStart(song, @min(view.selchor, max_chord - 1))) +
            view.chorpos +% view.subwpos1[3];
        if (pos >= swm.chord_len) return .none;
        const v = song.chords[pos];
        if (v < 0x80 and v >= 0x7e) return .none; // cmp #$7e; bcs
        song.chords[pos] = (v ^ 0xff) +% 1; // negate (2's complement)
        return .none;
    }
    return .none; // endequa
}

/// slasher (/) and uparrow (↑): page up/down. The orderlist pages by 4 CURSOR
/// STEPS (right for page-down, left for page-up); other windows page by 8
/// rows, 4 in the instrument table subwindows (>= 2).
fn slasher(song: *swm.Song, view: *dsp.View, up: bool) Effect {
    const w = view.curwind;
    var n: u8 = 8;
    if (w == 2 and view.subwpos1[2] >= 2) n = 4; // short instrument tables
    if (w == 1) { // pageupd: orderlist pages horizontally
        var m: u8 = 4;
        if (up) {
            while (m > 0) : (m -= 1) _ = cursorLeft(song, view, false); // norcrle
        } else {
            while (m > 0) : (m -= 1) _ = cursorRight(song, view); // pgrilp
        }
        return .none;
    }
    if (up) { // pgupper
        if (w == 2 and (view.subwpos1[2] | view.inswYbuf[0]) == 0) return .none;
        while (n > 0) : (n -= 1) _ = norcrup(song, view);
        return .none;
    }
    while (n > 0) : (n -= 1) _ = norcrdn(song, view); // pgdnlop
    return .none;
}

/// jumptoPtn (commonsubs.inc jmptopt): jump to the pattern under the orderlist
/// cursor for track `track`. Refused on a loop position ($ff before), pattern
/// 0, follow-play, or out-of-range numbers; selects the pattern, homes the
/// display and switches to the pattern window (postop2).
fn jumptoPtn(song: *swm.Song, view: *dsp.View, track: u8) void {
    const t: usize = clampTrack(track);
    const si = clampSubt(view.selsubt) * 3 + t;
    const seq = &song.seqs[si];
    const idx: usize = seqByte(view); // getcurptn (same cursor for all tracks)
    const prev: u8 = if (idx == 0) 0 else seq[idx - 1]; // deviation: asm wraps Y
    if (prev == swm.seq_end_loop) return; // cmp #$ff; beq jptret
    const v = seq[idx]; // seqadde
    if (v == 0) return; // pattern 00: no go
    if (view.followp) return; // seleptn: don't disturb pointers
    if (v > max_ptn) return; // cmp #maxptnamount+1; bcs
    view.curptn1[t] = v;
    view.prowpos[t] = 0;
    view.curwind = 0; // postop2
    view.subwpos2[0] = 0;
    view.subwpos3[0] = 0;
}

/// cbmRetu (reter cbmretu): switch to the currently played patterns (player
/// CURPTN, kept in view.played_curptn). Invalid numbers and follow-play are
/// skipped; homes the pattern cursor (postop2).
fn cbmRetu(song: *swm.Song, view: *dsp.View) Effect {
    _ = song;
    for (0..3) |t| {
        const p = view.played_curptn[t];
        if (p == 0 or p > max_ptn) continue; // invptn guards
        if (view.followp) continue;
        view.curptn1[t] = p;
        view.prowpos[t] = 0;
    }
    view.curwind = 0; // postop2
    view.subwpos2[0] = 0;
    view.subwpos3[0] = 0;
    return .none;
}

/// goChrdA (reter): enter the chord editor at chord number `ch` (0 and
/// >= MAXCHORDAMOUNT refused), remembering the current window.
fn goChrdA(song: *swm.Song, view: *dsp.View, ch: u8) Effect {
    _ = song;
    if (ch == 0 or ch >= max_chord) return .none; // retucho
    view.selchor = ch;
    view.prevwin = view.curwind;
    view.curwind = 3;
    chdzero(view);
    return .none;
}

/// caretDown (reter ptCare2): park the pattern cursor in a given column and
/// step one row down.
fn caretDown(song: *swm.Song, view: *dsp.View, col: u8) Effect {
    view.subwpos2[0] = col;
    return norcrdn(song, view);
}

/// retDown (reter carretn/retdown): plain return. In the pattern window's note
/// column it enters a gate-on note ($7d); elsewhere it zeroes the column and
/// steps down; from the chord window it restores prevwin.
fn retDown(song: *swm.Song, view: *dsp.View) Effect {
    const y = view.curwind;
    if (y == 0 and view.subwpos2[0] == 0 and !view.jammode) {
        return noteRep(song, view, 0x7d); // gateon
    }
    // retdown
    if (y == 2) view.inswXbuf[@min(view.subwpos1[2], 3)] = 0; // zero column
    if (y == 3) { // prevwin: back to the window the chord was opened from
        view.curwind = view.prevwin;
        return .none;
    }
    view.subwpos2[y] = 0; // sta subwpos2,y (windows 0/1/4)
    return norcrdn(song, view);
}

/// goInsCh (reter ptnRETU, columns 1-2): return on the instrument column
/// selects the typed instrument (or its chord when the byte encodes one).
fn goInsCh(song: *swm.Song, view: *dsp.View) Effect {
    const t = clampTrack(view.subwpos1[0]);
    const ptn = clampPtn(view.curptn1[t]);
    const base = ptnBase(song, ptn);
    const ai: usize = ptnMpos(song, view, t) + ptnCur(song, view, t);
    const note = if (ai < base.len) base[ai] else swm.ptn_end; // getcurnote
    if (note < 0x80) return .none; // bpl rerete2: no instrument column
    const ins: u8 = (if (ai + 1 < base.len) base[ai + 1] else 0) & 0x7f;
    if (ins == 0) return .none; // rereter: instrument 00
    if (ins <= max_inst) { // goInstA: select the instrument
        view.curwind = 2;
        view.selinst = ins;
        instInit(view);
        return .none;
    }
    if (ins >= 0x70) return goChrdA(song, view, ins -% 0x70); // chGoChd
    return caretDown(song, view, 1); // invalid: park in the inst column
}

/// ptnCaret (reter ptnRETU, columns >= 3): return on a chord-FX column opens
/// the chord editor; other fx park the cursor in the fx column and step down.
fn ptnCaret(song: *swm.Song, view: *dsp.View) Effect {
    const t = clampTrack(view.subwpos1[0]);
    const ptn = clampPtn(view.curptn1[t]);
    const base = ptnBase(song, ptn);
    const ai: usize = ptnMpos(song, view, t) + ptnCur(song, view, t);
    const at = struct {
        fn get(b: []const u8, i: usize) u8 {
            return if (i < b.len) b[i] else swm.ptn_end;
        }
    }.get;
    const note = at(base, ai); // getcurnote
    if (note < 0x80) return .none; // no instrument column
    const inst = at(base, ai + 1);
    if (inst < 0x80) return .none; // no fx column
    const fx = at(base, ai + 2);
    if (fx >= 0x80) return caretDown(song, view, 3); // ptCaret
    if (fx == 0x07) return goChrdA(song, view, at(base, ai + 3)); // bigFX value
    if (fx >= 0x70) return goChrdA(song, view, fx -% 0x70); // small chord FX
    return caretDown(song, view, 3); // sbc #$70; bcc ptCaret
}

/// goPosit (reter): window 0/1 return. Orderlist: jump to the pattern under
/// the cursor (all three tracks with shift, played patterns with cbm).
/// Pattern window: ptninsr.
fn goPosit(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (view.curwind == 1) {
        if (key.shift) {
            jumptoPtn(song, view, 0); // all tracks (always positive for bpl)
            jumptoPtn(song, view, 1);
            jumptoPtn(song, view, 2);
        } else if (key.cbm) {
            return cbmRetu(song, view);
        } else {
            const t = view.subwpos1[1]; // orderlist row (track)
            jumptoPtn(song, view, t);
        }
        view.subwpos1[0] = view.subwpos1[1]; // postopt
        return .none;
    }
    return ptnInsR(song, view, key); // pattern window
}

/// ptnInsR (reter ptninsr): return in the pattern window. shift: carretn;
/// cbm: cbmretu; plain (ptnRETU): gate-off note in the note column, instrument
/// jump on the instrument columns, chord jump / caret on the fx columns.
fn ptnInsR(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) return retDown(song, view); // carretn
    if (key.cbm) return cbmRetu(song, view);
    const x = view.subwpos2[0];
    if (x == 0) { // note column: gate-off
        if (view.jammode) return retDown(song, view);
        return noteRep(song, view, 0x7e); // gateoff
    }
    if (x < 3) return goInsCh(song, view); // instrument columns
    return ptnCaret(song, view); // fx columns
}

/// reter: RETURN. menumode: select the menu point (Part 4). Window >= 2:
/// instrument main-data toggles / chord jump (window 2) or retdown. Windows
/// 0/1: goPosit.
fn reter(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (view.menumode) {
        // menu.menucurpos - firstcpos + 1 -> menu.menupoint, then runmenup
        view.menupoint = view.menucurpos - menu.firstcpos + 1;
        return menuAction(song, view, menu.run(song, view));
    }
    if (view.curwind >= 2) {
        if (view.curwind == 2) return retInst(song, view);
        return retDown(song, view); // windows 3/4: carretn
    }
    return goPosit(song, view, key);
}

/// retInst (reter instrument-window branch): only the main instrument data
/// (subwindow 0) reacts. Columns < 4: plain retdown, or jump to the default
/// chord (row 3, columns 2-3). Columns >= 4 toggle the control byte (rows 0/1)
/// or negate the octave (row >= 2); the asm's vibrato-roll block is
/// unreachable (row 0 is handled by the eor branch first) - kept out.
fn retInst(song: *swm.Song, view: *dsp.View) Effect {
    const w = view.subwpos1[2];
    if (w != 0) return retDown(song, view); // not main data
    const x = view.inswXbuf[0];
    if (x < 4) { // jmpchrd
        if (x < 2) return retDown(song, view); // cmp #2; bmi carretn
        if (view.inswYbuf[0] != 3) return retDown(song, view); // chord row only
        const ch = song.insts[clampInst(view.selinst)][swi_defchord];
        return goChrdA(song, view, ch);
    }
    saveUndo(song, view); // deviation: snapshot before the toggle
    const ins = &song.insts[clampInst(view.selinst)];
    switch (view.inswYbuf[0]) {
        0 => ins[0] ^= 0x08, // control bit3
        1 => ins[0] ^= 0x04, // control bit2
        else => {
            if (ins[9] != 0) ins[9] = 0 -% ins[9]; // negate octave shift
        },
    }
    return .none; // retiwr/goirefr
}

/// findUnused (cbm+E): find the first unused pattern number (highest pattern
/// number used in any orderlist of any subtune, + 1) and type it at the
/// orderlist cursor, inserting a slot at the end signal if needed.
fn findUnused(song: *swm.Song, view: *dsp.View) Effect {
    if (view.curwind != 1) return .none; // dey; bne retEmpt: orderlist only
    var first: u8 = 0; // firstEmptyPtn
    for (0..swm.max_subtune) |st| { // fSeqEmp per subtune
        for (0..3) |tr| {
            const seq = &song.seqs[st * 3 + tr];
            var y: usize = 0;
            while (y < swm.seq_bound) : (y += 1) { // deviation: no page wrap
                const v = seq[y];
                if (v & 0x80 != 0) { // chkEnd: >= $fe ends this orderlist
                    if (v >= swm.seq_end_stop) break;
                    continue; // $80-$fd: never stored (cmpMaxP skipped)
                }
                if (v >= first) first = v; // cmpMaxP
            }
        }
    }
    first +%= 1; // inc firstEmptyPtn
    if (first > max_ptn) return .none; // cmp #maxptnamount+1; bcs
    if (cSeqLop(song, view)) return .none; // loop position under cursor
    const seq = seqOf(song, view);
    const idx: usize = seqByte(view);
    if (seq[idx] >= swm.seq_end_stop) {
        _ = seqInstTrack(song, view, view.subwpos1[1]); // room before $fe
    }
    const idx2: usize = seqByte(view); // getcurptn again
    if (idx2 >= seqlen - 1) return .none; // don't type at the very end
    seq[idx2] = first; // seqaddc
    return .none;
}

// == digit keys (key0sub..key9sub, key1sub) ===================================

/// setmut2 (key1sub): mute/unmute one track (bit0 of mutesolo). d is the
/// track index 0..2.
fn muteKey(view: *dsp.View, d: usize) Effect {
    view.mutesolo[d] ^= 1; // eor #1
    return .redraw; // display.msorefr: mute-colour refresh
}

/// solochn (key0sub shift): toggle between "all unmuted" and "solo current
/// track". solosta is the asm's self-modified flag: 0 = off, 1 = soloed.
fn soloChn(song: *swm.Song, view: *dsp.View) Effect {
    _ = song;
    const on = view.solosta != 0; // ldx solosta; beq -> all $fe
    @memset(&view.mutesolo, if (on) 0xff else 0xfe); // all three tracks
    view.solosta ^= 1; // eor #1
    view.mutesolo[clampTrack(view.subwpos1[0])] = 0xff; // current stays live
    return .redraw; // dAllMut
}

/// key1sub..key9sub / key0sub: hex-digit keys. shift: mute tracks 1..3 (key0
/// solos); cbm: jam/typing octave 1..9 selects octaves 0..8 (the asm allows
/// the 9th press to reach octave 8 - ported verbatim, jam-only in practice);
/// plain: value/note typing via writevalue (NoteOfY).
fn digitKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    const d = digitOf(key.code);
    if (key.shift) {
        if (d == 0) return soloChn(song, view); // key0sub
        if (d <= 3) return muteKey(view, d - 1); // setmute: tracks 1..3
        return .none; // setmute bge nor1key: writevalue refuses shift anyway
    }
    if (key.cbm and d != 0) {
        view.octave = d - 1; // key1sub: sty jamoctave+1
        return .none;
    }
    if (key.cbm) return .none; // cbm+0: writevalue's shift/cbm guard refuses
    return writevalue(song, view, d);
}

/// digitOf: key code -> typed hex digit (0..9); '1'..'9' type 1..9 (key1sub
/// nor1key: iny), '0' types 0 (nor0key). Letters map through their keysub.
fn digitOf(code: u8) u8 {
    return switch (code) {
        k0 => 0,
        k1 => 1,
        k2 => 2,
        k3 => 3,
        k4 => 4,
        k5 => 5,
        k6 => 6,
        k7 => 7,
        k8 => 8,
        k9 => 9,
        else => 0xff,
    };
}

// == letter / symbol key handlers (keysub routines) ===========================

/// keyAsub: shift: autoadvance +1 (cap $0f); cbm: autoadvance -1 (decAdva);
/// plain: writevalue $0A -> note C (writevalue's cpy #$A fixup).
fn aKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) { // autoadv toggle-up
        if (view.autoadv != 0x0f) view.autoadv += 1; // cmp #$0f
        return .none;
    }
    if (key.cbm) return decAdva(view);
    return writevalue(song, view, 0x0a);
}

/// zkeysub.decAdva: decrement autoadvance.
fn decAdva(view: *dsp.View) Effect {
    if (view.autoadv != 0) view.autoadv -= 1;
    return .none;
}

/// keyBsub: cbm: track-binding toggle (confbits bit0); plain: writevalue $0B
/// -> note G. (Shifted keys are refused inside writevalue.)
fn bKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.cbm) {
        view.confbits ^= 0x01; // eorconf $01
        return .none;
    }
    return writevalue(song, view, 0x0b);
}

/// keyCsub: cbm/shift: copy (pattern/orderlist/instrument per window); plain:
/// writevalue $0C -> note E.
fn cKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.cbm or key.shift) {
        switch (view.curwind) { // cpyStrt
            0 => _ = copyToBuf(song, view, key.shift),
            1 => _ = copySeq(song, view, key.shift),
            2 => _ = copyIns(song, view),
            else => {}, // retCkey
        }
        return .none;
    }
    return writevalue(song, view, 0x0c);
}

/// keyDsub: cbm: polyphonic-mode toggle (confbits $08); shift: dovetailing
/// toggle ($10); plain: writevalue $0D -> note E (the asm's cpy #$D inx fixup
/// makes the D key type E although its header says D#; see NOTES.md).
fn dKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.cbm) {
        view.confbits ^= 0x08; // togPoly
        return .none;
    }
    if (key.shift) {
        view.confbits ^= 0x10; // dovetailing
        return .none;
    }
    return writevalue(song, view, 0x0d);
}

/// keyEsub: cbm: findUnused; plain/shift: writevalue $0E -> note E+12 after
/// the cpy #$E ldx #$04 fixup (the E key types D#, see NOTES.md).
fn eKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.cbm) return findUnused(song, view);
    return writevalue(song, view, 0x0e);
}

/// keyFsub: shift: frame-speed down (roll 8->1); cbm: filter-reset toggle
/// (ins[0] bit7); plain: writevalue $0F -> note F (cpy #$F fixup).
fn fKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) {
        view.framesp = if (view.framesp <= 1) pal_max_framesp else view.framesp - 1; // DecFspd
        return .none;
    }
    if (key.cbm) { // PWreset: filter-reset bit of the control byte
        const ins = &song.insts[clampInst(view.selinst)];
        ins[0] ^= 0x80; // instpt1/instpt2 at position 0
        return .none; // instinit.goirefr
    }
    return writevalue(song, view, 0x0f);
}

/// gkeysub: shift: frame-speed up (roll to 1 past PALmaxframespeed); plain:
/// note F# (norGkey, unchanged by cbm).
fn gKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) {
        view.framesp = if (view.framesp >= pal_max_framesp) 1 else view.framesp + 1; // IncFspd
        return .none;
    }
    return notecol(song, view, 0 + 7);
}

/// hkeysub: shift: highlight step down (min 1); plain: note G#.
fn hKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) {
        if (view.stptick > 1) {
            view.stptick -= 1; // cmp #1; beq retpnt2
            return .redraw; // hilrefr
        }
        return .none;
    }
    return notecol(song, view, 0 + 9);
}

/// ikeysub: shift: instrument auto-append toggle (confbits $80) + full
/// mute-colour refresh; plain: note C in the 2nd upper octave.
fn iKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) {
        view.confbits ^= 0x80; // toggIns: eorconf $80
        return .redraw; // dAllMut
    }
    return notecol(song, view, 12 + 12 + 1);
}

/// jkeysub: shift: highlight step up (max $10); plain: note A#.
fn jKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) {
        if (view.stptick != 0x10) {
            view.stptick += 1; // cmp #$10; beq nothinc
            return .redraw; // hilrefr
        }
        return .none;
    }
    return notecol(song, view, 0 + 11);
}

/// kkeyer: cbm: chord table (swtochd); shift: chord number down (decchor);
/// plain: nothing in the default layout (keyretk).
fn kKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.cbm) return f5er(song, view, .{ .code = f5, .cbm = true }); // swtochd
    if (key.shift) { // decchor
        if (view.selchor != 1) {
            view.selchor -= 1;
            chdzero(view);
        }
        return .none;
    }
    return .none;
}

/// lkeysub: shift: chord number up (incchr2, cap MAXCHORDAMOUNT-2); plain:
/// note C# in the upper octave.
fn lKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) {
        if (view.selchor != max_chord - 2) { // cmp #MAXCHORDAMOUNT-2
            view.selchor += 1;
            chdzero(view);
        }
        return .none;
    }
    return notecol(song, view, 12 + 2);
}

/// mkeysub: plain path for every modifier in the default layout: note H (B).
fn mKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    _ = key;
    return notecol(song, view, 0 + 12);
}

/// nkeysub: shift: instrument-name typing mode; cbm: chord table note-mode
/// display toggle (confbits $40); plain: note A.
fn nKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) return nametypeEnter(song, view); // InsName
    if (key.cbm) {
        view.confbits ^= 0x40; // chord note/number mode
        return .none;
    }
    return notecol(song, view, 0 + 10);
}

/// okeysub: note D in the 2nd upper octave (no modifiers).
fn oKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    _ = key;
    return notecol(song, view, 12 + 12 + 3);
}

/// pkeysub: cbm: pulse-reset toggle (ins[0] bit6); shift: autoportamento FX
/// in the pattern window, else the pulsewidth table; plain: note E 2nd upper.
fn pKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.cbm) {
        const ins = &song.insts[clampInst(view.selinst)];
        ins[0] ^= 0x40; // PWreset: pulse-reset bit of the control byte
        return .none; // instinit.goirefr
    }
    if (key.shift) {
        if (view.curwind != 0) { // goPulWi: pulsewidth table
            view.curwind = 2;
            view.subwpos1[2] = 2;
            return .none;
        }
        return notecol(song, view, portam_fx);
    }
    return notecol(song, view, 12 + 12 + 5);
}

/// qkeysub: shift: transpose -1; cbm: transpose -12 ($f4); plain: note C
/// upper octave.
fn qKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) return transKey(song, view, 0xff); // transdn
    if (key.cbm) return transKey(song, view, 0xf4); // a whole octave down
    return notecol(song, view, 12 + 1);
}

/// rkeysub: shift: RING-BIT ON FX; cbm: RING-BIT OFF FX; plain: note F upper.
fn rKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) return notecol(song, view, ringon_fx); // wrRing
    if (key.cbm) return notecol(song, view, ringoff_fx);
    return notecol(song, view, 12 + 6);
}

/// skeysub: shift: SYNC-BIT ON FX in the pattern window, else the main
/// instrument panel; cbm: SYNC-BIT OFF FX; plain: note C#.
fn sKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) {
        if (view.curwind != 0) { // main instrument-setting panel
            view.curwind = 2;
            view.subwpos1[2] = 0;
            return .none;
        }
        return notecol(song, view, syncon_fx); // wrSync
    }
    if (key.cbm) return notecol(song, view, syncoff_fx);
    return notecol(song, view, 0 + 2);
}

/// tkeyer: cbm: toggle the subtune's funktempo (tempo1 bit7); shift: tempo
/// program number down (dectmpp); plain: note G upper.
fn tKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.cbm) {
        const st = clampSubt(view.selsubt);
        song.funk[st][0] ^= 0x80; // eor #$80, setstm2 store
        return .none;
    }
    if (key.shift) return tmpStepDown(view);
    return notecol(song, view, 12 + 8);
}

/// ykeysub.inctmpp: tempo program number up (cap MAXTEMPOPRAMOUNT-2) + jump
/// to the tempo table (tmpzero).
fn tmpStepUp(view: *dsp.View) Effect {
    if (view.seltemp != max_tempo - 2) view.seltemp += 1; // cmp #$3e
    tmpzero(view);
    return .none;
}

/// tkeyer.dectmpp: tempo program number down (floor 1) + tmpzero.
fn tmpStepDown(view: *dsp.View) Effect {
    if (view.seltemp != 1) view.seltemp -= 1; // cmp #1
    tmpzero(view);
    return .none;
}

/// tmpzero (keyhandler): jump to the tempo window, homed.
fn tmpzero(view: *dsp.View) void {
    view.curwind = 4; // tblhome with window 4
    view.subwpos1[4] = 0;
    view.temppos = 0;
}

/// ukeysub: note H (B) in the upper octave (no modifiers).
fn uKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    _ = key;
    return notecol(song, view, 12 + 12);
}

/// vkeysub: cbm: paste (pattern/orderlist/instrument per window); shift:
/// vibrato FX into the note column; plain: note F.
fn vKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.cbm) return pasteV(song, view);
    if (key.shift) return notecol(song, view, 0x66); // Vibrato (amplitude 6)
    return notecol(song, view, 0 + 6);
}

/// vkeysub.paste: paste per window.
fn pasteV(song: *swm.Song, view: *dsp.View) Effect {
    switch (view.curwind) {
        0 => _ = pasteBuf(song, view),
        1 => _ = pasteSeq(song, view),
        2 => _ = pasteIns(song, view),
        else => {}, // vkeyret
    }
    return .none;
}

/// wkeysub: shift: transpose +1 in the pattern window, else the waveform
/// table; cbm: transpose +12; plain: note D upper.
fn wKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) {
        if (view.curwind != 0) { // goWfTab: waveform/arp table
            view.curwind = 2;
            view.subwpos1[2] = 1;
            return .none;
        }
        return transKey(song, view, 1); // transup
    }
    if (key.cbm) return transKey(song, view, 12); // an octave up
    return notecol(song, view, 12 + 3);
}

/// transKey: transpose the current pattern (transptn refuses non-pattern
/// windows / follow-play itself; the keysub's SaveUndo happens inside).
fn transKey(song: *swm.Song, view: *dsp.View, amount: u8) Effect {
    _ = transPtn(song, view, amount);
    return .none;
}

/// xkeysub: cbm: cut (pattern) / copy+empty (instrument); plain: note D.
fn xKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.cbm) { // CbmXkey
        saveUndo(song, view);
        switch (view.curwind) {
            0 => _ = cutAndCopy(song, view, false),
            2 => { // cut instrument: copy to buffer, then create empty one
                _ = copyIns(song, view);
                _ = emptIns(song, view);
                instInit(view); // commonsubs.instinit
            },
            else => {}, // zkeyret (orderlist has no cut)
        }
        return .none;
    }
    return notecol(song, view, 0 + 3);
}

/// ykeysub: shift: tempo program number up; plain: note A upper.
fn yKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) return tmpStepUp(view);
    return notecol(song, view, 12 + 10);
}

/// zkeysub: cbm: undo; shift: autoadvance -1; plain: note C.
fn zKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.cbm) {
        doUndo(song, view); // Undo
        return .none;
    }
    if (key.shift) return decAdva(view);
    return notecol(song, view, 0 + 1);
}

/// atkeysub: note F in the 2nd upper octave (no modifiers).
fn atKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    _ = key;
    return notecol(song, view, 12 + 12 + 6);
}

/// asterisk: note G in the 2nd upper octave (no modifiers).
fn starKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    _ = key;
    return notecol(song, view, 12 + 12 + 8);
}

/// dotter: shift: subtune tempo1 up (low 6 bits != $3f gate); cbm: next
/// subtune (incSubt); plain: note D upper (normDot).
fn dotKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) { // defaDot
        const st = clampSubt(view.selsubt);
        const v = song.funk[st][0];
        if (v & 0x3f != 0x3f) song.funk[st][0] +%= 1; // and #$3f; cmp #$3f
        return .none;
    }
    if (key.cbm) return incSubt(view); // incSubt
    return notecol(song, view, 12 + 3);
}

/// coloner: shift: subtune funktempo2 down (needs tempo1 bit7 clear =
/// funktempo mode; refuses removing the $80 rest-flag); plain: note E upper.
fn colonKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) { // decrement the right funktempo
        const st = clampSubt(view.selsubt);
        if (song.funk[st][0] & 0x80 == 0) return .none; // bmi retpnts
        const v = song.funk[st][1];
        if (v == 0x80) return .none; // bvs: $80-1 would lose the end-flag
        song.funk[st][1] = v -% 1; // setstmp
        return .none;
    }
    return notecol(song, view, 12 + 5);
}

/// semicol: shift: subtune funktempo2 up (needs funktempo mode; cap < $c0);
/// plain: nothing in the default layout (norScol: bvc retpnts).
fn semicKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) {
        const st = clampSubt(view.selsubt);
        if (song.funk[st][0] & 0x80 == 0) return .none; // bmi retpnts
        const v = song.funk[st][1] +% 1;
        if (v >= 0xc0) return .none; // cmp #$c0; bcs
        song.funk[st][1] = v; // setstmp
        return .none;
    }
    return .none;
}

/// commasub: shift: subtune tempo1 down (refuses 0 and the $80 flag edge);
/// cbm: previous subtune (decSubt); plain: note C upper (norComma).
fn commaKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (key.shift) { // defComa
        const st = clampSubt(view.selsubt);
        const v = song.funk[st][0];
        if (v == 0 or v == 0x80) return .none; // bcc / bvs
        song.funk[st][0] = v -% 1; // setstm2
        return .none;
    }
    if (key.cbm) return decSubt(view);
    return notecol(song, view, 12 + 1);
}

/// dotter.incSubt: next subtune (capped at maxsubtuneamount). The asm then
/// jumps to playadapter.resetune - the host restarts playback from the new
/// subtune when playing (Effect.none, comment deviation).
fn incSubt(view: *dsp.View) Effect {
    if (view.selsubt != max_subt) view.selsubt += 1; // cmp #maxsubtuneamount
    return .none; // host: playadapter.resetune
}

/// commasub.decSubt: previous subtune (floor 0); host resetune as above.
fn decSubt(view: *dsp.View) Effect {
    if (view.selsubt != 0) view.selsubt -= 1; // beq retpntQ
    return .none; // host: playadapter.resetune
}

// == name-typing mode (nkeysub.InsName + menu.nametyper/typefld) ==============

/// nkeysub.InsName: enter instrument-name typing mode. The name is staged in
/// view.namebuf (the asm types into a screen field); RETURN stores it, RUN/
/// STOP escapes (deviation: both commit nothing until RETURN).
fn nametypeEnter(song: *swm.Song, view: *dsp.View) Effect {
    view.namemode = true; // inc namemode
    const inst = clampInst(view.selinst);
    @memcpy(&view.namebuf, song.insts[inst][120..128]); // setyfl2 field
    view.inamepos = 0; // setyfl2: compzvar2 reset
    saveUndo(song, view); // UndoType=2 + SavInsU
    return .nametype;
}

/// menu.nametyper: one key in name mode. Char comes from keychar[code];
/// RETURN stores, RUN/STOP/F7/backarrow escape, HOME homes the cursor,
/// insert/backspace/cursor keys edit, everything else is typed.
fn nameTypeKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    const ch = keychar[key.code];
    if (ch == 0) return .none; // no process (C= key etc.)
    const len: usize = instnamelength - 1; // compzvar4
    if (ch >= 0xfe) { // stop/esc or RETURN
        if (ch == 0xff) { // RETURN: storina - copy the field to the instrument
            const inst = clampInst(view.selinst);
            @memcpy(song.insts[inst][120..128], &view.namebuf);
        }
        view.namemode = false; // escape without saving otherwise
        return .redraw; // insrefr: display the (original) name again
    }
    switch (ch) {
        0xf5 => view.inamepos = 0, // HOME: cursor to the field start
        0xf7 => insertChar(view, len), // insert (pound / shift+backspace)
        0xfd => { // backspace; shift falls into the insert branch
            if (key.shift) {
                insertChar(view, len);
            } else {
                backspaceChar(view, len);
            }
        },
        0xfc => { // cursor sideways: shift left, plain right
            if (key.shift) {
                if (view.inamepos > 0) view.inamepos -= 1; // fcurbwd
            } else {
                if (view.inamepos < len) view.inamepos += 1; // fcurfwd
            }
        },
        else => { // normal character (norchar refuses >= $80 control signs)
            if (ch < 0x80) {
                view.namebuf[view.inamepos] = ch;
                if (view.inamepos < len) view.inamepos += 1; // fcurfwd
            }
        },
    }
    return .none;
}

/// typefld insert: shift [pos..len-1] right one and write a space at pos.
fn insertChar(view: *dsp.View, len: usize) void {
    var y: usize = len;
    while (y != view.inamepos) : (y -= 1) view.namebuf[y] = view.namebuf[y - 1];
    view.namebuf[view.inamepos] = ' ';
}

/// typefld backspace: cursor back, then shift [pos+1..len] left and blank the
/// tail position.
fn backspaceChar(view: *dsp.View, len: usize) void {
    if (view.inamepos > 0) view.inamepos -= 1; // fcurbwd
    var y: usize = view.inamepos;
    while (y != len) : (y += 1) view.namebuf[y] = view.namebuf[y + 1];
    view.namebuf[len] = ' ';
}

// == Part 4: the main menu (menu.zig) =========================================

/// menuAction: turn a menu row's Action into a host Effect. The four file
/// rows start the filer immediately (menu.inc filedialog), so the host only
/// sees the dialog's own listing/load/save requests.
fn menuAction(song: *swm.Song, view: *dsp.View, a: menu.Action) Effect {
    return switch (a) {
        .none => .none,
        .redraw, .close_redraw => .redraw,
        .save_tune => openFiler(song, view, .tune, .save),
        .load_tune => openFiler(song, view, .tune, .load),
        .save_inst => openFiler(song, view, .instrument, .save),
        .load_inst => openFiler(song, view, .instrument, .load),
        .save_config => openFiler(song, view, .config, .save),
    };
}

fn fileKind(k: filer.Kind) FileKind {
    return switch (k) {
        .tune => .tune,
        .instrument => .instrument,
        .config => .config,
    };
}

/// filedialog: open the dialog. A load always wants the directory; a save only
/// when confbits2 bit0 (Save_AutoDiskDir) is set. Only the tune saver enables
/// author-info editing (menu.inc savetun `inc editauth`).
fn openFiler(song: *swm.Song, view: *dsp.View, kind: FileKind, mode: filer.Mode) Effect {
    const fk: filer.Kind = switch (kind) {
        .tune => .tune,
        .instrument => .instrument,
        .config => .config,
    };
    const editauth = kind == .tune and mode == .save;
    const auto_dir = (view.confbits2 & 0x01) != 0;
    const author = song.header[swm.H_AUTHOR .. swm.H_AUTHOR + filer.author_len];
    const a = filer.begin(&view.filer, fk, mode, editauth, auto_dir, author);
    return switch (a) {
        .none => .redraw, // save without auto-dir: the name typer opens
        else => filerAction(song, view, a),
    };
}

/// regauth: the author-info typer writes back into the tune header (only when
/// editauth is on, i.e. saving a tune).
fn regAuth(song: *swm.Song, view: *dsp.View) void {
    if (!view.filer.editauth) return;
    @memcpy(song.header[swm.H_AUTHOR..][0..filer.author_len], &view.filer.author);
}

/// Translate the filer's Action into the host Effect. The load/save payload
/// carries the kind so the host knows which reader/writer to use.
fn filerAction(song: *swm.Song, view: *dsp.View, a: filer.Action) Effect {
    return switch (a) {
        .none => .none,
        .redraw => .redraw,
        .need_listing => .need_listing,
        .close => blk: {
            regAuth(song, view); // STOP also registers the author text
            break :blk .close_filer;
        },
        .load => |name| .{ .load_file = .{ .kind = fileKind(view.filer.kind), .name = name } },
        .save => |name| blk: {
            regAuth(song, view);
            break :blk .{ .save_file = .{ .kind = fileKind(view.filer.kind), .name = name } };
        },
    };
}

/// keychar (menu.inc) -> the filer's key vocabulary. $f6 (shift) and 0 never
/// reach the filer; the remaining control signs are filenamer's dispatch.
fn filerKeyOf(key: Key) filer.Key {
    return switch (keychar[key.code]) {
        0, 0xf6 => .none,
        0xfa => .tab,
        0xfb => .down,
        0xfc => .right,
        0xfd => .backspace,
        0xf5 => .home,
        0xf7 => .insert,
        0xf8 => .dir,
        0xf9 => .page,
        0xfe => .stop,
        0xff => .ret,
        else => |ch| .{ .char = ch },
    };
}

/// filenamer: every key while the dialog is open. keys.zig only translates;
/// the state machine lives in filer.zig.
fn filerKey(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    view.titledi = false;
    return filerAction(song, view, filer.key(&view.filer, filerKeyOf(key), key.shift));
}

/// The host's directory listing for the pending need_listing request.
pub fn filerListing(view: *dsp.View, entries: []const filer.Entry, more: bool) void {
    filer.setListing(&view.filer, entries, more);
}

/// The host's load/save result: records the error status (fnotfnd/saverror)
/// and leaves the dialog closed (the original returns to the menu/editor).
pub fn filerResult(view: *dsp.View, ok: bool) void {
    filer.finish(&view.filer, ok);
}

/// YesOrNo (menu.inc): while a kill item waits for an answer only Y/I (yes)
/// and N/V (no) do anything; everything else keeps waiting.
fn menuPrompt(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    const accept = key.code == y_ or key.code == i_;
    const reject = key.code == n_ or key.code == v_;
    if (!accept and !reject) return .none;
    return menuAction(song, view, menu.resolvePrompt(song, view, accept));
}

/// menu.menuinc: `+`/cursor-right on a menu row. Rows without their own
/// editor fall through to pluser.incinst (instrument select).
fn menuInc(song: *swm.Song, view: *dsp.View) Effect {
    if (menu.inc(song, view)) return .redraw;
    return instStep(song, view, true); // keyhandler.pluser.incinst
}

/// menu.menudec: `-`/cursor-left on a menu row, else minuser.decinst.
fn menuDec(song: *swm.Song, view: *dsp.View) Effect {
    if (menu.dec(song, view)) return .redraw;
    return instStep(song, view, false); // keyhandler.minuser.decinst
}

// == keyhandler entry point ===================================================

/// menukeys (keyhandler.inc): the key codes allowed while menumode is set
/// (stored as code*2, because the keyer's jump-table index is code*2).
const menukeys = [_]u8{
    ret_ * 2,   f7 * 2, crsr_d * 2,    stop * 2,  plus * 2, minus * 2,
    f1 * 2,     f3 * 2, backarrow * 2, slash * 2, home * 2, uparr * 2,
    crsr_r * 2,
};

/// keyhandler.keyer + keyjmp: the keyboard entry point. Name-typing mode
/// routes every key to menu.nametyper; the menu only lets its own keys
/// through; everything else jumps through the keyjmp table (codes 15/52/61
/// are the shift/C= keys themselves - morekey, a no-op here).
pub fn handle(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    if (view.filer.open) return filerKey(song, view, key); // filenamer
    if (view.menuprompt != menu.prompt_none) return menuPrompt(song, view, key); // RyouSur/YesOrNo
    if (view.namemode) return nameTypeKey(song, view, key); // menu.nametyper
    if (view.menumode) {
        const code: u8 = @as(u8, key.code) * 2;
        var allowed = false;
        for (menukeys) |m| {
            if (m == code) {
                allowed = true;
                break;
            }
        }
        if (!allowed) return .none;
    }
    view.titledi = false; // keyer: author-info/title display off when any key pressed
    return dispatch(song, view, key);
}

/// keyjmp (keyhandler.inc): one handler per matrix code, rows 0..7.
fn dispatch(song: *swm.Song, view: *dsp.View, key: Key) Effect {
    return switch (key.code) {
        del => deleter(song, view, key),
        ret_ => reter(song, view, key),
        crsr_r => cursori(song, view, key),
        f7 => f7er(song, view, key),
        f1 => f1er(song, view, key),
        f3 => f3er(song, view, key),
        f5 => f5er(song, view, key),
        crsr_d => cursrdn(song, view, key),
        k3, k4, k5, k6, k7, k8, k9, k0, k1, k2 => digitKey(song, view, key),
        w_ => wKey(song, view, key),
        a_ => aKey(song, view, key),
        z_ => zKey(song, view, key),
        s_ => sKey(song, view, key),
        e_ => eKey(song, view, key),
        r_ => rKey(song, view, key),
        d_ => dKey(song, view, key),
        c_ => cKey(song, view, key),
        f_ => fKey(song, view, key),
        t_ => tKey(song, view, key),
        x_ => xKey(song, view, key),
        y_ => yKey(song, view, key),
        g_ => gKey(song, view, key),
        b_ => bKey(song, view, key),
        h_ => hKey(song, view, key),
        u_ => uKey(song, view, key),
        v_ => vKey(song, view, key),
        i_ => iKey(song, view, key),
        j_ => jKey(song, view, key),
        m_ => mKey(song, view, key),
        k_ => kKey(song, view, key),
        o_ => oKey(song, view, key),
        n_ => nKey(song, view, key),
        plus => pluser(song, view, key),
        p_ => pKey(song, view, key),
        l_ => lKey(song, view, key),
        minus => minuser(song, view, key),
        dot => dotKey(song, view, key),
        colon => colonKey(song, view, key),
        at_ => atKey(song, view, key),
        comma => commaKey(song, view, key),
        pound => inskeye(song, view, key.cbm),
        star => starKey(song, view, key),
        semic => semicKey(song, view, key),
        home => homer(song, view, key),
        equal_ => equaler(song, view),
        uparr => slasher(song, view, true), // slasher.uparrow: page-up only
        slash => slasher(song, view, key.shift),
        backarrow => bckarrow(song, view, key),
        ctrl => ctrler(song, view, key),
        space => spacer(song, view, key),
        q_ => qKey(song, view, key),
        stop => stopper(song, view, key),
        else => .none, // morekey: lshift/rshift/C= (codes 15/52/61)
    };
}

// == chord-table note entry (datawriter.chwrchw notemod) ======================

/// notecol in the chord window with confbits bit6 (note-mode display): jam
/// the note, then store it as an offset from view.basnote. Values $7e/$7f
/// (the chord end signals) are refused when the result is positive; a
/// negative result (bit7 set) writes as-is. Autoadvance moves to the next
/// chord row (nextrow: column 0 + norcrdn).
fn chordNoteEntry(song: *swm.Song, view: *dsp.View, note: u8) void {
    const pos: usize = @as(usize, dsp.chordStart(song, @min(view.selchor, max_chord - 1))) +
        view.chorpos +% view.subwpos1[3];
    jamming(view, note); // notemod jams even if the write is refused
    if (pos >= swm.chord_len) return; // getctpos: past the table
    const n = calcoct(view, note) orelse return; // ChrdNot: bcs noctwr
    const off = n -% view.basnote; // sec; sbc BasNote
    if (off < 0x7e or off >= 0x80) song.chords[pos] = off; // wrinote
    if (view.autoadv != 0) { // nextrow
        view.subwpos2[3] = 0;
        _ = norcrdn(song, view);
    }
}
