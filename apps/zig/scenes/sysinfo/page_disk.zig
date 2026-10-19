// --------------------------------------------------------------------------
// SysInfo page 4 — DRIVE A: and its FILES (HWAM's Keyboard & Disk / Drives).
// The mounted disk's descriptor and boot sector, read through the drive at
// start (probe.readDisk), and its FAT (zg.disk). The shelf the host picked the
// disk from is the host's: a cart cannot see it, so it reads n/a.
// --------------------------------------------------------------------------
const hw = @import("hardware");
const grid = @import("grid.zig");
const pages = @import("pages.zig");
const diskinfo = @import("diskinfo.zig");

const L: usize = 0;
const R: usize = grid.COL2;
const N_A = pages.N_A;

pub fn fill(g: *grid.Grid, c: *const pages.Ctx) void {
    pages.heading(g, 2, L, "DRIVE A:");
    if (c.disk) |d| drive(g, &d) else g.field(3, L, "DISK", "NONE");
    g.field(13, L, "SHELF", N_A);
    pages.heading(g, 15, L, "THIS CART:");
    pages.kbField(g, 16, L, "RAM USED", hw.hwRamUsed());
    files(g, c);
}

fn drive(g: *grid.Grid, d: *const diskinfo.Info) void {
    var b: [16]u8 = undefined;
    g.fieldf(3, L, "DISK", "ZMDISK V{d}", .{d.version});
    g.field(4, L, "BOOT SECTOR", if (d.bootable) "BOOTABLE ($1234)" else "DATA DISK");
    g.field(5, L, "TITLE", d.titleText());
    g.field(6, L, "AUTHOR", d.authorText());
    g.field(7, L, "DATE", pages.date(&b, d.date));
    g.fieldf(8, L, "BOOT CART", "BLOCK {d}", .{d.cart_block});
    g.fieldf(9, L, "CART SIZE", "{d} Bytes", .{d.cart_len});
    if (d.total_blocks == 0) g.field(10, L, "DISK SIZE", N_A) else g.fieldf(10, L, "DISK SIZE", "{d} Kbytes", .{d.total_blocks / 2});
    g.fieldf(11, L, "FILES", "{d}", .{d.files});
}

fn files(g: *grid.Grid, c: *const pages.Ctx) void {
    pages.heading(g, 2, R, "FILES:");
    if (c.files.len == 0) return g.put(3, R, "NO FILES IN THE FAT", .plain);
    for (c.files, 0..) |f, i| {
        if (i >= 20) break; // rows 3..22
        const name = diskinfo.trim(&f.name);
        g.print(3 + i, R, "{s:<16} {d:>8} {s}", .{ name, f.len, kind(f.kind) });
    }
}

/// The FAT's type byte (docs/FLOPPY_DISK.md).
fn kind(k: u8) []const u8 {
    return switch (k) {
        0 => "PROGRAM",
        1 => "DATA",
        2 => "TEXT",
        else => "?",
    };
}
