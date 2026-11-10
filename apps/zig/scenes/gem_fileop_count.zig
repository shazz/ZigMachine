// --------------------------------------------------------------------------
// TOS's first pass (gem_fileop.zig): the folders, files and bytes an operation will touch,
// counted on the disk itself through Fsfirst / Fsnext, never from the desktop's model (C:'s
// holds at most MAX_FILES files over the whole card). Reads only: on the board a few sector
// round trips (~0.5 ms each), so the whole count runs in the frame that asked for it.
// --------------------------------------------------------------------------
const gemdos = @import("kos_gemdos");
const fp = @import("gem_fileop_path.zig");

pub const Counts = struct {
    folders: u32 = 0,
    files: u32 = 0,
    bytes: u32 = 0,
    code: i32 = 0, // the first GEMDOS error met (an item gone, a drive that does not mount)

    pub fn add(c: *Counts, o: Counts) void {
        c.folders += o.folders;
        c.files += o.files;
        c.bytes +%= o.bytes;
        if (c.code == 0) c.code = o.code;
    }
};

const MAX_DEPTH = 10; // KOS: 8 folders deep at most, and a margin

/// What `path` holds: itself (a file, or a folder and everything in it).
pub fn item(path: []const u8) Counts {
    var c = Counts{};
    const e = fp.stat(path, &c.code) orelse return c;
    if (!e.dir) return .{ .files = 1, .bytes = e.size };
    var p = fp.Path{};
    p.set(path);
    c.folders = 1;
    if (p.push("", true)) folder(&p, &c, 0);
    return c;
}

// Everything inside the folder `p` ("C:\A\B\"), added to `c`.
fn folder(p: *fp.Path, c: *Counts, depth: usize) void {
    if (depth >= MAX_DEPTH) return;
    const dos = gemdos.dos();
    var t: gemdos.Dta = .{};
    const at = p.len;
    defer p.len = at;
    if (!p.push("*.*", false)) return;
    dos.Fsetdta(&t);
    var r = dos.Fsfirst(p.str(), fp.ANY);
    p.len = at;
    while (r == 0) : (r = next(&t)) {
        if (fp.skipped(&t)) continue;
        const e = fp.Entry.of(&t);
        if (!e.dir) {
            c.files += 1;
            c.bytes +%= e.size;
            continue;
        }
        c.folders += 1;
        if (p.push(e.slice(), true)) folder(p, c, depth + 1);
        p.len = at;
    }
}

// Fsnext on this folder's DTA (a sub-folder's walk moved the DTA pointer away).
fn next(t: *gemdos.Dta) i32 {
    const dos = gemdos.dos();
    dos.Fsetdta(t);
    return dos.Fsnext();
}
