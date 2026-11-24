// --------------------------------------------------------------------------
// SID-WIZARD Z's files, as the host of the library's pure file dialog (filer.zig):
//   the floppy   read-only, off the cart's own disk (zg.disk: the .zmd FAT): the example song
//   C:\          read and write, KOS GEMDOS (docs/os/KOS_GEMDOS.md): Fsfirst/Fsnext, Fopen/Fread,
//                Fcreate/Fwrite/Fclose (the host writes the whole file at Fclose, through a temporary
//                name: a failed save leaves the old file whole)
// A listing is C:'s files of the dialog's extension, then the floppy's; a load tries C: first.
// A save always goes to C:. GEMDOS names are 8.3, so a longer name is refused, not truncated.
// Every failure is a value (Fail), never a silent default.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const gemdos = @import("kos_gemdos");
const filer = @import("filer.zig");
const names = @import("names.zig");

pub const Fail = error{ NoFile, TooBig, BadName, Dos };

const FA_DIR: u8 = 0x10;

/// The entries `ext` (".SWM") has on C: and the floppy, names without extension, in `out`.
pub fn listing(ext: []const u8, out: *[filer.max_files]filer.Entry) usize {
    return listFloppy(ext, out, listCDrive(ext, out));
}

fn listCDrive(ext: []const u8, out: *[filer.max_files]filer.Entry) usize {
    const dos = gemdos.dos();
    var dta: gemdos.Dta = .{};
    dos.Fsetdta(&dta);
    var n: usize = 0;
    var r = dos.Fsfirst("C:\\*.*", 0);
    while (r == 0 and n < out.len) : (r = dos.Fsnext()) {
        if (dta.attrib & FA_DIR != 0) continue;
        const len = std.mem.indexOfScalar(u8, &dta.name, 0) orelse dta.name.len;
        n = names.addEntry(out, n, dta.name[0..len], ext);
    }
    return n;
}

fn listFloppy(ext: []const u8, out: *[filer.max_files]filer.Entry, start: usize) usize {
    const lay = zg.disk.mount() orelse return start;
    var n = start;
    var i: u16 = 0;
    while (i < lay.count) : (i += 1) {
        const ent = zg.disk.entryAt(lay, i) orelse continue;
        const len = std.mem.indexOfScalar(u8, &ent.name, 0) orelse ent.name.len;
        n = names.addEntry(out, n, ent.name[0..len], ext);
    }
    return n;
}

/// `name` into `buf`: C:\NAME first, then the floppy's. The slice is the file's bytes.
pub fn read(name: []const u8, buf: []u8) Fail![]u8 {
    if (!names.valid(name)) return Fail.BadName;
    var path: [16]u8 = undefined;
    const p = std.fmt.bufPrint(&path, "C:\\{s}", .{name}) catch return Fail.BadName;
    if (readC(p, buf)) |got| {
        return buf[0..got];
    } else |e| if (e != Fail.NoFile) return e;
    return readFloppy(name, buf);
}

fn readC(path: []const u8, buf: []u8) Fail!usize {
    const dos = gemdos.dos();
    const h = dos.Fopen(path, 0);
    if (h < 0) return Fail.NoFile;
    defer _ = dos.Fclose(h);
    var got: usize = 0;
    while (got < buf.len) {
        const r = dos.Fread(h, @intCast(buf.len - got), buf.ptr + got);
        if (r < 0) return Fail.Dos;
        if (r == 0) return got;
        got += @intCast(r);
    }
    return Fail.TooBig; // the buffer filled: the file may be longer
}

fn readFloppy(name: []const u8, buf: []u8) Fail![]u8 {
    const lay = zg.disk.mount() orelse return Fail.NoFile;
    const e = zg.disk.find(lay, name) orelse return Fail.NoFile;
    if (e.len > buf.len) return Fail.TooBig;
    const got = zg.disk.read(e, buf);
    if (got != e.len) return Fail.Dos; // the drive ran out before the file did
    return buf[0..got];
}

/// `data` as C:\NAME. The host writes it at Fclose; a refusal is Fail.Dos.
pub fn write(name: []const u8, data: []const u8) Fail!void {
    if (!names.valid(name)) return Fail.BadName;
    var path: [16]u8 = undefined;
    const p = std.fmt.bufPrint(&path, "C:\\{s}", .{name}) catch return Fail.BadName;
    const dos = gemdos.dos();
    const h = dos.Fcreate(p, 0);
    if (h < 0) return Fail.Dos;
    const w = dos.Fwrite(h, @intCast(data.len), data.ptr);
    const c = dos.Fclose(h); // the save itself
    if (w != data.len or c < 0) return Fail.Dos;
}
