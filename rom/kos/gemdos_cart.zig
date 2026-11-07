// --------------------------------------------------------------------------
// KOS GEMDOS in a cart (docs/KOS_GEMDOS.md §4): the library bound to the sector imports every host
// serves. A: is the drive's disk through env.diskReadBlock (a FAT image: a real floppy, an .ST; a
// .zmd has no BPB, so A: does not mount over one); C: is the SD card's /HD through env.kosDriveRead
// (unit 2, up to 64 sectors a request: ~0.5 ms a round trip to glass on the board, a copy on the page
// and in the native host); C:'s writes through env.kosFileOp (system table 1.10), whole files the
// host writes: a cart using this library needs table 1.10. A Zig cart imports the module
// `kos_gemdos` and calls dos(); a C cart links gemdos_c.zig's object and calls Fopen & co.
// (apps/ports/kestrel_sdl2/include/kestrel_gemdos.h).
// --------------------------------------------------------------------------
const gemdos = @import("gemdos.zig");
const abi = @import("kfs_abi.zig");
pub const Dos = gemdos.Dos;
pub const Dta = gemdos.Dta;
pub const err = gemdos.err;
pub const search = gemdos.search;

extern "env" fn diskReadBlock(block: u32, dst_off: u32) i32;
extern "env" fn kosDriveRead(unit: u32, sector: u32, count: u32, dst: u32) u32;
// C:'s writes (docs/KOS_GEMDOS.md §7): the host owns them at the file level (glass on the board).
// System table 1.10: a cart that writes needs it; one that only reads still runs on 1.8.
extern "env" fn kosFileOp(req: u32) u32;

const UNIT_C = 2;
const BLOCK = 512;

fn runA(_: *anyopaque, sector: u32, count: u32, dst: [*]align(4) u8) u32 {
    for (0..count) |i| {
        const at: u32 = @intCast(@intFromPtr(dst) + i * BLOCK);
        if (diskReadBlock(sector + @as(u32, @intCast(i)), at) != BLOCK) return 0;
    }
    return count;
}

fn runC(_: *anyopaque, sector: u32, count: u32, dst: [*]align(4) u8) u32 {
    return kosDriveRead(UNIT_C, sector, count, @intCast(@intFromPtr(dst)));
}

fn addr(p: []const u8) u32 {
    return @intCast(@intFromPtr(p.ptr));
}

fn opC(_: *anyopaque, req: *abi.Req, path: []const u8, path2: []const u8, data: []const u8) i32 {
    req.path = addr(path);
    req.path_len = @intCast(path.len);
    req.path2 = addr(path2);
    req.path2_len = @intCast(path2.len);
    req.data = addr(data);
    req.len = @intCast(data.len);
    return @bitCast(kosFileOp(@intCast(@intFromPtr(req))));
}

var ctx: u8 = 0;
var drive_a: gemdos.Drive = .{ .run_fn = runA, .ctx = &ctx, .max_run = gemdos.MAX_RUN, .root_name = null };
var drive_c: gemdos.Drive = .{ .run_fn = runC, .ctx = &ctx, .max_run = gemdos.MAX_RUN, .root_name = "HD", .op_fn = opC };
var the_dos: Dos = .{};
var attached = false;

/// The cart's GEMDOS: A: and C: attached at the first call, each mounted at its first use.
pub fn dos() *Dos {
    if (!attached) {
        the_dos.attach(gemdos.DRIVE_A, &drive_a);
        the_dos.attach(gemdos.DRIVE_C, &drive_c);
        attached = true;
    }
    return &the_dos;
}

/// A new disk in drive A (the program saw KOS's media count move): A: mounts afresh at its next use.
pub fn mediaChangeA() void {
    drive_a.reset();
}

/// Round trips to each drive since start (the cost proofs: frame_cost, the board's OSD).
pub fn trips(letter: u8) u32 {
    return switch (letter) {
        gemdos.DRIVE_A => drive_a.trips,
        gemdos.DRIVE_C => drive_c.trips,
        else => 0,
    };
}
