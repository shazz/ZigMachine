// Where glass finds things on the SD card (docs/FPGA_GLASS.md "The SD card's layout";
// decisions.md 2026-11-06). Every SD path glass reads is under one of two directories:
//
//   sys    system.rv32, kos/desktop.rv32, glass.cfg, progs/ (by-hash and per-disk programs)
//   carts  the OSD's shelf: <category>/demo-<tag>.zmd and shelf.txt
//
// The card (FAT32, mounted read-only at ROOT) has two layouts, and glass runs on both:
//
//   KESTREL (6 Nov 2026)  ROOT/KESTREL = sys, ROOT/CARTS = carts, ROOT/HD = KOS's C: (the desktop
//                         shell reads it, glass never does), boot files alone at ROOT
//   old                   ROOT/zigmachine = sys = carts (a card not migrated yet, or migrated back)
//
// `glass run DIR` picks: DIR/KESTREL is a directory -> KESTREL; else DIR/zigmachine -> old; else DIR
// itself holds both (an explicit shelf directory: the old S99glass's `glass run /mnt/sd/zigmachine`,
// sim-menu, the tests).
const std = @import("std");

pub const ROOT = "/mnt/sd"; // where S99glass mounts the card
pub const SYSTEM = "KESTREL";
pub const CARTS = "CARTS";
pub const HD = "HD"; // KOS's C: (apps/zig/scenes/gem_fat.zig roots C: there)
pub const OLD = "zigmachine";

pub const Kind = enum { kestrel, old, flat };

pub const Dirs = struct {
    sys: []const u8,
    carts: []const u8,
    kind: Kind = .flat,

    /// One directory holding both (the old layout's zigmachine/, a test's shelf).
    pub fn flat(dir: []const u8) Dirs {
        return .{ .sys = dir, .carts = dir };
    }

    /// Free what detect() allocated (nothing for a flat one).
    pub fn deinit(d: Dirs, gpa: std.mem.Allocator) void {
        switch (d.kind) {
            .flat => {},
            .old => gpa.free(d.sys),
            .kestrel => {
                gpa.free(d.sys);
                gpa.free(d.carts);
            },
        }
    }
};

fn isDir(io: std.Io, path: []const u8) bool {
    var d = std.Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    d.close(io);
    return true;
}

/// The layout of the card mounted at `root` (see the top of this file).
pub fn detect(gpa: std.mem.Allocator, io: std.Io, root: []const u8) !Dirs {
    const sys = try std.fs.path.join(gpa, &.{ root, SYSTEM });
    if (isDir(io, sys)) {
        errdefer gpa.free(sys);
        const carts = try std.fs.path.join(gpa, &.{ root, CARTS });
        return .{ .sys = sys, .carts = carts, .kind = .kestrel };
    }
    gpa.free(sys);
    const old = try std.fs.path.join(gpa, &.{ root, OLD });
    if (isDir(io, old)) return .{ .sys = old, .carts = old, .kind = .old };
    gpa.free(old);
    return Dirs.flat(root);
}
