// --------------------------------------------------------------------------
// RACER: a file in C:\RACER\ (the SD card's /HD/RACER/, through KOS GEMDOS read-only: the existing ABI,
// system table 1.8). The track library (library.zig) and the car files (cars.zig) read through it.
// --------------------------------------------------------------------------
const std = @import("std");
const gemdos = @import("kos_gemdos");

pub const HD_DIR = "C:\\RACER\\";

pub fn hdPath(buf: *[32]u8, name: []const u8) []const u8 {
    return std.fmt.bufPrint(buf, HD_DIR ++ "{s}", .{name}) catch buf[0..0];
}

/// Up to dst.len bytes of a C: file: the count read (GEMDOS's negative code is an error).
pub fn hdRead(path: []const u8, dst: []u8) error{ReadFailed}!usize {
    const dos = gemdos.dos();
    const h = dos.Fopen(path, 0);
    if (h < 0) return error.ReadFailed;
    defer _ = dos.Fclose(h);
    var got: usize = 0;
    while (got < dst.len) {
        const r = dos.Fread(h, @intCast(@min(dst.len - got, 64 * 1024)), dst.ptr + got);
        if (r < 0) return error.ReadFailed;
        if (r == 0) break;
        got += @intCast(r);
    }
    return got;
}
