// --------------------------------------------------------------------------
// menu_test.zig — Part 4 checks: the main menu (menu.zig) and its keyhandler
// wiring (keys.zig). Uses tunes/FLASHITBACK.SWM as the starting tune.
// --------------------------------------------------------------------------

const std = @import("std");
const swm = @import("swm.zig");
const dsp = @import("display.zig");
const kh = @import("keys.zig");
const menu = @import("menu.zig");
const filer = @import("filer.zig");

const tune = @embedFile("tunes/FLASHITBACK.SWM");

var song: swm.Song = .{};
var view: dsp.View = .{};
var screen: dsp.Screen = .{};

fn reset() !void {
    song = .{};
    view = .{};
    screen = .{};
    try swm.load(&song, tune);
    view.mutesolo = .{
        song.header[swm.H_MUTE],
        song.header[swm.H_MUTE + 1],
        song.header[swm.H_MUTE + 2],
    };
}

fn key(code: u6) kh.Key {
    return .{ .code = code };
}

fn expectRowAt(row: usize, col: usize, text: []const u8) !void {
    for (text, 0..) |ch, i| {
        try std.testing.expectEqual(ch, screen.chars[row][col + i]); // dispmenu copies menutxt verbatim (menu.inc): ASCII
    }
}

fn expectRow(row: usize, text: []const u8) !void {
    try expectRowAt(row, menu.xpos, text);
}

fn expectColour(row: usize, col: u4) !void {
    for (0..menu.cols) |i| {
        try std.testing.expectEqual(col, screen.colours[row][menu.xpos + i]);
    }
}

/// Put the cursor on a menu row and press RETURN.
fn choose(row: u8) kh.Effect {
    view.menucurpos = row;
    return kh.handle(&song, &view, key(kh.ret_));
}

// -- rendering ---------------------------------------------------------------

test "draw paints the 22x19 menu block at (menuypos, menuxpos)" {
    try reset();
    view.menucurpos = menu.firstcpos;
    menu.draw(&song, &view, &screen);
    try expectRow(2, "*******************");
    try expectRow(3, "*  - MAIN MENU -  *");
    try expectRow(4, "* --------------- *");
    try expectRow(5, "*    SAVE TUNE    *");
    try expectRow(23, "*******************");
    for (2..24) |r| {
        try std.testing.expectEqual(@as(u8, '*'), screen.chars[r][menu.xpos]);
        try std.testing.expectEqual(@as(u8, '*'), screen.chars[r][menu.xpos + menu.cols - 1]);
    }
    // the cursor row is bright, the rest is the theme background
    try expectColour(5, 15);
    try expectColour(4, 14);
}

test "draw shows the live drive, defptlen, theme, layout and toggles" {
    try reset();
    view.menucurpos = 0xff; // no highlight: plain menu rows
    view.devicen = 23;
    song.header[swm.H_DEFLEN] = 0x2a;
    view.themeno = 4;
    view.keybtyp = 0x44;
    menu.draw(&song, &view, &screen);
    try expectRow(9, "* SELECT DRIVE:23 *"); // row 7
    try expectRow(12, "* DEF.PATT.LEN:2A *"); // row 10
    try expectRow(15, "* COLOR:  BLUISH  *"); // row 13, theme 4
    try expectRow(16, "* KEY-LAYOUT: DMC *"); // row 14
    // default confbits = %00001001: all four switches are off
    try expectRow(17, "* AUTO-INSTR: OFF *");
    try expectRow(18, "* AUTOFOLLOW: OFF *");
    try expectRow(19, "* HIDE RBARS: OFF *");
    try expectRow(20, "* CHORD-NOTE: OFF *");
    view.confbits = 0xff;
    view.cfgstat = '!';
    view.framesp = 8;
    menu.draw(&song, &view, &screen);
    try expectRow(17, "* AUTO-INSTR: ON  *");
    try expectRow(18, "* AUTOFOLLOW: ON  *");
    try expectRow(19, "* HIDE RBARS: ON  *");
    try expectRow(20, "* CHORD-NOTE: ON  *");
    try expectRow(11, "* FRAMESPEED: 8X  *");
    try expectRow(21, "*   SAVE CONFIG ! *");
}

test "help mode replaces the menu with the 20-row help text" {
    try reset();
    view.helpmode = true;
    menu.draw(&song, &view, &screen);
    try expectRow(2, "F1/F2 PLAY ALL/MARK");
    try expectRow(3, "F3/F4 PLAYPATT/STOP");
    try expectRow(11, "SH+1..3 MUTE/UNMUTE");
    try expectRow(21, " 2026 HERMIT SOFT. ");
    try expectColour(2, 15); // help uses the cursor colour everywhere
    try expectColour(21, 15);
}

test "the are-you-sure box is drawn only while a prompt is pending" {
    try reset();
    for (0..25) |r| @memset(&screen.chars[r], 'x');
    menu.drawPrompt(&view, &screen);
    try std.testing.expectEqual(@as(u8, 'x'), screen.chars[11][10]); // nothing pending
    view.menuprompt = menu.prompt_tune;
    menu.drawPrompt(&view, &screen);
    try expectRowAt(11, menu.xpos + 1, "*****************");
    try expectRowAt(12, menu.xpos + 1, "* ARE YOU SURE? *");
    try expectRowAt(13, menu.xpos + 1, "*  (Y/N) (I/N)  *");
    try expectRowAt(14, menu.xpos + 1, "*****************");
    try std.testing.expectEqual(@as(u4, 1), screen.colours[12][10]);
}

// -- cursor + row editors ----------------------------------------------------

test "menu cursor wraps and freezes in help mode" {
    try reset();
    view.menumode = true;
    view.menucurpos = menu.lastcrpos;
    _ = kh.handle(&song, &view, key(kh.crsr_d));
    try std.testing.expectEqual(menu.firstcpos, view.menucurpos);
    view.menucurpos = menu.firstcpos;
    _ = kh.handle(&song, &view, .{ .code = kh.crsr_d, .shift = true });
    try std.testing.expectEqual(menu.lastcrpos, view.menucurpos);
    view.helpmode = true;
    _ = kh.handle(&song, &view, key(kh.crsr_d));
    try std.testing.expectEqual(menu.lastcrpos, view.menucurpos);
}

test "drive row: +/- step the device 8..30 and wrap" {
    try reset();
    view.menumode = true;
    view.menucurpos = menu.drivemenupt;
    _ = kh.handle(&song, &view, key(kh.plus));
    try std.testing.expectEqual(@as(u8, 9), view.devicen);
    view.devicen = menu.max_device;
    _ = kh.handle(&song, &view, key(kh.plus));
    try std.testing.expectEqual(menu.min_device, view.devicen);
    _ = kh.handle(&song, &view, key(kh.minus));
    try std.testing.expectEqual(menu.max_device, view.devicen);
    view.devicen = 9;
    _ = kh.handle(&song, &view, key(kh.minus));
    try std.testing.expectEqual(@as(u8, 8), view.devicen);
}

test "def.patt.len row: +/- roll over the asm's 1..248 window" {
    try reset();
    view.menumode = true;
    view.menucurpos = menu.ptlenmenupt;
    song.header[swm.H_DEFLEN] = 32;
    _ = kh.handle(&song, &view, key(kh.plus));
    try std.testing.expectEqual(@as(u8, 33), song.header[swm.H_DEFLEN]);
    song.header[swm.H_DEFLEN] = 248;
    _ = kh.handle(&song, &view, key(kh.plus));
    try std.testing.expectEqual(@as(u8, 1), song.header[swm.H_DEFLEN]);
    song.header[swm.H_DEFLEN] = 1;
    _ = kh.handle(&song, &view, key(kh.minus));
    try std.testing.expectEqual(@as(u8, 248), song.header[swm.H_DEFLEN]);
}

test "+/- on any other row select the instrument" {
    try reset();
    view.menumode = true;
    view.menucurpos = menu.firstcpos; // SAVE TUNE
    _ = kh.handle(&song, &view, key(kh.plus));
    try std.testing.expectEqual(@as(u8, 2), view.selinst);
    _ = kh.handle(&song, &view, key(kh.minus));
    try std.testing.expectEqual(@as(u8, 1), view.selinst);
    try std.testing.expectEqual(menu.firstcpos, view.menucurpos); // cursor untouched
}

// -- RETURN on every row -----------------------------------------------------

test "RETURN rows 1-4 open the filer for the right file" {
    try reset();
    view.menumode = true;
    try std.testing.expectEqual(kh.Effect.redraw, choose(3)); // SAVE TUNE: name typer
    try std.testing.expect(!view.menumode); // the dialog returns through retoedi
    try std.testing.expect(view.filer.open);
    try std.testing.expectEqual(filer.Kind.tune, view.filer.kind);
    try std.testing.expectEqual(filer.Mode.save, view.filer.mode);
    try std.testing.expect(view.filer.editauth);
    try std.testing.expectEqual(@as(u8, ' '), view.filer.name[0]);
    view.filer = .{};

    view.menumode = true;
    try std.testing.expectEqual(kh.Effect.need_listing, choose(4)); // LOAD TUNE
    try std.testing.expect(view.filer.open);
    try std.testing.expectEqual(filer.Kind.tune, view.filer.kind);
    try std.testing.expectEqual(filer.Mode.load, view.filer.mode);
    try std.testing.expect(!view.filer.editauth);
    view.filer = .{};

    view.menumode = true;
    try std.testing.expectEqual(kh.Effect.redraw, choose(5)); // SAVE INST
    try std.testing.expectEqual(filer.Kind.instrument, view.filer.kind);
    view.filer = .{};

    view.menumode = true;
    try std.testing.expectEqual(kh.Effect.need_listing, choose(6)); // LOAD INST
    try std.testing.expectEqual(filer.Kind.instrument, view.filer.kind);
    view.filer = .{};
}

test "RETURN toggles: drive, autodir, framespeed, theme, layout, confbits" {
    try reset();
    view.menumode = true;
    _ = choose(menu.drivemenupt);
    try std.testing.expectEqual(@as(u8, 9), view.devicen);
    _ = choose(8); // AutoDir
    try std.testing.expectEqual(@as(u8, 1), view.confbits2);
    _ = choose(9); // SetFspd
    try std.testing.expectEqual(@as(u8, 2), view.framesp);
    const defpt = song.header[swm.H_DEFLEN];
    _ = choose(10); // SetDefPtLen
    try std.testing.expectEqual(defpt +% 1, song.header[swm.H_DEFLEN]);
    for (0..menu.theme_count) |_| _ = choose(13); // SwitchTheme
    try std.testing.expectEqual(@as(u8, 0), view.themeno); // wrapped
    _ = choose(14); // KeyLayout
    try std.testing.expectEqual(@as(u8, 0x2c), view.keybtyp);
    _ = choose(14);
    try std.testing.expectEqual(@as(u8, 0x44), view.keybtyp);
    _ = choose(14);
    try std.testing.expectEqual(@as(u8, 0x88), view.keybtyp);
    _ = choose(14);
    try std.testing.expectEqual(@as(u8, 0), view.keybtyp);
    const bits = [_]u8{ 0x80, 0x04, 0x02, 0x40 }; // AutoIns/AutoFollow/RasterBar/ChordNote
    for (bits, 15..) |b, row| {
        const before = view.confbits;
        _ = choose(@intCast(row));
        try std.testing.expectEqual(before ^ b, view.confbits);
        try std.testing.expect(view.menumode); // toggles leave the menu open
    }
}

test "RETURN on SAVE CONFIG stays in the menu; INSTANT HELP switches display" {
    try reset();
    view.menumode = true;
    try std.testing.expectEqual(kh.Effect.redraw, choose(19)); // config filer
    try std.testing.expectEqual(filer.Kind.config, view.filer.kind);
    view.filer = .{};
    view.menumode = true;
    menu.setCfgStat(&view, false);
    try std.testing.expectEqual(@as(u8, '!'), view.cfgstat);
    menu.setCfgStat(&view, true);
    try std.testing.expectEqual(@as(u8, ' '), view.cfgstat);
    try std.testing.expectEqual(kh.Effect.redraw, choose(20));
    try std.testing.expect(view.helpmode);
    try std.testing.expect(view.menumode);
    _ = choose(20);
    try std.testing.expect(!view.helpmode);
}

// -- kill items --------------------------------------------------------------

test "KILL TUNE asks first; N leaves the tune alone and closes the menu" {
    try reset();
    view.menumode = true;
    const before = song.pats[0][0];
    try std.testing.expectEqual(kh.Effect.none, choose(11)); // initunt
    try std.testing.expectEqual(menu.prompt_tune, view.menuprompt);
    _ = kh.handle(&song, &view, key(kh.plus)); // only Y/N count
    try std.testing.expectEqual(menu.prompt_tune, view.menuprompt);
    try std.testing.expectEqual(kh.Effect.redraw, kh.handle(&song, &view, key(kh.n_)));
    try std.testing.expectEqual(menu.prompt_none, view.menuprompt);
    try std.testing.expect(!view.menumode);
    try std.testing.expectEqual(before, song.pats[0][0]);
}

test "KILL TUNE (Y) blanks the song to defptlen and a default subtune" {
    try reset();
    view.menumode = true;
    song.header[swm.H_DEFLEN] = 40;
    const funk0 = song.funk[0];
    _ = choose(11);
    try std.testing.expectEqual(kh.Effect.redraw, kh.handle(&song, &view, key(kh.y_)));
    // counts zeroed, patterns rebuilt at the editable defptlen
    try std.testing.expectEqual(@as(u8, 0), song.header[swm.H_SEQAMO]);
    try std.testing.expectEqual(@as(u8, 0), song.header[swm.H_PTAMOU]);
    try std.testing.expectEqual(@as(u8, 0), song.header[swm.H_TMPLEN]);
    try std.testing.expectEqual(@as(u8, 40), song.ptn_len[1]);
    try std.testing.expectEqual(@as(u8, 41), song.ptn_size[1]);
    try std.testing.expectEqual(@as(u8, 0), song.pats[0][0]);
    try std.testing.expectEqual(@as(u8, 0xff), song.pats[0][40]);
    try std.testing.expectEqual(@as(u8, 40), song.ptn_len[100]);
    // one default subtune: patterns 1,2,3, the other orderlists empty
    for (0..3) |t| {
        try std.testing.expectEqual(@as(u8, @intCast(t + 1)), song.seqs[t][0]);
        try std.testing.expectEqual(@as(u8, 0xfe), song.seqs[t][1]);
        try std.testing.expectEqual(@as(u8, 2), song.seq_len[t]);
    }
    try std.testing.expectEqual(@as(u8, 0xfe), song.seqs[3][0]);
    try std.testing.expectEqual(@as(u8, 1), song.seq_len[3]);
    // tempo table empty, subtune 0's funk pair survives, unused ones reset
    for (song.tempo) |v| try std.testing.expectEqual(@as(u8, 0x80), v);
    try std.testing.expectEqualSlices(u8, &funk0, &song.funk[0]);
    try std.testing.expectEqualSlices(u8, &swm.default_funk, &song.funk[1]);
    // retsubt's view reset
    try std.testing.expectEqual(@as(u8, 0), view.selsubt);
    try std.testing.expectEqual(@as(u8, 1), view.selinst);
    try std.testing.expectEqual(@as(u8, 1), view.selchor);
    try std.testing.expectEqual(@as(u8, 1), view.seltemp);
}

test "the killed tune still saves and reloads" {
    try reset();
    view.menumode = true;
    song.header[swm.H_DEFLEN] = 40;
    _ = choose(11);
    _ = kh.handle(&song, &view, key(kh.y_));
    var out: [tune.len + 128]u8 = undefined;
    const n = try swm.save(&song, &out);
    try std.testing.expect(n < out.len);
    var back: swm.Song = .{};
    try swm.load(&back, out[0..n]);
    try std.testing.expectEqual(@as(u8, 40), back.ptn_len[1]);
    try std.testing.expectEqual(@as(u8, 1), back.seqs[0][0]);
    try std.testing.expectEqual(@as(u8, 3), back.seqs[2][0]);
}

test "KILL INST&CHORD (I) rebuilds instruments and chord end signals" {
    try reset();
    view.menumode = true;
    song.insts[5][0] = 0x42;
    song.chords[1] = 0x12;
    _ = choose(12);
    try std.testing.expectEqual(menu.prompt_inst, view.menuprompt);
    _ = kh.handle(&song, &view, key(kh.i_)); // I also answers yes
    try std.testing.expectEqual(@as(u8, 0), song.header[swm.H_INSTAM]);
    try std.testing.expectEqual(@as(u8, 0), song.header[swm.H_CHRDLE]);
    try std.testing.expectEqual(@as(u8, 0b00011010), song.insts[5][0]); // dummyihdr
    try std.testing.expectEqual(@as(u8, 0x7f), song.chords[1]);
    try std.testing.expectEqual(@as(u8, 0x7f), song.chords[0]);
}

// -- menu open/close through the keyhandler ----------------------------------

test "shift+F7 opens the menu; any key drops the title row; F7 closes it" {
    try reset();
    view.curwind = 0;
    try std.testing.expectEqual(kh.Effect.menu, kh.handle(&song, &view, .{ .code = kh.f7, .shift = true }));
    try std.testing.expect(view.menumode);
    try std.testing.expectEqual(@as(u8, 0), view.menupoint);
    try std.testing.expectEqual(menu.firstcpos, view.menucurpos);
    try std.testing.expect(view.titledi); // dispaut
    _ = kh.handle(&song, &view, key(kh.crsr_d));
    try std.testing.expect(!view.titledi);
    try std.testing.expectEqual(menu.firstcpos + 1, view.menucurpos);
    try std.testing.expectEqual(kh.Effect.redraw, kh.handle(&song, &view, key(kh.f7)));
    try std.testing.expect(!view.menumode);
}

test "RUN/STOP and F7 both leave help mode" {
    try reset();
    view.menumode = true;
    view.helpmode = true;
    _ = kh.handle(&song, &view, key(kh.stop));
    try std.testing.expect(!view.menumode);
    try std.testing.expect(!view.helpmode);
    view.menumode = true;
    view.helpmode = true;
    _ = kh.handle(&song, &view, key(kh.f7));
    try std.testing.expect(!view.menumode);
    try std.testing.expect(!view.helpmode);
}
