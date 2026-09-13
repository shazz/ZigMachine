// --------------------------------------------------------------------------
// The desktop's directory MODEL: the host-packed disk FAT plus the in-RAM
// folder tree. No Gui, no drawing: a window only asks it questions (how many
// items in this directory, in what order), so it is natively testable — see
// dirmodel_test.zig.
// --------------------------------------------------------------------------
const std = @import("std");
const stamp = @import("stamp.zig");

// The mounted disk's FAT, packed by the host into `disk_dir`. Shown as icons in
// the FLOPPY window; double-clicking a program launches it.
pub const MAX_FILES: usize = 12;
// Host-packed directory entry: 16-byte name · 1 type (0 = program/cart, 1 =
// data) · 4 size (u32 LE) · 4 date (u32 LE, YYYYMMDD). Must match the packer in
// docs/sealed-loader.js.
pub const FILE_ENT: usize = 25;

// Folders live only in RAM (the mounted disk is a flat read-only FAT).
pub const MAX_FOLDERS: usize = 8;
pub const ROOT: i16 = -1; // a directory id: the root disk (A:\), else a folder index

pub const SortKey = enum { name, date, size, type };

pub const Folder = struct {
    name: [12]u8 = [_]u8{0} ** 12,
    nlen: u8 = 0,
    parent: i16 = ROOT,
    title: [40]u8 = [_]u8{0} ** 40, // "A:\FOO\BAR" for the window title
    tlen: u8 = 0,
};

pub const DirModel = struct {
    disk_dir: [MAX_FILES * FILE_ENT]u8 = [_]u8{0} ** (MAX_FILES * FILE_ENT), // host-filled FAT
    n_disk: u8 = 0,
    folders: [MAX_FOLDERS]Folder = [_]Folder{.{}} ** MAX_FOLDERS,
    n_folders: u8 = 0,
    new_seq: u8 = 0, // auto-name counter for New Folder

    pub fn name(self: *const DirModel, i: usize) []const u8 {
        const s = self.disk_dir[i * FILE_ENT .. i * FILE_ENT + 16];
        var n: usize = 0;
        while (n < 16 and s[n] != 0) : (n += 1) {}
        return s[0..n];
    }
    pub fn kind(self: *const DirModel, i: usize) u8 {
        return self.disk_dir[i * FILE_ENT + 16];
    }
    pub fn size(self: *const DirModel, i: usize) u32 {
        return std.mem.readInt(u32, self.disk_dir[i * FILE_ENT + 17 ..][0..4], .little);
    }
    pub fn date(self: *const DirModel, i: usize) u32 { // YYYYMMDD
        return std.mem.readInt(u32, self.disk_dir[i * FILE_ENT + 21 ..][0..4], .little);
    }
    pub fn usedBytes(self: *const DirModel) u32 {
        var used: u32 = 0;
        var k: u8 = 0;
        while (k < self.n_disk) : (k += 1) used += self.size(k);
        return used;
    }

    // The program a .launch action refers to: `file` if that is a program, else
    // the disk's first one (the FLOPPY-as-launcher case names no file, -1). Empty
    // when the disk holds none, so the caller can report it instead of booting nothing.
    pub fn launchName(self: *const DirModel, file: i16) []const u8 {
        if (file >= 0 and file < self.n_disk) {
            const i: usize = @intCast(file);
            if (self.kind(i) == 0) return self.name(i);
        }
        var i: usize = 0;
        while (i < self.n_disk) : (i += 1) if (self.kind(i) == 0) return self.name(i);
        return &.{};
    }

    // The display order of the disk's files for `sort` (a permutation of 0..n_disk).
    pub fn order(self: *const DirModel, sort: SortKey) [MAX_FILES]u8 {
        var ord: [MAX_FILES]u8 = undefined;
        var i: u8 = 0;
        while (i < self.n_disk) : (i += 1) ord[i] = i;
        var a: usize = 1; // insertion sort (n_disk <= 12)
        while (a < self.n_disk) : (a += 1) {
            const v = ord[a];
            var b: usize = a;
            while (b > 0 and self.less(sort, v, ord[b - 1])) : (b -= 1) ord[b] = ord[b - 1];
            ord[b] = v;
        }
        return ord;
    }
    fn less(self: *const DirModel, sort: SortKey, x: u8, y: u8) bool {
        switch (sort) {
            .type => if (self.kind(x) != self.kind(y)) return self.kind(x) < self.kind(y), // programs first
            .size => if (self.size(x) != self.size(y)) return self.size(x) > self.size(y), // largest first
            .date => if (self.date(x) != self.date(y)) return self.date(x) > self.date(y), // newest first
            .name => {},
        }
        return std.mem.lessThan(u8, self.name(x), self.name(y)); // name (and tie-break)
    }

    // Add (or update) a data file. Returns false when the directory is full — the
    // caller must NOT report a save that did not happen.
    pub fn put(self: *DirModel, file_name: []const u8, bytes: u32) bool {
        var i: u8 = 0;
        while (i < self.n_disk) : (i += 1) {
            if (std.mem.eql(u8, self.name(i), file_name)) break;
        }
        if (i == self.n_disk) {
            if (self.n_disk >= MAX_FILES) return false;
            self.n_disk += 1;
        }
        const e = @as(usize, i) * FILE_ENT;
        @memset(self.disk_dir[e .. e + FILE_ENT], 0);
        @memcpy(self.disk_dir[e .. e + file_name.len], file_name);
        self.disk_dir[e + 16] = 1; // data file
        std.mem.writeInt(u32, self.disk_dir[e + 17 ..][0..4], bytes, .little);
        std.mem.writeInt(u32, self.disk_dir[e + 21 ..][0..4], stamp.DEFAULT_DATE, .little);
        return true;
    }
    pub fn remove(self: *DirModel, idx: usize) void {
        var i = idx;
        while (i + 1 < self.n_disk) : (i += 1) {
            const dst = i * FILE_ENT;
            const src = (i + 1) * FILE_ENT;
            @memcpy(self.disk_dir[dst .. dst + FILE_ENT], self.disk_dir[src .. src + FILE_ENT]);
        }
        if (self.n_disk > 0) self.n_disk -= 1;
    }
    pub fn renameFile(self: *DirModel, i: usize, nm: []const u8) void {
        const b = i * FILE_ENT;
        var k: usize = 0;
        while (k < 16) : (k += 1) self.disk_dir[b + k] = if (k < nm.len) nm[k] else 0;
    }

    // --- folders: an in-memory tree over the flat disk ---
    pub fn folderName(self: *const DirModel, f: u8) []const u8 {
        return self.folders[f].name[0..self.folders[f].nlen];
    }
    pub fn fileCount(self: *const DirModel, dir: i16) usize {
        return if (dir == ROOT) self.n_disk else 0; // disk files exist only at root
    }
    pub fn folderCount(self: *const DirModel, dir: i16) usize {
        var n: usize = 0;
        var k: u8 = 0;
        while (k < self.n_folders) : (k += 1) {
            if (self.folders[k].parent == dir) n += 1;
        }
        return n;
    }
    pub fn nthFolder(self: *const DirModel, dir: i16, rank: usize) u8 {
        var seen: usize = 0;
        var k: u8 = 0;
        while (k < self.n_folders) : (k += 1) {
            if (self.folders[k].parent != dir) continue;
            if (seen == rank) return k;
            seen += 1;
        }
        return 0;
    }

    // Create a folder under `parent` named `typed` (empty -> the classic
    // auto-name, so OK on the NEW FOLDER box is never a dead end). No-op when full.
    pub fn addFolder(self: *DirModel, parent: i16, typed: []const u8) void {
        if (self.n_folders >= MAX_FOLDERS) return;
        const f = &self.folders[self.n_folders];
        f.* = .{ .parent = parent };
        if (typed.len > 0) {
            f.nlen = @intCast(@min(typed.len, f.name.len));
            @memcpy(f.name[0..f.nlen], typed[0..f.nlen]);
        } else {
            self.new_seq += 1;
            const nm = std.fmt.bufPrint(&f.name, "NEWDIR{d}", .{self.new_seq}) catch "NEWDIR";
            f.nlen = @intCast(nm.len);
        }
        self.setTitle(f);
        self.n_folders += 1;
    }
    pub fn renameFolder(self: *DirModel, idx: u8, nm: []const u8) void {
        const f = &self.folders[idx];
        f.nlen = @intCast(@min(nm.len, f.name.len));
        @memcpy(f.name[0..f.nlen], nm[0..f.nlen]);
        self.setTitle(f);
    }
    // The window title is the folder's full path: A:\ + each parent's title.
    fn setTitle(self: *const DirModel, f: *Folder) void {
        const nm = f.name[0..f.nlen];
        const t = if (f.parent == ROOT)
            std.fmt.bufPrint(&f.title, "A:\\{s}", .{nm}) catch "A:\\"
        else blk: {
            const par = self.folders[@intCast(f.parent)];
            break :blk std.fmt.bufPrint(&f.title, "{s}\\{s}", .{ par.title[0..par.tlen], nm }) catch "A:\\";
        };
        f.tlen = @intCast(t.len);
    }
};
