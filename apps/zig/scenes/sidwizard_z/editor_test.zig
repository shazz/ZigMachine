// --------------------------------------------------------------------------
// editor_test.zig — Part 5: the Editor glue. A scripted session boots a blank
// editor, loads FLASHITBACK.SWM, types three notes, saves, reloads the saved
// bytes and checks the final screen. Also checks the play hooks against
// emulated C64 memory.
// --------------------------------------------------------------------------

const std = @import("std");
const swm = @import("swm.zig");
const dsp = @import("display.zig");
const kh = @import("keys.zig");
const Editor = @import("editor.zig").Editor;
const ed = @import("editor.zig");

const tune = @embedFile("tunes/FLASHITBACK.SWM");

fn key(code: u6) kh.Key {
    return .{ .code = code };
}

test "boot -> load -> three notes -> save -> reload" {
    var e = Editor.init();
    // the fresh workfile defaults
    try std.testing.expectEqual(swm.default_ptn_len, e.song.header[swm.H_DEFLEN]);
    for (0..3) |t| try std.testing.expectEqual(@as(u8, 0xff), e.song.header[swm.H_MUTE + t]);
    try std.testing.expectEqual([3]u8{ 0xff, 0xff, 0xff }, e.view.mutesolo);

    // user config survives a load (the asm keeps Config across depackt)
    e.view.themeno = 3;
    e.view.keybtyp = 0x44;
    e.view.devicen = 9;
    e.view.confbits2 = 1;
    e.view.framesp = 4;
    try e.load(tune);
    try std.testing.expectEqual(@as(u8, 3), e.view.themeno);
    try std.testing.expectEqual(@as(u8, 0x44), e.view.keybtyp);
    try std.testing.expectEqual(@as(u8, 9), e.view.devicen);
    try std.testing.expectEqual(@as(u8, 1), e.view.confbits2);
    try std.testing.expectEqual(@as(u8, 4), e.view.framesp);
    try std.testing.expectEqualStrings("HERMIT: FLASH IT BACK", e.song.header[swm.H_AUTHOR .. swm.H_AUTHOR + 21]);
    try std.testing.expect(e.view.titledi); // dispaut after a load

    // the hidden row 26 carries the author line until the first key
    var over: dsp.Overlay = .{};
    e.overlay(&over);
    try std.testing.expect(over.row26_title);
    try std.testing.expectEqualStrings("HERMIT: FLASH IT BACK", over.row26[0..21]);

    // rows 1, 2, 3 of pattern 1 (track 0): C, D, E by the piano keys
    _ = e.key(key(kh.crsr_d));
    _ = e.key(key(kh.z_));
    _ = e.key(key(kh.crsr_d));
    _ = e.key(key(kh.x_));
    _ = e.key(key(kh.crsr_d));
    _ = e.key(key(kh.c_));
    const n1 = e.song.pats[0][3] & 0x7f;
    const n2 = e.song.pats[0][4] & 0x7f;
    const n3 = e.song.pats[0][5] & 0x7f;
    try std.testing.expect(n1 != 0 and n2 != 0 and n3 != 0);
    try std.testing.expectEqual(@as(u8, 64), e.song.ptn_len[1]);
    try std.testing.expectEqual(@as(u8, 75), e.song.ptn_size[1]);

    // save, then reload those exact bytes into a second editor
    var buf: [65536]u8 = undefined;
    const n = try e.save(&buf);
    var again = Editor.init();
    try again.load(buf[0..n]);
    try std.testing.expectEqualSlices(u8, &e.song.header, &again.song.header);
    try std.testing.expectEqualSlices(u8, &e.song.pats[0], &again.song.pats[0]);
    try std.testing.expectEqual(@as(u8, n1), again.song.pats[0][3] & 0x7f);

    // the final screen: the three notes are in track 0's note column
    var scr: dsp.Screen = .{};
    e.render(&scr);
    for ([_]struct { row: usize, note: u8 }{
        .{ .row = 1, .note = n1 },
        .{ .row = 2, .note = n2 },
        .{ .row = 3, .note = n3 },
    }) |want| {
        try std.testing.expectEqual(dsp.notechar[want.note], scr.chars[want.row][1]);
        try std.testing.expectEqual(dsp.octachar[want.note], scr.chars[want.row][2]);
    }
    try std.testing.expectEqual(@as(u8, 0xc0), scr.chars[0][0]); // the template's top-left
}

test "songForPlayer writes the tune at $1D00 and playerState reads $10.." {
    var e = Editor.init();
    try e.load(tune);
    var mem = [_]u8{0} ** 65536;
    try e.songForPlayer(&mem);
    // TUNEHEADER starts at music_data + o_tuneheader; SWM files begin "SWM1"
    const hdr = swm.music_data + swm.o_tuneheader;
    try std.testing.expectEqualStrings("SWM1", mem[hdr .. hdr + 4]);
    try std.testing.expectEqualStrings("HERMIT: FLASH IT BACK", mem[hdr + swm.H_AUTHOR .. hdr + swm.H_AUTHOR + 21]);

    // the player's 7-byte bunches: set one channel and read it back
    for (0..3) |c| {
        const b = ed.player_base + c * ed.player_stride;
        mem[b + ed.off_spdcnt] = @intCast(1 + c);
        mem[b + ed.off_seqpos] = @intCast(10 + c);
        mem[b + ed.off_ptnpos] = @intCast(20 + c);
        mem[b + ed.off_curptn] = @intCast(2 + c);
        mem[b + ed.off_tmppos] = @intCast(30 + c);
    }
    const p = Editor.playerState(&mem);
    try std.testing.expectEqual([3]u8{ 1, 2, 3 }, p.spdcnt);
    try std.testing.expectEqual([3]u8{ 10, 11, 12 }, p.seqpos);
    try std.testing.expectEqual([3]u8{ 20, 21, 22 }, p.ptnpos);
    try std.testing.expectEqual([3]u8{ 2, 3, 4 }, p.curptn);
    try std.testing.expectEqual([3]u8{ 30, 31, 32 }, p.tmppos);
}

test "syncPlayback advances the row on a tempo tick and resets on PTNPOS=0" {
    var e = Editor.init();
    try e.load(tune);
    var mem = [_]u8{0} ** 65536;
    // channel 0: tempo program 0 starts at TMPPOS 9 (RESTEMP+1)
    const b = ed.player_base;
    mem[b + ed.off_tmppos] = 9;
    mem[b + ed.off_spdcnt] = 3;
    mem[b + ed.off_ptnpos] = 5;
    mem[b + ed.off_seqpos] = 7;
    mem[b + ed.off_curptn] = 2;
    mem[ed.tempo_table + 9] = 3; // tempo 3: the counter has reached it
    e.view.ptrowpos[0] = 4;
    e.syncPlayback(&mem, true);
    try std.testing.expectEqual(@as(u8, 5), e.view.ptrowpos[0]);
    try std.testing.expectEqual(@as(u8, 7), e.view.olstart[0]);
    try std.testing.expectEqual(@as(u8, 2), e.view.played_curptn[0]);

    // PTNPOS 0 means a new pattern: the editor row resets
    mem[b + ed.off_ptnpos] = 0;
    e.syncPlayback(&mem, true);
    try std.testing.expectEqual(@as(u8, 0), e.view.ptrowpos[0]);

    // stopped playback never counts
    mem[b + ed.off_ptnpos] = 5;
    mem[b + ed.off_spdcnt] = 3;
    e.view.ptrowpos[0] = 4;
    e.syncPlayback(&mem, false);
    try std.testing.expectEqual(@as(u8, 4), e.view.ptrowpos[0]);
}
