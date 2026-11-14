// --------------------------------------------------------------------------
// The shell's file operations (gem_fileop.zig), TOS's second pass: the items walked one entry
// a frame, depth first, a folder's contents before the folder is left. A copy (and a move to
// another drive) creates each folder where it goes, then copies its files (gem_fileop_copy.zig);
// a delete removes the files, then the emptied folder. The walk's place is kept here between
// frames: the top-level item reached, and per folder level its DTA (Fsnext resumes it) and how
// long the source and destination paths were before it went down.
// --------------------------------------------------------------------------
const gemdos = @import("kos_gemdos");
const op = @import("rom_sdk").deskop;
const fp = @import("gem_fileop_path.zig");

const MAX_DEPTH = 10; // KOS: 8 folders deep at most

const Level = struct { dta: gemdos.Dta = .{}, src_len: usize = 0, dst_len: usize = 0, started: bool = false };

pub var src: fp.Path = .{}; // the folder being walked, "C:\A\" (the items' own at the top)
pub var dst: fp.Path = .{}; // where its entries go
var levels: [MAX_DEPTH]Level = undefined;
var depth: usize = 0; // 0: the box's own items; n: inside n folders
var top: usize = 0; // the next top-level item

pub const Next = union(enum) { got: fp.Entry, wait, end, fail: i32 };

pub fn reset(b: *const op.Box) void {
    src.set(b.srcPath());
    dst.set(b.dstPath());
    depth = 0;
    top = 0;
}

/// The next entry to work on; a folder finished on the way up runs `left` (its Ddelete for a
/// delete or a move: a write, so the frame ends there: .wait).
pub fn next(b: *op.Box, left: *const fn (*op.Box, []const u8) i32) Next {
    while (true) {
        if (depth == 0) {
            if (top >= b.n_items) return .end;
            top += 1;
            const at = src.len;
            if (!src.push(b.item(top - 1), false)) return .{ .fail = gemdos.err.EPTHNF };
            defer src.len = at;
            var code: i32 = 0;
            const e = fp.stat(src.str(), &code) orelse return .{ .fail = code };
            return .{ .got = e };
        }
        const l = &levels[depth - 1];
        if (entryIn(l)) |e| return .{ .got = e };
        const code = up(b, left);
        if (code < 0) return .{ .fail = code };
        if (code > 0) return .wait;
    }
}

// The folder level's next entry, "." / ".." and temp files skipped.
fn entryIn(l: *Level) ?fp.Entry {
    const dos = gemdos.dos();
    dos.Fsetdta(&l.dta);
    var r: i32 = undefined;
    if (!l.started) {
        l.started = true;
        const at = src.len;
        if (!src.push("*.*", false)) return null;
        r = dos.Fsfirst(src.str(), fp.ANY);
        src.len = at;
    } else r = dos.Fsnext();
    while (r == 0) : (r = dos.Fsnext()) {
        if (!fp.skipped(&l.dta)) return fp.Entry.of(&l.dta);
    }
    return null;
}

// Out of a finished folder: `left(b, folder)` (0 nothing written, 1 a write made, < 0 an error).
fn up(b: *op.Box, left: *const fn (*op.Box, []const u8) i32) i32 {
    depth -= 1;
    const l = &levels[depth];
    const folder = src.str()[0 .. src.len - 1]; // "C:\A\B" without its last '\'
    const r = left(b, folder);
    src.len = l.src_len;
    dst.len = l.dst_len;
    return r;
}

/// Into folder `name` (its copy is `as` where it goes): its entries come next.
pub fn down(name: []const u8, as: []const u8) bool {
    if (depth >= MAX_DEPTH) return false;
    levels[depth] = .{ .src_len = src.len, .dst_len = dst.len };
    if (!src.push(name, true) or !dst.push(as, true)) {
        src.len = levels[depth].src_len;
        dst.len = levels[depth].dst_len;
        return false;
    }
    depth += 1;
    return true;
}

/// At the top level: the items are the box's own (a move on one drive renames them whole).
pub fn atTop() bool {
    return depth == 0;
}
