// --------------------------------------------------------------------------
// The editor's effects, done by the host: the file dialog's listing / load / save on the floppy and C:
// (files.zig), playing (play.zig), quitting. The library is pure and says WHAT; this does it and
// reports the result back to the dialog (filerResult: the dialog's own error line).
// --------------------------------------------------------------------------
const std = @import("std");
const kh = @import("keys.zig");
const filer = @import("filer.zig");
const Editor = @import("editor.zig").Editor;
const files = @import("files.zig");
const Play = @import("play.zig").Play;

pub const START_SONG = "FLASHBAK.SWM";

pub const Session = struct {
    ed: *Editor,
    io: []u8, // a song's bytes, both ways (the largest song's file is under 35 KB)
    play: Play = .{},
    wants_quit: bool = false,
    exit_ask: bool = false, // "DO YOU REALLY WANT TO EXIT? (Y/N)" is up
    last_fail: ?files.Fail = null, // the last file error, for the harness and the log

    /// Open the example song off the floppy, as the C cart's key simulator does at start.
    pub fn openStart(self: *Session) bool {
        const bytes = files.read(START_SONG, self.io) catch |e| {
            self.last_fail = e;
            return false;
        };
        self.ed.load(bytes) catch return false;
        return true;
    }

    pub fn apply(self: *Session, eff: kh.Effect) void {
        switch (eff) {
            .play_song => |follow| self.startPlay(.song, follow),
            .play_markers => |follow| self.startPlay(.song, follow), // from the orderlist marks: from the top for now
            .play_pattern => |follow| self.startPlay(.pattern, follow),
            .stop_or_cont => self.play.stopOrCont(self.ed),
            .need_listing => self.listing(),
            .load_file => |ref| self.load(ref),
            .save_file => |ref| self.save(ref),
            .quit => self.quit(),
            else => {},
        }
    }

    fn startPlay(self: *Session, mode: @import("player.zig").Mode, follow: bool) void {
        self.ed.view.followp = follow;
        _ = self.play.start(self.ed, mode);
    }

    pub fn quit(self: *Session) void {
        self.play.out.close(); // the sound side's SID stops with the program
        self.wants_quit = true;
    }

    fn listing(self: *Session) void {
        var entries: [filer.max_files]filer.Entry = undefined;
        const ext = extOf(self.ed.view.filer.kind);
        const n = files.listing(&ext, &entries);
        self.ed.filerListing(entries[0..n], false);
    }

    fn load(self: *Session, ref: kh.FileRef) void {
        const ok = self.loadFile(ref);
        self.ed.filerResult(ok);
    }

    fn loadFile(self: *Session, ref: kh.FileRef) bool {
        if (ref.kind != .tune) return false; // instrument and config files are not read here yet
        const bytes = files.read(ref.name.buf[0..ref.name.len], self.io) catch |e| {
            self.last_fail = e;
            return false;
        };
        self.ed.load(bytes) catch return false;
        self.play.halt(self.ed);
        return true;
    }

    fn save(self: *Session, ref: kh.FileRef) void {
        self.ed.filerResult(self.saveFile(ref));
    }

    fn saveFile(self: *Session, ref: kh.FileRef) bool {
        if (ref.kind != .tune) return false;
        const n = self.ed.save(self.io) catch return false;
        files.write(ref.name.buf[0..ref.name.len], self.io[0..n]) catch |e| {
            self.last_fail = e;
            return false;
        };
        return true;
    }
};

fn extOf(kind: filer.Kind) [4]u8 {
    return switch (kind) {
        .tune => ".SWM".*,
        .instrument => ".SWI".*,
        .config => ".CFG".*,
    };
}

test "extOf names the dialog's extension" {
    try std.testing.expectEqualStrings(".SWM", &extOf(.tune));
    try std.testing.expectEqualStrings(".CFG", &extOf(.config));
}
