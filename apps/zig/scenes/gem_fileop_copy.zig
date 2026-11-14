// --------------------------------------------------------------------------
// One file copied by the shell's file operations (gem_fileop.zig), a chunk a frame: Fread then
// Fwrite of CHUNK bytes, which is exactly KOS GEMDOS's write buffer (kfs_abi DATA_MAX), so each
// frame sends at most one env.kosFileOp request (on the board: a remount and a sync on the card,
// seconds) and the desktop's count-down repaints between them. The data goes to a temporary
// name and is renamed over the file at Fclose (KOS_GEMDOS_WRITES §2): a copy that fails half
// way (a full card) is dropped there whole, never left as a partial file.
// --------------------------------------------------------------------------
const gemdos = @import("kos_gemdos");
const fp = @import("gem_fileop_path.zig");
const zmd = @import("gem_fileop_zmd.zig");

pub const CHUNK: i32 = 32 * 1024;
// The source "handle" of a file read off a .zmd in drive A (gem_fileop_zmd.zig): never a GEMDOS
// one (those are 6 .. 6 + MAX_FILES), so it is never Fclosed.
const ZMD_H: i32 = 0x7FFF;

fn zmdOpen(from: []const u8) i32 {
    const r = zmd.open(from);
    return if (r < 0) r else ZMD_H;
}
pub const MORE: i32 = 1; // chunk(): more to come; 0 the file is whole; < 0 GEMDOS's error

var buf: [CHUNK]u8 align(4) = undefined;
var in_h: i32 = -1;
var out_h: i32 = -1;
pub var src: fp.Path = .{}; // the file being copied, and where it goes (a move deletes `src` after)
pub var dst: fp.Path = .{};
pub var size: u32 = 0;

pub fn active() bool {
    return out_h >= 0;
}

/// Open `from`, create `to`: 0, or GEMDOS's error (nothing left open).
pub fn start(from: []const u8, to: []const u8, bytes: u32) i32 {
    const dos = gemdos.dos();
    in_h = if (zmd.owns(from)) zmdOpen(from) else dos.Fopen(from, 0);
    if (in_h < 0) return drop(in_h);
    out_h = dos.Fcreate(to, 0);
    if (out_h < 0) return drop(out_h);
    src.set(from);
    dst.set(to);
    size = bytes;
    return 0;
}

/// The next chunk: MORE, 0 (the file is whole: committed at Fclose), or the error that dropped it.
pub fn chunk() i32 {
    const dos = gemdos.dos();
    const n = if (in_h == ZMD_H) zmd.read(&buf) else dos.Fread(in_h, CHUNK, &buf);
    if (n < 0) return drop(n);
    if (n > 0) {
        const w = dos.Fwrite(out_h, n, &buf);
        if (w != n) return drop(if (w < 0) w else gemdos.err.EWRITF);
    }
    if (n == CHUNK) return MORE;
    const c = dos.Fclose(out_h); // the save: the last bytes and the commit
    out_h = -1;
    if (in_h != ZMD_H) _ = dos.Fclose(in_h);
    in_h = -1;
    return c;
}

/// Close both (a file being written that failed is dropped at its Fclose): `code` back.
pub fn drop(code: i32) i32 {
    const dos = gemdos.dos();
    if (out_h >= 0) _ = dos.Fclose(out_h);
    if (in_h >= 0 and in_h != ZMD_H) _ = dos.Fclose(in_h);
    out_h = -1;
    in_h = -1;
    return code;
}

/// A move's check before it deletes the source: the copy is there, as long as the original.
pub fn verified() bool {
    var code: i32 = 0;
    const e = fp.stat(dst.str(), &code) orelse return false;
    return !e.dir and e.size == size;
}
