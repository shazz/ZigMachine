// The B.I.G. Demo's jukebox list — TEX's OWN 118 rows, ripped out of the
// running demo's memory, not transcribed from the CODEF remake.
//
// The rows themselves are generated into big/list_data.zig. This file is the
// provenance: where they came from, how they were checked, and what the fields
// mean. That prose is the point — it is what makes the data trustworthy to the
// next reader — so it lives here rather than being squeezed to fit beside 118
// table rows.
//
// ---- SOURCE --------------------------------------------------------------
// BIG_DEMO.MSA booted in Hatari (TOS 1.02 fr, ST, 1 MB), frozen at the jukebox
// screen, the table dumped straight out of RAM
// (prototypes/codef/23/atarimania/songlist.bin). The geometry comes out of the
// DRAWING CODE, not from eyeballing the data:
//
//     $B648  mulu.w  #$26,d1        ; row index * 38   <- stride
//     $B652  lea     $a4bc(pc),a0   ; table base       <- $A4BC
//     $B662  move.b  (a0)+,d0       ; print until NUL
//     $B686  move.b  $24(a1),$b699  ; byte 36 -> a self-modified operand
//     $B68E  move.b  $25(a1),$b69b  ; byte 37 -> a self-modified operand
//
// A row is 38 bytes: [0..34] the 35 printable characters, [35] the NUL the
// print loop stops on, [36] the subtune (0-BASED), [37] the tune id. On a tune
// row byte 29 is '|' and bytes 30..34 are the duration, MM'SS.
//
// ---- VERIFIED INDEPENDENTLY, before any of this was generated -------------
// The dump begins ONE BYTE BEFORE $A4BC and runs past the table's end, so a
// decode from offset 0 produces rows of noise. Rather than take the offset on
// trust, it was recovered from the bytes: the printable runs in the dump start
// at 1, 39, 77, 115, 153, 191, ... which gives base = 1 and stride = 38 from
// the data alone. Then, every one of these was measured and held:
//
//   * all 118 rows carry NUL at byte 35, and every label is fully printable;
//   * exactly 113 rows carry '|' at byte 29, and all 113 of those ALSO carry a
//     well-formed MM'SS at 30..34 — zero exceptions in either direction. The
//     other 5 are the dividers and blanks;
//   * 118 x 38 = 4484 = $A4BC..$B640, exactly what the drawing code says;
//   * ACE 2 = 05'52, ACTION-BIKER #1 = 03'09 and #2 = 01'01 — all three match
//     the live screen;
//   * and the whole decode was then diffed row by row, field by field, against
//     an independent one made from the same dump: 118 of 118 identical.
//
// ---- THE SUBTUNE IS THE DEMO'S OWN ---------------------------------------
// `tune` is byte 36 + 1 (our API counts from 1) and rows sharing byte 37 share
// an SNDH image. This replaces the mapping we previously INFERRED from the
// remake's ".ym" filename numbering. Across all 47 ids byte 36 runs 0..n-1 with
// zero exceptions, and the group sizes match the SNDH images exactly — MONTY
// 13, DELTA 10, GERRY THE GERM 7, GREMLIN 7, SAMANTHA-FOX 6, STRONGMAN 6.
//
// NOTE the SEMANTICS of bytes 36/37 are a reading of two values the code copies
// into self-modified operands. The bytes are fact; "subtune" and "tune id" are
// the hypothesis that 47-for-47 agreement supports.
//
// ---- THE LABELS ARE VERBATIM ---------------------------------------------
// Internal spacing, the '|', and the duration, exactly as the table holds them.
//
// The '|' does not appear on the real screen and does not need stripping:
// fontp.png is 512x32, cut by initTile(16,16,32) into 64 tiles from character
// 32, so '|' (0x7C) is glyph 92 — off the sheet. drawPart paints nothing, which
// is precisely what screen.zig's `if (g >= A.P_GLYPHS) continue` does, the same
// path the scrolltext's TAB and lowercase 'r' already take. Checked against the
// font, not assumed.
//
// Keeping the labels verbatim is also what puts the DURATIONS on screen,
// right-aligned, with no code at all: they are part of the 35 characters.
//
// ---- WHERE THE REMAKE IS WRONG -------------------------------------------
// It is not only dropped rows. CODEF screen 23 RENAMED entries and then
// RE-SORTED the list alphabetically under the new names, which moved them:
//
//     ACTION-BIKER #1..#3   -> "CLUMSY COLIN ACTION BIKER",  A -> C
//     STRONGMAN #1..#6      -> "GEOFF CAPES STRONGMAN",      S -> G
//     SHOWJUMPING           -> "HARVEY SMITHS SHOW JUMPING", S -> H
//
// It also dropped BALLOON CHALLENGE #2 and INTERNATIONAL KARATE II, invented an
// "INTERNATIONAL KARATE +" that memory does not have, lost the '&' of BUMP SET
// & SPIKE and both hyphens of SAMANTHA-FOX STRIP-POKER, shortened
// "(MAKE L.O.V.E. NOT) W.A.R." to "W.A.R", carried a "##2" typo on GERRY THE
// GERM, and ended the list "END OF LIST" where the demo says "BOTTOM OF LIST".
// We follow the REAL demo (Matt, 2026-09-19) — the same call already made for
// the colour bands, the border and the Digital Department row itself.
//
// NOTE ZOIDS sorts AFTER ZOOLOOK here. That is the demo's own order, not a
// mistake, and it must not be "fixed".
//
// ---- FILE NAMES, AND TWO REAL DISAGREEMENTS ------------------------------
// The archive's names differ from TEX's spelling in places — CONFUZION ->
// Confuzion.sndh, SHOWJUMPING -> Harvey_Smiths_Show_Jumping.sndh — which is the
// archive's naming of the same Mad Max Best-In-Galaxy tunes, not a substitution.
//
// INTERNATIONAL KARATE II -> International_Karate_Plus.sndh is the same thing
// in the other direction, and it is correct: the 1987 sequel to International
// Karate was released as "International Karate +" (IK+), so TEX's "II" and the
// archive's "_Plus" are one game under its two common names. The two files in
// Best_In_Galaxy/ are genuinely different images (different size and md5)
// despite sharing a TITL, so the demo's two rows map onto them one for one.
// Settled; please do not re-litigate it.
//
// Two genuine disagreements between the demo's table and the archive, recorded
// here as known rather than overlooked:
//
//   * THE LAST V8 — the table has THREE rows, The_Last_V8.sndh is ##01. Rows #2
//     and #3 therefore play NOTHING. The archive is missing two of TEX's
//     subtunes; that is a fact about the archive, not a licence to substitute
//     some other part of the tune.
//   * STARPAWS — the table has THREE rows, Starpaws.sndh is ##04. Subtunes 1-3
//     are used and the fourth is simply unused. Harmless, but it means either
//     the demo omits one or the archive's image carries an extra.
//
// `song = ""` means "select it, nothing plays": the 5 divider and blank rows,
// the two tunes with no SNDH in the archive at all (DELTA PREVIEW, THALAMUS),
// and THE LAST V8 #2 and #3 above. Nine rows in total.
const std = @import("std");
const data = @import("list_data.zig");

pub const Entry = data.Entry;
pub const ENTRIES = data.ENTRIES;

/// The row that opens the Digital Solution (big/digital.zig): the last one
/// `curent` can reach.
///
/// The real table puts "-=THE DIGITAL DEPARTMENT=-" at row 115, and the demo's
/// own clamp is `mylist.length - 3` = 118 - 3 = 115. The data and the code
/// agree without being made to, which is the strongest evidence we have that
/// this row is where memory says it is — and it is why the remake's list, which
/// has no such row, left the clamp pointing at an ordinary tune.
pub const DIGITAL: usize = ENTRIES.len - 3;

comptime {
    @setEvalBranchQuota(4000); // the 118-row label check below
    if (ENTRIES.len != 118) @compileError("the table is 118 rows");
    if (ENTRIES[DIGITAL].song.len != 0) @compileError("the Digital Department row must have no tune");
    if (std.mem.indexOf(u8, ENTRIES[DIGITAL].label, "DIGITAL DEPARTMENT") == null)
        @compileError("DIGITAL does not point at the Digital Department row");
    for (ENTRIES) |e| if (e.label.len != 35) @compileError("a row is not 35 characters");
}
