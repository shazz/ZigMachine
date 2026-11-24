// --------------------------------------------------------------------------
// filer_test.zig — Part 4: the file dialog (filer.zig) driven through
// keys.zig. Covers the four prompt_4 cases: menu -> LOAD -> pick a file from a
// fake listing, SAVE round-trip through swm.save, Escape at every level, and
// the empty directory listing.
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

fn reset() !void {
    song = .{};
    view = .{};
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

fn nameEntry(text: []const u8, blocks: u16) filer.Entry {
    var e = filer.Entry{ .blocks = blocks };
    e.len = @intCast(text.len);
    @memcpy(e.name[0..text.len], text);
    return e;
}

/// One menu row press (RETURN) after putting the cursor on it.
fn choose(row: u8) kh.Effect {
    view.menumode = true;
    view.menucurpos = row;
    return kh.handle(&song, &view, key(kh.ret_));
}

fn expectName(ref: kh.FileRef, text: []const u8) !void {
    try std.testing.expectEqual(@as(u8, @intCast(text.len)), ref.name.len);
    try std.testing.expectEqualStrings(text, ref.name.buf[0..ref.name.len]);
}

// -- the four Part-4 cases ---------------------------------------------------

test "menu -> LOAD TUNE -> fake listing -> load effect" {
    try reset();
    try std.testing.expectEqual(kh.Effect.need_listing, choose(4)); // LOAD TUNE
    try std.testing.expect(view.filer.open);

    const entries = [_]filer.Entry{
        nameEntry("FLASHITBACK", 64),
        nameEntry("OTHER", 3),
    };
    kh.filerListing(&view, &entries, true);
    try std.testing.expectEqual(filer.Window.selector, view.filer.window);
    try std.testing.expectEqual(@as(u8, 2), view.filer.count);

    // RETURN on the first entry registers its name plus the .SWM extension
    const eff = kh.handle(&song, &view, key(kh.ret_));
    switch (eff) {
        .load_file => |ref| {
            try std.testing.expectEqual(kh.FileKind.tune, ref.kind);
            try expectName(ref, "FLASHITBACK.SWM");
        },
        else => return error.WrongEffect,
    }
    try std.testing.expect(!view.filer.open);

    // the host's part: the bytes swm.load reads are the fixture
    var loaded: swm.Song = .{};
    try swm.load(&loaded, tune);
    try std.testing.expectEqualStrings("HERMIT: FLASH IT BACK", loaded.header[swm.H_AUTHOR .. swm.H_AUTHOR + 21]);
}

test "SAVE TUNE round-trips through swm.save" {
    try reset();
    try std.testing.expectEqual(kh.Effect.redraw, choose(3)); // SAVE TUNE
    try std.testing.expect(view.filer.open);
    try std.testing.expect(view.filer.editauth); // savetun `inc editauth`

    // type NEW in the name typer, then RETURN
    for ([_]u6{ kh.n_, kh.e_, kh.w_ }) |c| _ = kh.handle(&song, &view, key(c));
    try std.testing.expectEqualStrings("NEW", view.filer.name[0..3]);
    const eff = kh.handle(&song, &view, key(kh.ret_));
    var ref: kh.FileRef = undefined;
    switch (eff) {
        .save_file => |r| ref = r,
        else => return error.WrongEffect,
    }
    try expectName(ref, "NEW.SWM");

    // host: swm.save -> swm.load must give the same tune back
    var buf: [65536]u8 = undefined;
    const n = try swm.save(&song, &buf);
    var again: swm.Song = .{};
    try swm.load(&again, buf[0..n]);
    try std.testing.expectEqualSlices(u8, &song.header, &again.header);
    var buf2: [65536]u8 = undefined;
    const n2 = try swm.save(&again, &buf2);
    try std.testing.expectEqualSlices(u8, buf[0..n], buf2[0..n2]);
}

test "Escape backs out of the filer, menu, help and prompt" {
    try reset();
    // filer: STOP closes it without a file operation
    view.menumode = true;
    view.menucurpos = 4;
    _ = kh.handle(&song, &view, key(kh.ret_));
    kh.filerListing(&view, &.{}, true);
    try std.testing.expectEqual(kh.Effect.close_filer, kh.handle(&song, &view, key(kh.stop)));
    try std.testing.expect(!view.filer.open);

    // menu: STOP closes it
    view.menumode = true;
    _ = kh.handle(&song, &view, key(kh.stop));
    try std.testing.expect(!view.menumode);

    // help mode: STOP closes it
    view.menumode = true;
    view.helpmode = true;
    _ = kh.handle(&song, &view, key(kh.stop));
    try std.testing.expect(!view.menumode);
    try std.testing.expect(!view.helpmode);

    // kill prompt: N refuses and returns to the editor
    view.menumode = true;
    view.menucurpos = 11;
    _ = kh.handle(&song, &view, key(kh.ret_));
    try std.testing.expect(view.menuprompt != menu.prompt_none);
    _ = kh.handle(&song, &view, key(kh.n_));
    try std.testing.expectEqual(@as(u8, menu.prompt_none), view.menuprompt);
    try std.testing.expect(!view.menumode);
}

test "an empty directory listing keeps the name typer and shows no files" {
    try reset();
    _ = choose(4); // LOAD TUNE
    kh.filerListing(&view, &.{}, false);
    try std.testing.expectEqual(@as(u8, 0), view.filer.count);
    try std.testing.expectEqual(filer.Window.name_typer, view.filer.window);
    try std.testing.expect(!view.filer.more);

    // TAB cannot reach an empty selector (setsele: `lda filecnt; beq setfnam`)
    _ = kh.handle(&song, &view, key(kh.ctrl));
    try std.testing.expectEqual(filer.Window.name_typer, view.filer.window);

    // RETURN with an empty name asks for nothing
    try std.testing.expectEqual(kh.Effect.none, kh.handle(&song, &view, key(kh.ret_)));
    try std.testing.expect(view.filer.open);
}

// -- the dialog's own behaviour ---------------------------------------------

test "typing, HOME, INSERT, BACKSPACE and cursor-right edit the name" {
    try reset();
    _ = choose(3); // SAVE TUNE, name typer
    _ = kh.handle(&song, &view, key(kh.a_));
    _ = kh.handle(&song, &view, key(kh.b_));
    _ = kh.handle(&song, &view, key(kh.c_));
    try std.testing.expectEqualStrings("ABC", view.filer.name[0..3]);
    _ = kh.handle(&song, &view, key(kh.home)); // HOME: cursor to 0
    try std.testing.expectEqual(@as(u8, 0), view.filer.name_pos);
    _ = kh.handle(&song, &view, key(kh.pound)); // INSERT at 0
    _ = kh.handle(&song, &view, key(kh.d_));
    try std.testing.expectEqualStrings("DABC", view.filer.name[0..4]);
    _ = kh.handle(&song, &view, key(kh.del)); // BACKSPACE removes D
    try std.testing.expectEqualStrings("ABC", view.filer.name[0..3]);
    _ = kh.handle(&song, &view, key(kh.crsr_r)); // cursor right, no edit
    try std.testing.expectEqualStrings("ABC", view.filer.name[0..3]);
}

test "shift reverses the selector step and the typer cursor" {
    try reset();
    _ = choose(4);
    const entries = [_]filer.Entry{
        nameEntry("ONE", 1),
        nameEntry("TWO", 1),
        nameEntry("THREE", 1),
        nameEntry("FOUR", 1),
    };
    kh.filerListing(&view, &entries, true);
    _ = kh.handle(&song, &view, key(kh.crsr_d)); // +3 -> FOUR
    try std.testing.expectEqual(@as(u8, 3), view.filer.sel);
    _ = kh.handle(&song, &view, .{ .code = kh.crsr_d, .shift = true }); // -3 -> ONE
    try std.testing.expectEqual(@as(u8, 0), view.filer.sel);
    _ = kh.handle(&song, &view, key(kh.crsr_r)); // +1 -> TWO
    try std.testing.expectEqual(@as(u8, 1), view.filer.sel);
    try std.testing.expectEqualStrings("TWO", view.filer.name[0..3]);

    _ = kh.handle(&song, &view, key(kh.ctrl)); // TAB -> name typer
    try std.testing.expectEqual(filer.Window.name_typer, view.filer.window);
    view.filer.name_pos = 2;
    _ = kh.handle(&song, &view, .{ .code = kh.crsr_r, .shift = true }); // back
    try std.testing.expectEqual(@as(u8, 1), view.filer.name_pos);
}

test "author-info editing writes back into the tune header (regauth)" {
    try reset();
    _ = choose(3); // SAVE TUNE
    _ = kh.handle(&song, &view, key(kh.ctrl)); // TAB: name -> author typer
    try std.testing.expectEqual(filer.Window.author_typer, view.filer.window);
    _ = kh.handle(&song, &view, key(kh.x_));
    const eff = kh.handle(&song, &view, key(kh.stop)); // abort, but register
    try std.testing.expectEqual(kh.Effect.close_filer, eff);
    try std.testing.expectEqual(@as(u8, 'X'), song.header[swm.H_AUTHOR]);
}

test "confbits2 auto-directory makes SAVE ask for a listing first" {
    try reset();
    view.confbits2 = 0x01;
    try std.testing.expectEqual(kh.Effect.need_listing, choose(3));
    const entries = [_]filer.Entry{nameEntry("PICKME", 2)};
    kh.filerListing(&view, &entries, true);
    // a save keeps its default name typer; TAB then walks name -> author ->
    // selector because savetun enables author-info editing
    try std.testing.expectEqual(filer.Window.name_typer, view.filer.window);
    _ = kh.handle(&song, &view, key(kh.ctrl));
    try std.testing.expectEqual(filer.Window.author_typer, view.filer.window);
    _ = kh.handle(&song, &view, key(kh.ctrl));
    try std.testing.expectEqual(filer.Window.selector, view.filer.window);
    try std.testing.expectEqualStrings("PICKME", view.filer.name[0..6]);
    const eff = kh.handle(&song, &view, key(kh.ret_));
    switch (eff) {
        .save_file => |ref| try expectName(ref, "PICKME.SWM"),
        else => return error.WrongEffect,
    }
}

test "F1 asks for a fresh listing and the save dialog's TAB skips the author" {
    try reset();
    _ = choose(5); // SAVE INST: no author editing
    try std.testing.expect(!view.filer.editauth);
    try std.testing.expectEqual(kh.Effect.need_listing, kh.handle(&song, &view, key(kh.f1)));
    const entries = [_]filer.Entry{nameEntry("INST1", 1)};
    kh.filerListing(&view, &entries, true);
    _ = kh.handle(&song, &view, key(kh.ctrl)); // name -> selector (no author)
    try std.testing.expectEqual(filer.Window.selector, view.filer.window);
    _ = kh.handle(&song, &view, key(kh.ctrl)); // selector -> name
    try std.testing.expectEqual(filer.Window.name_typer, view.filer.window);
}

test "the save result records an error status for the host" {
    try reset();
    _ = choose(3);
    _ = kh.handle(&song, &view, key(kh.a_));
    _ = kh.handle(&song, &view, key(kh.ret_));
    kh.filerResult(&view, false);
    try std.testing.expectEqual(filer.Status.save_error, view.filer.status);
    _ = choose(4);
    kh.filerListing(&view, &.{}, false);
    kh.filerResult(&view, false);
    try std.testing.expectEqual(filer.Status.not_found, view.filer.status);
}
