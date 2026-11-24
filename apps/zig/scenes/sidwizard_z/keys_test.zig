// --------------------------------------------------------------------------
// keys_test.zig — Part 3 checks: keyhandler.handle() against
// tunes/FLASHITBACK.SWM, whose pattern bytes were probed from the file
// (pattern 1 = pats[0]: ptn_size 75, ptn_len 64, rows 0..63, endmark at 74;
// row 0 = bd 82 59 (3B), rows 1..5 NOP, row 6 = bb 58 (2B) at offset 8,
// last row 63 = NOP at 73).
// --------------------------------------------------------------------------

const std = @import("std");
const swm = @import("swm.zig");
const dsp = @import("display.zig");
const kh = @import("keys.zig");

const tune = @embedFile("tunes/FLASHITBACK.SWM");

var song: swm.Song = .{};
var view: dsp.View = .{};

// The editor's start-up view (display_test.startupView), reloaded per test.
fn reset() !void {
    song = .{};
    view = .{};
    try swm.load(&song, tune);
    view.mutesolo = .{ song.header[swm.H_MUTE], song.header[swm.H_MUTE + 1], song.header[swm.H_MUTE + 2] };
}

fn key(code: u6) kh.Key {
    return .{ .code = code };
}

/// The pattern under the default cursor (track 0, pattern 1).
fn pat() *[swm.ptn_bound]u8 {
    return &song.pats[0];
}

fn saved() ![tune.len + 64]u8 {
    var out: [tune.len + 64]u8 = undefined;
    _ = try swm.save(&song, &out);
    return out;
}

// -- cursor movement (keyjmp crsrdn -> norcrdn -> ptcurdn) -------------------

test "CRSR down x3 moves the display cursor, not the scroll" {
    try reset();
    for (0..3) |_| _ = kh.handle(&song, &view, key(kh.crsr_d));
    try std.testing.expectEqual(@as(u8, 3), view.subwpos3[0]);
    try std.testing.expectEqual(@as(u8, 0), view.prowpos[0]); // no scroll yet
}

// -- note entry (writevalue -> notecol -> noteEntry) --------------------------

test "Z types note C (1) at the cursor row, size unchanged" {
    try reset();
    try std.testing.expectEqual(@as(u8, 0), pat()[5]); // row 3 = NOP
    for (0..3) |_| _ = kh.handle(&song, &view, key(kh.crsr_d));
    const eff = kh.handle(&song, &view, key(kh.z_)); // Z = note 1 (C)
    try std.testing.expect(eff == .none);
    try std.testing.expectEqual(@as(u8, 0x01), pat()[5]); // row 3 @ offset 5
    try std.testing.expectEqual(@as(u8, 75), song.ptn_size[1]); // note-only row
    try std.testing.expectEqual(@as(u8, 64), song.ptn_len[1]);
}

test "cbm+2 selects octave 1 (2-1); Z then types 0x0d" {
    try reset();
    const eff = kh.handle(&song, &view, .{ .code = kh.k2, .cbm = true });
    try std.testing.expect(eff == .none);
    try std.testing.expectEqual(@as(u8, 1), view.octave);
    _ = kh.handle(&song, &view, key(kh.crsr_d)); // row 1 = NOP at offset 3
    _ = kh.handle(&song, &view, key(kh.z_)); // note 1 + 12 octaves = 0x0d
    try std.testing.expectEqual(@as(u8, 0x0d), pat()[3]);
}

// -- instrument typing (writevalue -> isincol -> instLeft/instRight) ----------

test "typing '1' '2' in the inst column builds inst 18 on a NOP row" {
    try reset();
    _ = kh.handle(&song, &view, key(kh.crsr_d)); // row 1 = NOP at offset 3
    _ = kh.handle(&song, &view, key(kh.crsr_r)); // note -> inst column
    try std.testing.expectEqual(@as(u8, 1), view.subwpos2[0]);
    _ = kh.handle(&song, &view, key(kh.k1)); // '1': inserts the inst column
    try std.testing.expectEqual(@as(u8, 76), song.ptn_size[1]);
    _ = kh.handle(&song, &view, key(kh.k2)); // '2': completes inst $12
    try std.testing.expectEqual(@as(u8, 0x80), pat()[3]); // note marker only
    try std.testing.expectEqual(@as(u8, 0x12), pat()[4]); // inst 18
    try std.testing.expectEqual(@as(u8, 64), song.ptn_len[1]); // rows intact
    try std.testing.expectEqual(@as(u8, 2), view.subwpos2[0]); // still col 2
}

test "cbm+Z restores the previous keypress's state (single-level undo)" {
    try reset();
    _ = kh.handle(&song, &view, key(kh.crsr_d));
    _ = kh.handle(&song, &view, key(kh.crsr_r));
    _ = kh.handle(&song, &view, key(kh.k1));
    _ = kh.handle(&song, &view, .{ .code = kh.z_, .cbm = true });
    try std.testing.expectEqual(@as(u8, 0x00), pat()[3]);
    try std.testing.expectEqual(@as(u8, 0x00), pat()[4]);
    try std.testing.expectEqual(@as(u8, 75), song.ptn_size[1]);
    try std.testing.expectEqual(@as(u8, 64), song.ptn_len[1]);
    // a second mutation re-saves (each fresh keypress refreshes the undo
    // buffer, keyhandler.SaveUndo repecnt gate). The undo left the cursor in
    // the inst column: move left, retype '1' '2', and undo goes back to the
    // post-'1' state (not the original pattern).
    _ = kh.handle(&song, &view, .{ .code = kh.crsr_r, .shift = true }); // left
    try std.testing.expectEqual(@as(u8, 1), view.subwpos2[0]);
    _ = kh.handle(&song, &view, key(kh.k1)); // re-save, insert, advance
    _ = kh.handle(&song, &view, key(kh.k2)); // '2' re-saves, then completes
    try std.testing.expectEqual(@as(u8, 0x12), pat()[4]);
    _ = kh.handle(&song, &view, .{ .code = kh.z_, .cbm = true });
    try std.testing.expectEqual(@as(u8, 0x80), pat()[3]); // note marker stays
    try std.testing.expectEqual(@as(u8, 0x10), pat()[4]); // back to '1'
    try std.testing.expectEqual(@as(u8, 76), song.ptn_size[1]);
}

// -- DEL (deleter: delinpt main path + end-of-pattern dellast path) -----------

test "DEL removes the cursor row, appends NOP+endmarker, keeps ptnlength" {
    try reset();
    _ = kh.handle(&song, &view, key(kh.crsr_d)); // row 1 (NOP) at offset 3
    _ = kh.handle(&song, &view, key(kh.del));
    // row 6's bytes (bb 58) moved up one byte: offsets 8/9 -> 7/8
    try std.testing.expectEqual(@as(u8, 0xbb), pat()[7]);
    try std.testing.expectEqual(@as(u8, 0x58), pat()[8]);
    // delinpt: size-- by delbackpt, then ++: NOP over the moved endmarker
    try std.testing.expectEqual(@as(u8, 0x00), pat()[73]);
    try std.testing.expectEqual(@as(u8, 0xff), pat()[74]);
    try std.testing.expectEqual(@as(u8, 75), song.ptn_size[1]);
    try std.testing.expectEqual(@as(u8, 64), song.ptn_len[1]); // still 64 rows
}

test "DEL on the endsignal deletes the last row (dellast) and follows up" {
    try reset();
    for (0..64) |_| _ = kh.handle(&song, &view, key(kh.crsr_d)); // row 64
    try std.testing.expectEqual(@as(u8, 40), view.prowpos[0]); // 64-24 scroll
    _ = kh.handle(&song, &view, key(kh.del));
    // last row (row 63, NOP @73) gone: endmark moved up to [73]
    try std.testing.expectEqual(@as(u8, 0xff), pat()[73]);
    try std.testing.expectEqual(@as(u8, 74), song.ptn_size[1]);
    try std.testing.expectEqual(@as(u8, 63), song.ptn_len[1]);
    // cursor in the bottom half (24 >= 13) follows up: upinptn
    try std.testing.expectEqual(@as(u8, 23), view.subwpos3[0]);
    try std.testing.expectEqual(@as(u8, 40), view.prowpos[0]);
}

// -- no-op and round-trip ------------------------------------------------------

test "unknown key (shift/C= matrix code) leaves the whole tune unchanged" {
    try reset();
    const before = try saved();
    const eff = kh.handle(&song, &view, key(15)); // morekey
    try std.testing.expect(eff == .none);
    const after = try saved();
    try std.testing.expectEqualSlices(u8, &before, &after);
}

test "edits survive save -> load -> save byte-identically" {
    try reset();
    _ = kh.handle(&song, &view, key(kh.crsr_d));
    _ = kh.handle(&song, &view, key(kh.crsr_r));
    _ = kh.handle(&song, &view, key(kh.k1)); // inst column with inst $12
    _ = kh.handle(&song, &view, key(kh.k2));
    _ = kh.handle(&song, &view, .{ .code = kh.crsr_r, .shift = true }); // left
    _ = kh.handle(&song, &view, .{ .code = kh.crsr_r, .shift = true }); // left
    for (0..3) |_| _ = kh.handle(&song, &view, key(kh.crsr_d)); // row 4
    _ = kh.handle(&song, &view, key(kh.z_)); // note C
    var out1: [tune.len + 64]u8 = undefined;
    const n1 = try swm.save(&song, &out1);
    var back: swm.Song = .{};
    try swm.load(&back, out1[0..n1]);
    try std.testing.expectEqual(@as(u8, 0x80), back.pats[0][3]);
    try std.testing.expectEqual(@as(u8, 0x12), back.pats[0][4]);
    try std.testing.expectEqual(@as(u8, 0x01), back.pats[0][7]); // row 4 note
    var out2: [tune.len + 64]u8 = undefined;
    const n2 = try swm.save(&back, &out2);
    try std.testing.expectEqual(n1, n2);
    try std.testing.expectEqualSlices(u8, out1[0..n1], out2[0..n2]);
}

// -- instrument name typing (cbm+... nametypeEnter + menu.nametyper) ----------

test "name mode stages the field, edits it, RETURN stores it" {
    try reset();
    const eff = kh.handle(&song, &view, .{ .code = kh.n_, .shift = true });
    try std.testing.expect(eff == .nametype); // InsName
    try std.testing.expect(view.namemode);
    try std.testing.expectEqualStrings("ARP.....", &view.namebuf); // inst 1
    _ = kh.handle(&song, &view, key(8)); // keychar[8] = '3'
    try std.testing.expectEqual(@as(u8, '3'), view.namebuf[0]);
    try std.testing.expectEqual(@as(u8, 1), view.inamepos); // fcurfwd
    const eff2 = kh.handle(&song, &view, key(kh.ret_)); // RETURN: storina
    try std.testing.expect(eff2 == .redraw);
    try std.testing.expect(!view.namemode);
    try std.testing.expectEqualStrings("3RP.....", song.insts[1][120..128]);
}

// -- the menu gate (keyhandler.keyer menumode allowlist) -----------------------

test "menumode swallows keys outside the menu allowlist" {
    try reset();
    view.menumode = true;
    const before = try saved();
    const eff = kh.handle(&song, &view, key(kh.z_)); // not a menu key
    try std.testing.expect(eff == .none);
    const after = try saved();
    try std.testing.expectEqualSlices(u8, &before, &after);
    // crsr_d IS allowed: it goes to the menu cursor (menuDown), not the
    // pattern editor, so the pattern cursor stays put
    _ = kh.handle(&song, &view, key(kh.crsr_d));
    try std.testing.expectEqual(@as(u8, 0), view.subwpos3[0]);
}
