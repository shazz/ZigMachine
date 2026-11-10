// --------------------------------------------------------------------------
// The ITEM SELECTOR's file list: the names (a trailing backslash: a folder), which
// one is picked and the first row shown. Data only: fsel_tree.zig lays the rows
// out (TOS 4's nine, a file as NAME____.EXT, an empty slot as the template) and
// fsel_draw.zig draws them. Split out of filesel.zig.
// --------------------------------------------------------------------------
pub const MAX_FILES: usize = 32;
pub const ROWS: usize = 9; // visible list rows

pub const List = struct {
    names: [MAX_FILES][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** MAX_FILES,
    nlen: [MAX_FILES]u8 = [_]u8{0} ** MAX_FILES,
    dir: [MAX_FILES]bool = [_]bool{false} ** MAX_FILES,
    n: usize = 0,
    sel: i16 = -1,
    top: usize = 0, // first visible row

    pub fn add(self: *List, name: []const u8) void {
        if (self.n >= MAX_FILES) return;
        const folder = name.len > 0 and name[name.len - 1] == '\\';
        self.dir[self.n] = folder;
        const k = @min(name.len - @intFromBool(folder), 16);
        @memcpy(self.names[self.n][0..k], name[0..k]);
        self.nlen[self.n] = @intCast(k);
        self.n += 1;
    }

    pub fn nameAt(self: *const List, i: usize) []const u8 {
        return self.names[i][0..self.nlen[i]];
    }

    pub fn isDir(self: *const List, i: usize) bool {
        return i < self.n and self.dir[i];
    }

    /// Scroll by `delta` rows (an arrow 1, the track a page), kept inside the list.
    pub fn step(self: *List, delta: i32) void {
        const max: i32 = if (self.n > ROWS) @intCast(self.n - ROWS) else 0;
        self.top = @intCast(@max(0, @min(max, @as(i32, @intCast(self.top)) + delta)));
    }
};
