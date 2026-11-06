// --------------------------------------------------------------------------
// KOS GEMDOS in a cart (docs/KOS_GEMDOS.md §4): the library bound to the sector imports every host
// serves. A: is the drive's disk through env.diskReadBlock (a FAT image: a real floppy, an .ST; a
// .zmd has no BPB, so A: does not mount over one); C: is the SD card's /HD through env.kosDriveRead
// (unit 2, up to 64 sectors a request: ~0.5 ms a round trip to glass on the board, a copy on the page
// and in the native host). Both imports are in the system table since 1.8: a cart that uses this
// needs no new system. A Zig cart imports the module `kos_gemdos` and calls dos(); a C cart links
// gemdos_c.zig's object and calls Fopen & co. (apps/ports/kestrel_sdl2/include/kestrel_gemdos.h).
// --------------------------------------------------------------------------
const gemdos = @import("gemdos.zig");
pub const Dos = gemdos.Dos;
pub const Dta = gemdos.Dta;
pub const err = gemdos.err;
pub const search = gemdos.search;

extern "env" fn diskReadBlock(block: u32, dst_off: u32) i32;
extern "env" fn kosDriveRead(unit: u32, sector: u32, count: u32, dst: u32) u32;

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

var ctx: u8 = 0;
var drive_a: gemdos.Drive = .{ .run_fn = runA, .ctx = &ctx, .max_run = gemdos.MAX_RUN, .root_name = null };
var drive_c: gemdos.Drive = .{ .run_fn = runC, .ctx = &ctx, .max_run = gemdos.MAX_RUN, .root_name = "HD" };
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
