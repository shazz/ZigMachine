// --------------------------------------------------------------------------
// swm.zig — SID-Wizard Module (.SWM v1.0) tune container, native port
// (Part 1 of the SID-Wizard 1.97 editor port: the song data model and its
// file format; a later part builds the editor around it.)
//
// What lives here, in the terms the SWM-spec.src / packdepack.inc / SWMconvert.c
// sources use:
//
//   * load:   the backwards reader `ProcessSWMver1` (SWMconvert.c) + the
//             backwards depacker `depackt/depkinsch/depkptseq` (packdepack.inc).
//             Loads [2-byte loadaddr][64-byte TUNEHEADER][packed stream] into
//             the expanded form the editor keeps in C64 memory.
//   * save:   the forward packer `packtun` (packdepack.inc), including the
//             recompute of the header's five counts the packer rewrites.
//   * toC64:  the editor's workfile layout (settings.cfg, COMPILEDAPP==1 and
//             SID_AMOUNT==1) at a fixed MUSICDATA base, with the derived
//             pointer tables and pattern-length caches filled in.
//   * fromC64: reads that same layout back into a Song.
//
// No allocator, no global state. A Song is ~33.5 kB of plain arrays, passed
// in and out of every function. Sizes and offsets stay free-running u32
// arithmetic until they are written as C64 bytes.
// --------------------------------------------------------------------------

const std = @import("std");

// -- limits (SWM-spec.src; the COMPILEDAPP==1 / SID_AMOUNT==1 build) ---------
pub const max_subtune = 8; // (maxsubtuneamount 7 counted from 0, +1 for the table)
pub const seq_slots = max_subtune * 3; // 24 orderlists: 3 tracks per subtune
pub const seq_bound = 128; // seqbound: one sequence's storage slot
pub const seq_len_max = 126; // seqlength: max bytes scanned before the safety $FE
pub const ptn_count = 100; // maxptnamount: patterns 1..100 (pattern 0 is the dummy)
pub const ptn_bound = 256; // PTNBOUND: one pattern's storage slot
pub const ptn_len_max = 250 - 1; // maxptnlen: max pattern size before the $FF delimiter
pub const inst_count = 36; // maxinstamount-1: instruments 1..36 get streamed
pub const inst_size = 128; // maxinstsize: one instrument slot
pub const name_len = 8; // instnamelength
pub const inst_usable = 120; // maxinstsize-instnamelength: data 0..119, name at 120..127
pub const inst_empty_size = 18; // (enddummyih-dummyihdr)-1: the dummy instrument's $FF position
pub const inst_low_lim = 15; // the $FF search never looks below here (packinst)
pub const chord_len = 256; // ChordTableLen: chords[0] is the dummy NOP chord
pub const max_chord = 32; // MAXCHORDAMOUNT (pointer-table entries including dummy 0)
pub const max_tempopg = 64; // MAXTEMPOPRAMOUNT (same)
pub const tempotbl_len = 128; // TempoTableLen: the C64's whole tempo area on one page
pub const tempo_len = tempotbl_len - (2 + 2 * 3) - 1; // RESTEMP+1.. 119 bytes the packer saves
pub const default_ptn_len = 32; // DEFAULTPTNLEN for patterns not referenced by any sequence
pub const default_funk = [2]u8{ 0x86, 0x83 }; // defsubtempo1/2 (settings.cfg)
pub const header_size = 64; // tuneheadersize

// header byte positions (SWM-spec.src)
pub const H_ID = 0; // 0..3 "SWM1"
pub const H_FSPEED = 4;
pub const H_HILI = 5;
pub const H_AUTO = 6;
pub const H_CBIT = 7;
pub const H_MUTE = 8; // 8..0xA
pub const H_DEFLEN = 11;
pub const H_SEQAMO = 12;
pub const H_PTAMOU = 13;
pub const H_INSTAM = 14;
pub const H_CHRDLE = 15;
pub const H_TMPLEN = 16;
pub const H_HILI2 = 21; // SID2's (2SID builds put the highlight here)
pub const H_AUTHOR = 24; // 24..63 author-info

// pattern data special values (SWM-spec.src)
pub const packed_min = 0x70; // PACKEDMIN: a marker for two NOP rows
pub const packed_max = 0x77; // PACKEDMAX: a marker for nine (v-$6E) NOP rows
pub const note_max = 0x5f; // SWM_NOTE_MAX; note-column effects live above this
pub const seq_end_stop = 0xFE; // orderlist: absolute end of sequence
pub const seq_end_loop = 0xFF; // orderlist: loop command, one address byte follows
pub const ptn_end = 0xFF; // pattern end delimiter
pub const chord_end1 = 0x7E; // chord delimiters $7e/$7f
pub const chord_end2 = 0x7F;
pub const tempo_end = 0x80; // hardwired empty delimiter (any byte with bit7 ends a program)

// -- the canonical memory image ---------------------------------------------
// The buyer of toC64() gets the editor's workfile at a fixed base, so a
// Zig-built tune is always at the same place (real SWM files' load addresses
// vary, e.g. $1F10..$2050, because that is where each build's editor put it).
// D6 (sidwizard_z): the base is $1DBB, MUSICDATA of the real 1.97 editor build (64tass label
// listing of SID-Wizard.cmp; the player's code reads its tables at these ABSOLUTE addresses).
// The pattern and instrument areas are page-aligned in ABSOLUTE space, so their offsets
// depend on the base (the first port assumed $1D00 and was off by $BB).
pub const music_data = 0x1DBB;
fn alignUp(abs: usize) usize {
    return ((abs + ptn_bound) / ptn_bound) * ptn_bound;
}

pub const o_subtunes = 0;
pub const pptrlo_n = ptn_count + 1; // 101 pointers, pattern 0 dummy included
pub const o_pptrlo = o_subtunes + 8 * max_subtune; // 64
pub const o_pptrhi = o_pptrlo + pptrlo_n; // 165
pub const o_insptlo = o_pptrhi + pptrlo_n; // 266
pub const o_inspt_n = inst_count + 2; // 38: dummy 0 + copy buffer
pub const o_inspthi = o_insptlo + o_inspt_n; // 304
pub const o_chdptrlo = o_inspthi + o_inspt_n; // 342
pub const o_chdptr_n = max_chord + 1; // 33
pub const o_temptrlo = o_chdptrlo + o_chdptr_n; // 375
pub const o_temptr_n = max_tempopg + 1; // 65
pub const o_ptnlength = o_temptrlo + o_temptr_n; // 440
pub const o_ptnsize = o_ptnlength + pptrlo_n; // 541
pub const o_tuneheader = o_ptnsize + pptrlo_n; // 642
pub const o_sequences = o_tuneheader + header_size; // 706
pub const sequences_len = seq_slots * seq_bound; // 3072
pub const o_patterns = o_sequences + sequences_len; // 3778 (PTN0 lives here, 2 bytes)
pub const o_ptn0 = o_patterns;
pub const o_restptn = alignUp(music_data + o_ptn0 + 2) - music_data; // $2D00 absolute
pub const o_instruments = alignUp(music_data + o_restptn + (ptn_count - 1) * ptn_bound) - music_data; // $9100
pub const o_endinstrum = o_instruments + inst_count * inst_size; // 34048
pub const o_chords = o_endinstrum; // CHORDS=endinstrum+0
pub const o_tempotbl = o_chords + chord_len; // 34304
pub const o_resemp = o_tempotbl + (2 + 2 * 3); // 34312 (rest-tempo words, 1SID)
pub const o_endoftune = o_tempotbl + tempotbl_len; // 34432 ($8680; endoftune in settings.cfg)
pub const music_len = o_endoftune;

// -- the song ---------------------------------------------------------------
/// The expanded (depacked) form the editor keeps: exactly what depackt lands
/// in C64 memory, reshaped into counted arrays so the file side can repack it.
/// Everything is 1-based where the C64 is: pattern[0]/chord[0]/insts[0] are
/// dummies the stream never carries.
pub const Song = struct {
    loadaddr: u16 = music_data, // the file's leading word; toC64 has no use for it
    header: [header_size]u8 = undefined,
    seqs: [seq_slots][seq_bound]u8 = [_][seq_bound]u8{[_]u8{0} ** seq_bound} ** seq_slots,
    seq_len: [seq_slots]u8 = [_]u8{0} ** seq_slots, // bytes including the ending delimiter
    ptn_len: [ptn_count + 1]u8 = [_]u8{0} ** (ptn_count + 1), // effective rows
    ptn_size: [ptn_count + 1]u8 = [_]u8{0} ** (ptn_count + 1), // bytes incl. the endmark
    pats: [ptn_count][ptn_bound]u8 =
        [_][ptn_bound]u8{[_]u8{0} ** ptn_bound} ** ptn_count, // pats[i-1]: pattern i
    insts: [inst_count + 1][inst_size]u8 =
        [_][inst_size]u8{[_]u8{0} ** inst_size} ** (inst_count + 1), // insts[i]: instrument i
    chords: [chord_len]u8 = [_]u8{0} ** chord_len,
    tempo: [tempo_len]u8 = [_]u8{0} ** tempo_len, // RESTEMP+1.. on the image
    funk: [max_subtune][2]u8 = [_][2]u8{default_funk} ** max_subtune,
};

pub const LoadError = error{
    TooShort, // no room even for the loadaddr + a header
    BadId, // TUNEHEADER does not begin with "SWM1"
    Truncated, // the stream runs off the front of the file
    BadCount, // a header count is beyond what the editor's tables can hold
    BadSize, // a pattern claims size 0 (bigger would be nonsense but is read as-is)
};

pub const SaveError = error{
    NoRoom, // the output slice is smaller than packtun's result for this tune
    Overflow, // the packer's own memory limits no longer hold (a count > maxptnamount etc.)
};

/// Pattern 0: the dummy pattern a sequence shows while it has no rows
/// (editor.asm: PTN0 = $00,$FF). Pattern size caches as 2.
fn putPtn0(s: *Song) void {
    s.ptn_len[0] = 1;
    s.ptn_size[0] = 2;
    // pats[0] slot is unused; the image writer emits [$00,$FF] directly.
}

/// The song as a fresh editor workfile (InitTune/EmptyIns defaults), then
/// adjusted where a depack would leave data: a blank tune with no counts.
pub fn reset(s: *Song) void {
    s.loadaddr = music_data;
    @memset(&s.header, 0);
    for (0..seq_slots) |i| blankSeq(s, i);
    for (1..ptn_count + 1) |i| blankPtn(s, i);
    putPtn0(s);
    for (1..inst_count + 1) |i| blankInst(s, i);
    blankChords(s);
    blankTempo(s);
    for (0..max_subtune) |i| s.funk[i] = default_funk;
}

fn blankSeq(s: *Song, i: usize) void {
    @memset(&s.seqs[i], 0);
    s.seqs[i][0] = seq_end_stop; // unused (decoseq `unused`), the same default
    s.seq_len[i] = 1;
}

fn blankPtn(s: *Song, i: usize) void {
    blankPtnLen(s, i, default_ptn_len);
}

/// emptypt with the editor's *runtime* defptlen (TUNEHEADER+11, editable from
/// the menu): cleared, delimiter at `len`, length/size caches set.
fn blankPtnLen(s: *Song, i: usize, len: u8) void {
    @memset(&s.pats[i - 1], 0);
    s.pats[i - 1][len] = ptn_end;
    s.ptn_len[i] = len;
    s.ptn_size[i] = len +% 1;
}

/// The default instrument from EmptIns + dummyihdr. The two HR-ADSR bytes are
/// DEFAULTHRADSR from settings.cfg ($0F,$F0 flipped through >,<).
fn blankInst(s: *Song, i: usize) void {
    const m = &s.insts[i];
    @memset(m, 0);
    m[0] = 0b00011010; // control register (dummyihdr)
    m[1] = 0x0F; // >DEFAULTHRADSR (DEFAULTHRADSR=$0F00)
    m[2] = 0x00; // <DEFAULTHRADSR
    m[3] = 0x00; // ADSR on notestart, gate on
    m[4] = 0xF0;
    m[8] = 0x01; // default chord for instrument
    m[10] = 0x11; // <(pulsprog-instbase): pulsprog sits at +17
    m[11] = 0x12; // <(filtprog-instbase): filtprog sits at +18
    m[15] = 0x09; // first frame waveform
    m[16] = ptn_end; // WF program
    m[17] = ptn_end; // pulse width program
    m[18] = ptn_end; // filter program (also the instrument endmark position)
    @memset(m[inst_empty_size + 1 .. inst_usable], 0);
    @memset(m[inst_usable..inst_size], '.');
}

fn blankChords(s: *Song) void {
    s.chords[0] = chord_end2; // editor.asm: "ensure delimiter as chord0"
    @memset(s.chords[1..], chord_end2); // depkinsch fills the rest with endsignals
}

fn blankTempo(s: *Song) void {
    @memset(&s.tempo, tempo_end); // depktempo fills unused tempo bytes with $80
}

// -- menu kill items (menu.inc CINITUN / CININST) -----------------------------

/// CINITUN (menu.inc): "KILL TUNE&TEMPO". The three counts go to zero, then
/// the same depackers a load runs rebuild the blank state: every pattern
/// wiped to the editable defptlen (TUNEHEADER+11), every orderlist $FE, the
/// tempo table $80. A default subtune then plays patterns 1..3.
/// Quirk kept: depktempo re-reads subtune 0's tempo pair from the packed
/// stream, which after zeroing the counts is the tune's own funk pair, so
/// funk[0] survives while the unused subtunes get defsubtempo1/2 again.
pub fn killTune(s: *Song) void {
    s.header[H_SEQAMO] = 0;
    s.header[H_PTAMOU] = 0;
    s.header[H_TMPLEN] = 0;
    const len = s.header[H_DEFLEN];
    for (1..ptn_count + 1) |i| blankPtnLen(s, i, len); // depkptseq emptypt
    putPtn0(s);
    for (0..seq_slots) |i| blankSeq(s, i); // decoseq unused
    blankTempo(s); // depktempo
    for (1..max_subtune) |i| s.funk[i] = default_funk;
    // CINITUN: create a default subtune with patterns 1..3
    for (0..3) |t| {
        s.seqs[t][0] = @intCast(t + 1);
        s.seqs[t][1] = seq_end_stop;
        s.seq_len[t] = 2;
    }
}

/// CININST (menu.inc): "KILL INST&CHORD" -> depkinsch with both counts zero,
/// which rebuilds instruments 1..36 from EmptIns and fills the chord table
/// with end signals (chord 0 keeps its preset delimiter).
pub fn killInsts(s: *Song) void {
    s.header[H_INSTAM] = 0;
    s.header[H_CHRDLE] = 0;
    for (1..inst_count + 1) |i| blankInst(s, i);
    blankChords(s);
}

// -- reading: ProcessSWMver1 + depackt --------------------------------------

/// Load an .SWM/.SWS file (the 2-byte PRG loadaddr included in `data`) into
/// `s` (depacked form). The stream is read backwards exactly like
/// ProcessSWMver1; nothing else in the tune data is touched.
pub fn load(s: *Song, data: []const u8) LoadError!void {
    if (data.len < 2 + header_size) return error.TooShort;
    if (!std.mem.eql(u8, data[2..6], "SWM1")) return error.BadId;
    s.loadaddr = @as(u16, data[0]) | (@as(u16, data[1]) << 8);
    @memcpy(&s.header, data[2 .. 2 + header_size]);

    const counts = try readCounts(s);
    var idx: usize = data.len - 1; // ProcessSWMver1's DataIndex

    // A. subtune funktempos: read pairs for subtune subt-1 .. 0 (dpstemp/isttemp
    // packed them in that order, t0=fast t1=slow at SUBTUNES+s*8+6/7)
    var f = counts.subt;
    while (f > 0) {
        f -= 1;
        if (idx < header_size + 2) return error.Truncated;
        const t1 = data[idx];
        const t0 = data[idx - 1];
        idx -= 2;
        s.funk[f] = .{ t0, t1 };
    }

    try readTempo(s, data, &idx, counts.tmplen);
    try readChords(s, data, &idx, counts.chrdle);
    try readInsts(s, data, &idx, counts.instam);
    try readPats(s, data, &idx, counts.ptamou);
    try readSeqs(s, data, &idx, counts.seqamo);
    if (idx != 2 + header_size - 1) return error.Truncated; // must land after TUNEHEADER
}

fn readCounts(s: *Song) LoadError!struct {
    seqamo: usize,
    subt: usize,
    ptamou: usize,
    instam: usize,
    chrdle: usize,
    tmplen: usize,
} {
    const seqamo = s.header[H_SEQAMO];
    if (seqamo > seq_slots) return error.BadCount;
    const ptamou = s.header[H_PTAMOU];
    if (ptamou > ptn_count) return error.BadCount;
    const instam = s.header[H_INSTAM];
    if (instam > inst_count) return error.BadCount;
    const chrdle = s.header[H_CHRDLE];
    if (chrdle > chord_len - 1) return error.BadCount;
    const tmplen = s.header[H_TMPLEN];
    if (tmplen > tempo_len) return error.BadCount;
    const subt: usize = if (seqamo != 0) (@as(usize, seqamo) - 1) / 3 + 1 else 1;
    if (subt > max_subtune) return error.BadCount;
    return .{
        .seqamo = seqamo,
        .subt = subt,
        .ptamou = ptamou,
        .instam = instam,
        .chrdle = chrdle,
        .tmplen = tmplen,
    };
}

// consuming n bytes must never eat into the TUNEHEADER even on bad files:
// everything below the stream floor is the header's own tail.
const stream_floor = header_size + 1; // data[65]: last TUNEHEADER byte

fn need(idx: usize, n: usize) LoadError!void {
    if (idx < stream_floor + n) return error.Truncated;
}

/// B. tempotable: tmplen bytes land at RESTEMP+1.. (depktempo), the rest is
/// filled with $80 endsignals. Read backwards like ProcessSWMver1 step B.
fn readTempo(s: *Song, data: []const u8, idx: *usize, tmplen: usize) LoadError!void {
    try need(idx.*, tmplen);
    idx.* -= tmplen;
    @memset(&s.tempo, tempo_end);
    for (0..tmplen) |k| s.tempo[k] = data[idx.* + 1 + k];
}

/// C. chordtable: chords 1..chrdle from the stream, everything above filled
/// with $7F endsignals; chord 0 is the editor's own $7F NOP (editor.asm:320,
/// depkinsch never touches it but the workspace holds that value).
fn readChords(s: *Song, data: []const u8, idx: *usize, chrdle: usize) LoadError!void {
    try need(idx.*, chrdle);
    idx.* -= chrdle;
    s.chords[0] = chord_end2;
    @memset(s.chords[1..], chord_end2);
    for (0..chrdle) |k| s.chords[k + 1] = data[idx.* + 1 + k];
}

/// D. instruments: stream block `[Size raw bytes][Size][8 name bytes]`; the
/// depacked slot is the raws + $FF endmark at index Size, zeroes up to the
/// name at +120 (depkins). Slots above instam get EmptIns' default dummy.
fn readInsts(s: *Song, data: []const u8, idx: *usize, instam: usize) LoadError!void {
    var i: usize = inst_count;
    while (i > 0) : (i -= 1) {
        if (i > instam) {
            blankInst(s, i);
            continue;
        }
        try need(idx.*, name_len);
        idx.* -= name_len;
        const pos = idx.*; // the size byte overwrote $FF at this position
        const size: usize = data[pos];
        try need(idx.*, size + 1);
        idx.* -= size + 1;
        const m = &s.insts[i];
        @memcpy(m[0..size], data[idx.* + 1 .. idx.* + 1 + size]);
        m[size] = 0xFF;
        @memset(m[size + 1 .. inst_usable], 0);
        @memcpy(m[inst_usable..], data[pos + 1 .. pos + 1 + name_len]);
    }
}

/// E. patterns: `raws... | Size | Length` (size $FF byte transformed to a size
/// indicator by the packer). Expanded slot: Size bytes, $FF at Size-1.
fn readPats(s: *Song, data: []const u8, idx: *usize, ptamou: usize) LoadError!void {
    var i: usize = ptn_count;
    while (i > 0) : (i -= 1) {
        if (i > ptamou) {
            blankPtn(s, i); // emptypt: not referenced by any sequence
            continue;
        }
        try need(idx.*, 2);
        const len: usize = data[idx.*];
        const size: usize = data[idx.* - 1];
        if (size == 0) return error.BadSize; // ProcessSWMver1: a 0-size pattern is nonsense
        idx.* -= 2;
        try expandPtn(s, i, size, data, idx);
        s.ptn_len[i] = @intCast(len);
        s.ptn_size[i] = @intCast(size);
    }
}

/// The packed-NOP expansion (`depak0`): marker $70..$77 means (v-$6E) zero
/// rows, legal only after a raw $00 or another marker; the previous RAW
/// stream byte is the judge (ProcessSWMver1's PreceedingData peeks, even if
/// that ends up being the size byte — the original's bug, kept).
fn expandPtn(s: *Song, i: usize, size: usize, data: []const u8, idx: *usize) LoadError!void {
    const p = &s.pats[i - 1];
    @memset(p, 0);
    p[size - 1] = ptn_end;
    var j: isize = @as(isize, @intCast(size)) - 2;
    while (j >= 0) {
        if (idx.* < stream_floor) return error.Truncated;
        const v = data[idx.*];
        const prev = data[idx.* - 1];
        if (v >= packed_min and v <= packed_max and
            (prev == 0 or (prev >= packed_min and prev <= packed_max)))
        {
            const k: isize = @as(isize, v) - packed_min + 1; // zero rows inside the marker
            if (j < k) return error.Truncated; // corrupt: marker would run past row 0
            j -= k; // the slot is zeroed already; Zeros are accounted for
            j -= 1; // the marker's own slot is consumed by the byte itself
        } else {
            p[@intCast(j)] = v;
            j -= 1;
        }
        idx.* -= 1;
    }
}

/// F. sequences 0..seqamo-1: `[L bytes incl. delimiter][L]`, read backwards
/// (the depkptseq scan). Unused slots get the bare-$FE empty orderlist.
fn readSeqs(s: *Song, data: []const u8, idx: *usize, seqamo: usize) LoadError!void {
    var si: usize = seq_slots;
    while (si > 0) {
        si -= 1;
        if (si >= seqamo) {
            blankSeq(s, si);
            continue;
        }
        try need(idx.*, 1);
        const L: usize = data[idx.*];
        try need(idx.*, L + 1);
        idx.* -= L + 1;
        @memcpy(s.seqs[si][0..L], data[idx.* + 1 .. idx.* + 1 + L]);
        @memset(s.seqs[si][L..], 0);
        s.seq_len[si] = @intCast(L);
    }
}

// -- saving: packtun's scans -----------------------------------------------
//
// packtun recomputes the five header counts from the tune memory before
// packing; the same scans give the file-cut points (the chord/tempo copy
// loops write their whole 255/119-byte scan but only advance compzptr by
// CHRDLE/TMPLEN, so the saved file holds exactly count bytes there).

/// A subtune gets one funktempo pair per ceil(SEQAMO/3), min 1 even when the
/// tune has no sequences at all (packdepack.inc:240 "still possible for the
/// 1st empty subtune").
pub fn subtuneCount(seqamo: usize) usize {
    return if (seqamo == 0) 1 else (seqamo - 1) / 3 + 1;
}

/// packtun's orderlist scan: length until $FE, or $FF + its one jump-address
/// byte; at the seqlength cap a bare $FE is forced in (seqlength=126,
/// sizeof the block stays 127).
pub fn scanSeq(slot: *const [seq_bound]u8) usize {
    var y: usize = 0;
    while (true) {
        const v = slot[y];
        if (v == seq_end_stop) return y + 1; // including the $FE itself
        if (v == seq_end_loop) return y + 2; // $FF plus the jump address
        if (y == seq_len_max) return seq_len_max + 1; // artificial $FE at slot[126]
        y += 1;
    }
}

/// SEQAMO = last slot whose block is more than the bare $FE; PTAMOU rides
/// along: the packer watches every scanned orderlist byte in 1..maxptnamount.
pub fn recomputeSeqs(s: *const Song, seqamo: *usize, ptamou: *usize) void {
    var p_max: usize = 0;
    var s_last: usize = 0;
    for (0..seq_slots) |i| {
        if (scanSeq(&s.seqs[i]) != 1) s_last = i + 1;
        var y: usize = 0;
        while (y <= seq_len_max) : (y += 1) {
            const v = s.seqs[i][y];
            if (v == seq_end_stop or v == seq_end_loop) break;
            if (v >= 1 and v <= ptn_count and v > p_max) p_max = v;
        }
    }
    seqamo.* = s_last;
    ptamou.* = p_max;
}

/// packinst's $FF search: up from nothing, down from y=119, giving up at
/// y=15 (an unfound delimiter reads as size 15, per the `cpy #$0f` bail).
pub fn instSize(m: *const [inst_size]u8) usize {
    var y: usize = inst_usable - 1; // 119: the byte before the name
    while (y != inst_low_lim) {
        if (m[y] == 0xFF) return y;
        y -= 1;
    }
    return inst_low_lim;
}

/// INSTAM = last instrument whose size differs from the dummy header's 18.
pub fn recomputeInstam(s: *const Song) usize {
    var last: usize = 0;
    for (1..inst_count + 1) |i| {
        if (instSize(&s.insts[i]) != inst_empty_size) last = i;
    }
    return last;
}

/// CHRDLE (packdepack.inc:181): walk chords[1..255]; a $7E/$7F byte always
/// burns the delimiter counter X, but CHRDLE only moves at a delimiter whose
/// predecessor is a note (bit7-set or delimiter prev = consecutive endsign,
/// not a chord end). The scan stops once MAXCHORDAMOUNT chord ends have
/// been recorded: FUTUCO's chord table carries 31 endsignals and still
/// records the last one, so the naive `cpx #31 → abort` reading mis-trims.
pub fn recomputeChrdle(s: *const Song) usize {
    var chrdle: usize = 0;
    var x: usize = 0; // chcount: every $7E/$7F seen so far
    for (0..chord_len) |y| { // y indexes chords[1+y]; chords[256] is past the
        const k = y + 1; // table, read as a non-delimiter (loop wraps in asm)
        if (k >= chord_len) break;
        const v = s.chords[k];
        if (v >= 0x80) continue;
        if (v < chord_end1) continue;
        x += 1;
        const prev = s.chords[k - 1];
        if (prev < 0x80 and prev >= chord_end1) continue;
        if (x > max_chord - 1) break; // record while X <= 31; see doc above
        chrdle = y + 1;
    }
    return chrdle;
}

/// TMPLEN (packdepack.inc:211): any byte with bit7 set ends a portrait; a
/// plain $80 delimiter after another bit7-set byte is an EMPTY program and
/// does not move TMPLEN; X>=MAXTEMPOPRAMOUNT-1 aborts.
pub fn recomputeTmplen(s: *const Song) usize {
    var tmplen: usize = 0;
    var x: usize = 0;
    for (0..tempo_len) |y| {
        const v = s.tempo[y];
        if (v < 0x80) continue;
        x += 1;
        if (v != tempo_end) {
            if (x > max_tempopg - 1) break;
            tmplen = y + 1;
            continue;
        }
        if (y == 0) continue;
        if (s.tempo[y - 1] >= 0x80) continue; // empty delimiter pair
        if (x > max_tempopg - 1) break;
        tmplen = y + 1;
    }
    return tmplen;
}

// byte-at-a-time writer with packtun's own memory check (KERNAL.SAVE is only
// handed compzptr's span; anything the buffer can't hold would not be saved)
const Pack = struct {
    buf: []u8,
    pos: usize = 0,

    fn put(self: *Pack, b: u8) SaveError!void {
        if (self.pos >= self.buf.len) return error.NoRoom;
        self.buf[self.pos] = b;
        self.pos += 1;
    }
    fn putSlice(self: *Pack, bytes: []const u8) SaveError!void {
        for (bytes) |b| try self.put(b);
    }
};

/// Pack the Song into `out` (loadaddr + TUNEHEADER + packed stream); the
/// header's five counts get recomputed on every save, like packtun does.
pub fn save(s: *const Song, out: []u8) SaveError!usize {
    var seqamo: usize = 0;
    var ptamou: usize = 0;
    recomputeSeqs(s, &seqamo, &ptamou);
    const instam = recomputeInstam(s);
    const chrdle = recomputeChrdle(s);
    const tmplen = recomputeTmplen(s);
    const subt = subtuneCount(seqamo);

    var p = Pack{ .buf = out };
    try p.put(@truncate(s.loadaddr & 0xFF));
    try p.put(@truncate(s.loadaddr >> 8));
    var head = s.header;
    head[H_SEQAMO] = @intCast(seqamo);
    head[H_PTAMOU] = @intCast(ptamou);
    head[H_INSTAM] = @intCast(instam);
    head[H_CHRDLE] = @intCast(chrdle);
    head[H_TMPLEN] = @intCast(tmplen);
    try p.putSlice(&head);

    // 1. orderlists of the used subtunes (seqcolp), block = bytes + length
    for (0..seqamo) |i| try packSeqBlock(&s.seqs[i], &p);
    // 2. patterns 1..PTAMOU (ptnclop; $FF endmark becomes the size byte)
    for (1..ptamou + 1) |i| try packPtnBlock(s, i, &p);
    // 3. instruments 1..INSTAM (insclop; later stream blocks get cut off by
    //    the chord copy written over them at compzptr, i.e. they never land
    //    in the file)
    for (1..instam + 1) |i| try packInstBlock(s, i, &p);
    // 4.-6. chords 1..CHRDLE, tempi 0..TMPLEN-1 at RESTEMP+1.., funk pairs
    try p.putSlice(s.chords[1 .. chrdle + 1]);
    try p.putSlice(s.tempo[0..tmplen]);
    for (0..subt) |sub| try p.putSlice(&s.funk[sub]);
    return p.pos;
}

fn packSeqBlock(slot: *const [seq_bound]u8, p: *Pack) SaveError!void {
    const L = scanSeq(slot);
    for (0..L) |k| {
        var b = slot[k];
        if (k == seq_len_max and L == seq_len_max + 1) b = seq_end_stop; // forced $FE
        try p.put(b);
    }
    try p.put(@intCast(L));
}

/// The pattern-packer (ptpcklp): copy non-zeros and isolated zeros; a run
/// longer than 2 zeros gets one marker $70..$77 (only when OPTIMIZEPTN's
/// confbit says the column may hold them — see NOTES.md).
fn packPtnBlock(s: *const Song, i: usize, p: *Pack) SaveError!void {
    const S: usize = s.ptn_size[i];
    const e = &s.pats[i - 1];
    var j: usize = 0;
    while (j + 1 < S) { // bytes 0..Size-2; Size-1 holds the delimiter
        const v = e[j];
        if (v != 0 or j == 0 or e[j - 1] != 0) {
            try p.put(v);
            j += 1;
            continue;
        }
        var m: usize = packed_min - 1; // PACKEDMIN-1: nothing packable yet
        while (true) {
            if (j + 1 >= S - 1 or e[j + 1] != 0) break;
            j += 1;
            m += 1;
            if (m == packed_max) break;
        }
        try p.put(@intCast(if (m == packed_min - 1) 0 else m)); // 2 zeros stay literal
        j += 1;
    }
    try p.put(@intCast(S));
    try p.put(@intCast(s.ptn_len[i]));
}

/// packinst: raws 0..Size-1 with the Size byte replacing the $FF endmark,
/// then the 8 name bytes; Size re-searched from the slot at pack time.
fn packInstBlock(s: *const Song, i: usize, p: *Pack) SaveError!void {
    const m = &s.insts[i];
    const S = instSize(m);
    try p.putSlice(m[0..S]);
    try p.put(@intCast(S));
    try p.putSlice(m[inst_usable..]);
}

// -- the C64 workfile image (settings.cfg layout, MUSICDATA=$1D00) ----------

fn putPtr(img: []u8, lo_off: usize, hi_off: usize, k: usize, addr: usize) void {
    img[lo_off + k] = @truncate(addr & 0xFF);
    img[hi_off + k] = @truncate((addr >> 8) & 0xFF);
}

/// Fill the whole 34432-byte editor image:
/// SUBTUNES (orderlist pointers + funk tempos), the pointer caches, the
/// TUNEHEADER copy, then the raw sequence/pattern/instrument/chord/tempo
/// areas — the mirror image of what depackt lands in the editor's memory.
pub fn toC64(s: *const Song, img: []u8) SaveError!void {
    if (img.len < music_len) return error.NoRoom;
    putSubtunes(s, img);
    // observer-grid caches as the tune-initer/depkptseq would leave them
    for (0..pptrlo_n) |k| {
        const off: usize = if (k == 0) o_ptn0 else o_restptn + (k - 1) * ptn_bound;
        putPtr(img, o_pptrlo, o_pptrhi, k, music_data + off);
    }
    for (0..o_inspt_n) |k| {
        // dummy instrument 0 rides instrument 1's base (Ian Coog's advice, the
        // COMPILEDAPP==2 wiring); slot 37 is the one-past-last copy buffer
        const off: usize = o_instruments + (if (k == 0) 0 else k - 1) * inst_size;
        putPtr(img, o_insptlo, o_inspthi, k, music_data + off);
    }
    putChdTempptr(s, img);
    for (0..pptrlo_n) |k| { // ptnlength/ptnsize index by pattern number
        img[o_ptnlength + k] = s.ptn_len[k];
        img[o_ptnsize + k] = s.ptn_size[k];
    }
    @memcpy(img[o_tuneheader..][0..header_size], &s.header);
    for (0..seq_slots) |i|
        @memcpy(img[o_sequences + i * seq_bound ..][0..seq_bound], &s.seqs[i]);
    @memcpy(img[o_ptn0..][0..2], &[_]u8{ 0, 0xFF }); // PTN0 (editor.asm:309)
    for (1..ptn_count + 1) |i|
        @memcpy(img[o_restptn + (i - 1) * ptn_bound ..][0..ptn_bound], &s.pats[i - 1]);
    for (1..inst_count + 1) |i|
        @memcpy(img[o_instruments + (i - 1) * inst_size ..][0..inst_size], &s.insts[i]);
    @memcpy(img[o_chords..][0..chord_len], &s.chords);
    @memset(img[o_tempotbl..o_resemp], 0); // rest-tempo words: player runtime
    img[o_resemp] = 0; // RESTEMP+0: tempo[0]'s "previous byte" during a depack
    @memcpy(img[o_resemp + 1 ..][0..tempo_len], &s.tempo);
}

/// SUBTUNES: always 8 rows of 8 (orderlist lo/hi for the 3 tracks, then the
/// funk tempos); unused subtunes keep the orderlist pointers (their slots
/// hold $FE) and defsubtempo1/2, as setstp1/setstp2 leaves them.
fn putSubtunes(s: *const Song, img: []u8) void {
    const subt = subtuneCount(s.header[H_SEQAMO]);
    for (0..max_subtune) |sub| {
        for (0..3) |c| {
            const a = music_data + o_sequences + (sub * 3 + c) * seq_bound;
            img[sub * 8 + c * 2] = @truncate(a & 0xFF); // lo of the orderlist slot
            img[sub * 8 + c * 2 + 1] = @truncate((a >> 8) & 0xFF);
        }
        const f = if (sub < subt) s.funk[sub] else default_funk;
        img[sub * 8 + 6] = f[0];
        img[sub * 8 + 7] = f[1];
    }
}

/// CHDPTR/TEMPTR caches. Bases: chord 0 = the $7F NOP at chords[0] (CHDPTR[0]
/// = 0) and chord 1 begins at chords[1] (CHDPTR[1] = 1, editor init, not the
/// depacker's job); each later delimiter at chords[i] starts a chord at i+1.
/// Program 0/1 of the tempos both sit at RESTEMP+1 (depktempo's "pointer 0
/// and 1 need not be set" = init value 9; delimiters then stack the titles).
fn putChdTempptr(s: *const Song, img: []u8) void {
    img[o_chdptrlo] = 0;
    img[o_chdptrlo + 1] = 1;
    var x: usize = 1; // delimiters seen; the first stores slot 2
    for (0..chord_len) |y| {
        const k = y + 1;
        if (k >= chord_len) break;
        const v = s.chords[k];
        if (v == chord_end1 or v == chord_end2) { // depkinsch's inchdpt
            x += 1;
            if (x < max_chord) img[o_chdptrlo + x] = @truncate(k + 1 & 0xFF);
        }
    }
    img[o_temptrlo] = 9; // RESTEMP+1 relative to TEMPOTBL: program 0's start
    img[o_temptrlo + 1] = 9; // depktempo: "pointer 0 and 1 need not be set"
    var t: usize = 1;
    for (0..tempo_len) |y| {
        if (s.tempo[y] < 0x80) continue; // only delimiters move the pointer
        t += 1;
        if (t < max_tempopg) img[o_temptrlo + t] = @truncate(y + 2 + (o_resemp - o_tempotbl));
    }
}

/// Read the editor workfile image back into a Song (toC64's inverse; used by
/// later parts to hand zig-edited tunes to the original player). Header
/// counts are read from the image's TUNEHEADER, sequence lengths re-scanned,
/// pattern sizes trusted from the cache (checked against the slot's $FF).
pub fn fromC64(song: *Song, img: []const u8) LoadError!void {
    if (img.len < music_len) return error.TooShort;
    song.loadaddr = music_data;
    @memcpy(&song.header, img[o_tuneheader..][0..header_size]);
    song.chords[0] = chord_end2;
    @memcpy(&song.chords, img[o_chords..][0..chord_len]);
    @memset(&song.tempo, tempo_end);
    @memcpy(&song.tempo, img[o_resemp + 1 ..][0..tempo_len]);
    for (0..seq_slots) |i| {
        @memcpy(&song.seqs[i], img[o_sequences + i * seq_bound ..][0..seq_bound]);
        song.seq_len[i] = @intCast(scanSeq(&song.seqs[i]));
    }
    for (0..max_subtune) |sub| {
        song.funk[sub] = .{ img[sub * 8 + 6], img[sub * 8 + 7] };
    }
    for (1..ptn_count + 1) |i| {
        const s_off = o_restptn + (i - 1) * ptn_bound;
        @memcpy(&song.pats[i - 1], img[s_off..][0..ptn_bound]);
        const S = img[o_ptnsize + i];
        if (S == 0 or img[s_off + S - 1] != ptn_end) return error.BadSize; // cache lied
        song.ptn_size[i] = S;
        song.ptn_len[i] = img[o_ptnlength + i];
    }
    for (1..inst_count + 1) |i|
        @memcpy(&song.insts[i], img[o_instruments + (i - 1) * inst_size ..][0..inst_size]);
}
