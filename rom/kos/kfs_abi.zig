// --------------------------------------------------------------------------
// KOS GEMDOS's writes to C: (docs/KOS_GEMDOS.md §7): the request a cart hands env.kosFileOp. A cart
// never writes sectors: the host owns every write at the FILE level (glass on the board, over Linux's
// own FAT driver; kfs.zig over the C: image on the page and in the native host), so two writers never
// share one FAT. The cart fills a Req in its own memory and passes its address; the host answers a
// TOS code (>= 0 done, < 0 a GEMDOS error) and the C: generation after the op in `gen`.
//
// Paths are C:'s, canonical: relative to C:\ (the card's /HD), names 8.3 upper case joined by `\`,
// no drive, no `.` or `..` (the library resolves them first). The host checks them again
// (kfs_path.zig): a cart is not trusted.
//
// A file is written to a temporary name in its folder (`~KOS<slot>.TMP`, slot = the cart's handle
// index) and renamed over its own name at the last write, so a crash mid-save leaves the old file.
// --------------------------------------------------------------------------
pub const Op = enum(u32) {
    gen = 0, // the C: generation (answered by the host itself, no write)
    write = 1, // `len` bytes of `data` at `offset` of slot's temp file; flags FIRST / LAST
    delete = 2, // the file `path`
    rename = 3, // `path` -> `path2` (a file or a folder, same drive)
    mkdir = 4, // the folder `path`
    rmdir = 5, // the empty folder `path`
    setattr = 6, // `path`'s attributes := `attr` (read-only, hidden, system, archive)
    abort = 7, // drop slot's temp file in `path`'s folder (a save that failed half way)
    _,
};

pub const FIRST: u32 = 1; // write: create (or truncate) the temp file first
pub const LAST: u32 = 2; // write: then rename it over `path`, its attributes `attr`

pub const PATH_MAX: u32 = 127; // 8 folders and a name of 12, `\` between: 116
pub const DATA_MAX: u32 = 32 * 1024; // the library's write buffer: a picture is one request
pub const SLOTS: u32 = 8; // the library's handles (gemdos.MAX_FILES)

/// What the cart writes at the address it passes (every field a little-endian u32: wasm32).
pub const Req = extern struct {
    op: u32 = 0,
    flags: u32 = 0,
    slot: u32 = 0,
    attr: u32 = 0,
    offset: u32 = 0,
    len: u32 = 0,
    data: u32 = 0, // the cart's address of the bytes
    path: u32 = 0, // the cart's address of `path`, path_len bytes (no NUL needed)
    path_len: u32 = 0,
    path2: u32 = 0,
    path2_len: u32 = 0,
    gen: u32 = 0, // the answer: the C: generation after the op
};

pub const REQ_BYTES = @sizeOf(Req);

comptime {
    if (REQ_BYTES != 48) @compileError("kfs Req is 12 words: docs/sealed-loader.js and the firmware read it so");
}

/// The temp file's name for `slot` (0..SLOTS-1).
pub fn tempName(slot: u32, out: *[9]u8) []const u8 {
    out.* = "~KOS0.TMP".*;
    out[4] = '0' + @as(u8, @intCast(slot % 10));
    return out;
}
