// --------------------------------------------------------------------------
// ITEM SELECTOR — GEM's file-choosing dialog (fsel_input), the box every TOS
// program opens for "Load from disc". Since GEM 5 S2 (G21) it is TOS 4's: the
// path as its title, Directory: and Selection:, the list as a little window
// (closer, the mask, nine rows, a scroll column), DRIVE: A..P, OK and Cancel:
// fsel_tree.zig lays it out, fsel_draw.zig draws it with the GEM 5 engine in the
// program look (flat TOS 1 or 3D TOS 4) and acts on a press.
//
// This file is the state: the Directory: line is the path spec (filesel_path.zig),
// editable as TOS's: a click on it moves the caret there, Return or a click in
// the list re-reads it; a folder row (a name added with a trailing backslash)
// opens the folder, the closer goes to the parent, a drive button re-roots the
// spec at that drive. Each of those clears the list and answers `relist`: the
// caller reads the spec (fileSelSpec) and adds the names again (decisions.md:
// the program supplies the names; this file does not touch a disk). The drives
// shown are the ones the program says are there (fileSelDrives, the GEMDOS
// drive map), plus the spec's own.
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");
const NameField = @import("namefield.zig").NameField;
const list_mod = @import("filesel_list.zig");
const fpath = @import("filesel_path.zig");

pub const MAX_FILES = list_mod.MAX_FILES;
pub const ROWS = list_mod.ROWS;

pub const Result = enum { none, ok, cancel, relist };

pub const FileSel = struct {
    active: bool = false,
    path: fpath.PathField = .{}, // the Directory: line, the spec the list shows
    on_path: bool = false, // typing goes to the Directory: line (else the Selection)
    list: list_mod.List = .{},
    name: NameField = .{}, // the Selection: field
    drives: u16 = 0, // the program's drive map (bit 0 = A:), 0: not given

    pub fn open(self: *FileSel, start: []const u8) void {
        const d = self.drives;
        self.* = .{ .active = true, .drives = d };
        self.path.set(start);
    }

    pub fn spec(self: *const FileSel) []const u8 {
        return self.path.text();
    }

    pub fn add(self: *FileSel, name: []const u8) void {
        self.list.add(name);
    }

    pub fn chosen(self: *const FileSel) []const u8 {
        return self.name.text();
    }
    pub fn key(self: *FileSel, cp: u32) void {
        if (!self.active) return;
        if (self.on_path) {
            if (cp == 8) self.path.deleteBack() else if (cp >= 32 and cp < 127) self.path.insert(@intCast(cp));
            return;
        }
        if (cp == 8) self.name.deleteBack() else if (cp >= 32 and cp < 127) self.name.insert(@intCast(cp));
    }

    pub fn process(self: *FileSel, g: *gui.Gui) Result {
        if (!self.active) return .none;
        return @import("fsel_draw.zig").frame(self, g);
    }

    // The list emptied for the caller to fill from the (new) spec; the Selection keeps the caret.
    pub fn relist(self: *FileSel) Result {
        self.list = .{};
        self.on_path = false;
        return .relist;
    }

    pub fn close(self: *FileSel, r: Result) Result {
        self.active = false;
        return r;
    }

    /// The spec's drive, 0 = A: (a bare mask, ST Replay's `*.RAW`: A:).
    pub fn driveOf(self: *const FileSel) u8 {
        const s = self.path.text();
        if (s.len < 2 or s[1] != ':') return 0;
        const c = s[0] & 0xDF; // upper case
        return if (c >= 'A' and c <= 'P') c - 'A' else 0;
    }

    /// The drive buttons that are enabled: the program's map, A: (the floppy drive is always
    /// there, as TOS's Drvmap: KOS GEMDOS answers for A: only once a disk is read), the spec's.
    pub fn drivesShown(self: *const FileSel) u16 {
        return self.drives | 1 | @as(u16, 1) << @intCast(self.driveOf());
    }

    /// A drive button: the spec re-rooted there (`X:\` + the mask), the list re-read. An absent
    /// drive does nothing.
    pub fn toDrive(self: *FileSel, k: u8) Result {
        if (k > 15 or self.drivesShown() & (@as(u16, 1) << @intCast(k)) == 0) return .none;
        var buf: [fpath.MAX]u8 = undefined;
        const m = fpath.mask(self.path.text());
        const mk = if (m.len == 0) "*.*" else m;
        const n = @min(mk.len, buf.len - 3);
        buf[0] = 'A' + k;
        buf[1] = ':';
        buf[2] = '\\';
        @memcpy(buf[3..][0..n], mk[0..n]);
        self.path.set(buf[0 .. 3 + n]);
        return self.relist();
    }

    /// A list row: a folder opens (relist), a file fills Selection:.
    pub fn pickRow(self: *FileSel, idx: usize) Result {
        if (idx >= self.list.n) return .none;
        if (self.list.isDir(idx)) return if (self.path.enter(self.list.nameAt(idx))) self.relist() else .none;
        self.list.sel = @intCast(idx);
        self.name.set(self.list.nameAt(idx));
        self.on_path = false;
        return .none;
    }
};
