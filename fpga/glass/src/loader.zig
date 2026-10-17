// Loading a cart: the .zmd's rv32 board image, depacked, placed in the cart
// CPU's DDR window, and the CPU let out of reset (docs/FPGA_GLASS.md, "Cart
// load"). Every step that can fail says which, and a failure leaves the cart
// CPU HELD IN RESET: never running a half-written image.
const std = @import("std");
const zx0 = @import("zx0");
const map = @import("map.zig");
const bus = @import("bus.zig");
const zmd = @import("zmd.zig");

pub const Error = zmd.Error || error{
    NoGlass, // the PL does not answer with ID_VALUE: wrong bitstream, or none
    OldGlass, // the PL predates 1.3.0: it ignores LOAD_BASE, the cart would run over the initramfs
    WontStop, // the cart CPU did not go into reset
    BadImage, // the board image is a ZX0 container that does not depack
    TooBig, // larger than the cart CPU's window
    DiskTooBig, // the shelf disk does not fit between the image and the pictures (map.DISK_END)
    DdrMismatch, // the window did not read back what was written
    CartTrapped, // the firmware reported a trap while booting
    CartSilent, // the firmware never reported RUNNING
    WarmLost, // a warm boot found no cart memory to keep (TRAP_WARM_LOST): reset cold
    OutOfMemory,
};

pub const Options = struct {
    /// Polls of CART_STATE before giving up on a boot. A cart sits in BOOTING ~2.5 s on the
    /// board (the wasm data image and both pictures written over HP0), so the old 2,000 (2 s)
    /// stopped every cart as CartSilent (2026-10-10); 10 s leaves 4x room.
    boot_polls: u32 = 10_000,
    /// Called between polls (the board sleeps a millisecond; tests do nothing).
    idle: *const fn () void = noIdle,
    /// Read the whole window back after writing it.
    verify: bool = true,
    /// Wait for the firmware to report RUNNING (false until board firmware exists).
    wait_boot: bool = true,
    /// The descriptor's magic: DISK_MAGIC, or map_cart.zig's DISK_MAGIC_PROGRAM for a
    /// program launched off the disk (app_request.zig).
    disk_magic: u32 = map.DISK_MAGIC,
};

fn noIdle() void {}

pub const Report = struct { image_bytes: u32, packed_bytes: u32, polls: u32, trap: u32 = 0, fw: u32 = 0, disk_at: u32 = 0, disk_bytes: u32 = 0 };

/// Both OSD bits, which a load or a reset leaves as they are: the window the user sees
/// is the app's (app_stats.place), and a program run off a disk (app_request.zig) loads
/// with nothing after it to put a dropped OSD_STATS back (an opaque box in the corner).
const OSD_BITS = map.CTRL_OSD | map.CTRL_OSD_STATS;

/// Stop the cart CPU, keeping the OSD bits as they are (and dropping WARM: the next
/// boot is cold unless warm() asks again).
pub fn hold(regs: bus.Regs) Error!void {
    regs.write(map.REG_CTRL, regs.read(map.REG_CTRL) & ~(map.CTRL_RUN | map.CTRL_WARM));
    if (regs.read(map.REG_STATUS) & map.ST_RUNNING != 0) return error.WontStop;
}

pub fn checkGlass(regs: bus.Regs) Error!void {
    if (regs.read(map.REG_ID) != map.ID_VALUE) return error.NoGlass;
    if (regs.read(map.REG_VERSION) < 0x0001_0300) return error.OldGlass;
}

/// Unpack the board image into a fresh buffer (a raw image is copied as is).
pub fn unpack(gpa: std.mem.Allocator, image: []const u8, window: usize) Error![]u8 {
    if (!zx0.isPacked(image)) {
        if (image.len > window) return error.TooBig;
        return gpa.dupe(u8, image);
    }
    const n = zx0.depackedLen(image) orelse return error.BadImage;
    if (n > window) return error.TooBig;
    const out = try gpa.alloc(u8, n);
    errdefer gpa.free(out);
    const got = zx0.depack(image, out) orelse return error.BadImage;
    if (got != n) return error.BadImage;
    return out;
}

/// What a load writes into the window, worked out before anything is touched:
/// the image at 0, the shelf disk after it, the disk's descriptor near the top
/// (map.zig, "the disk in the cart window"). Everything else is zero.
pub const Plan = struct {
    image: []u8,
    disk: []u8,
    disk_at: u32,
    desc: [map.DISK_DESC_WORDS * 4]u8,
    desc_at: u32,
    packed_bytes: u32,

    pub fn parts(self: *const Plan) [3]bus.Part {
        return .{
            .{ .at = 0, .bytes = self.image },
            .{ .at = self.disk_at, .bytes = self.disk },
            .{ .at = self.desc_at, .bytes = &self.desc },
        };
    }

    pub fn deinit(self: *Plan, gpa: std.mem.Allocator) void {
        gpa.free(self.image);
        gpa.free(self.disk);
    }
};

/// Steps 2 and 3 of the load (and the disk's place): parse, depack, fit. Touches nothing.
pub fn plan(gpa: std.mem.Allocator, disk: []const u8, window: usize) Error!Plan {
    return planAs(gpa, disk, window, map.DISK_MAGIC);
}

/// plan, the descriptor saying `magic` (Options.disk_magic).
pub fn planAs(gpa: std.mem.Allocator, disk: []const u8, window: usize, magic: u32) Error!Plan {
    const d = try zmd.parse(disk);
    const board = try d.boardImage();
    const image = try unpack(gpa, board, window);
    errdefer gpa.free(image);
    const shelf = try d.shelfDisk(gpa);
    errdefer gpa.free(shelf);
    const at = try diskAt(image.len, shelf.len, window);
    var p = Plan{ .image = image, .disk = shelf, .disk_at = at, .desc = undefined, .desc_at = @intCast(window - map.DISK_DESC_FROM_TOP), .packed_bytes = @intCast(board.len) };
    const size: u32 = @intCast(shelf.len);
    const words = [map.DISK_DESC_WORDS]u32{ magic, at, size, ~(magic ^ at ^ size) };
    for (words, 0..) |w, i| std.mem.writeInt(u32, p.desc[i * 4 ..][0..4], w, .little);
    return p;
}

/// Where the disk goes: the first DISK_ALIGN boundary after the image, ending
/// by the pictures (DISK_END) and below the descriptor.
pub fn diskAt(image_len: usize, disk_len: usize, window: usize) Error!u32 {
    const at = std.mem.alignForward(usize, image_len, map.DISK_ALIGN);
    const end = @min(map.DISK_END, window - map.DISK_DESC_FROM_TOP);
    if (at + disk_len > end) return error.DiskTooBig;
    return @intCast(at);
}

/// The whole sequence, from a disk image in memory to a running cart.
pub fn load(gpa: std.mem.Allocator, regs: bus.Regs, ddr: bus.Ddr, disk: []const u8, opt: Options) Error!Report {
    try checkGlass(regs);
    var p = try planAs(gpa, disk, ddr.bytes(), opt.disk_magic);
    defer p.deinit(gpa);
    const parts = p.parts();
    try hold(regs);
    ddr.placeParts(&parts);
    if (opt.verify and ddr.verifyParts(&parts) != null) return error.DdrMismatch;
    regs.write(map.REG_LOAD_BASE, map.DDR_CART_BASE);
    regs.write(map.REG_LOAD_SIZE, @intCast(p.image.len));
    // Keys typed for the previous cart (or the menu) must not reach this one.
    regs.write(map.REG_CTRL, (regs.read(map.REG_CTRL) & OSD_BITS) | map.CTRL_KEY_FLUSH);
    regs.write(map.REG_CTRL, regs.read(map.REG_CTRL) | map.CTRL_RUN);
    var report = Report{ .image_bytes = @intCast(p.image.len), .packed_bytes = p.packed_bytes, .polls = 0, .disk_at = p.disk_at, .disk_bytes = @intCast(p.disk.len) };
    if (opt.wait_boot) try waitBoot(regs, opt, &report);
    return report;
}

/// The ST's reset button: the cart CPU restarts over the memory it has, which
/// nothing here touches. The firmware sees CTRL_WARM at boot (glass_boot.h); a
/// cold load writes CTRL without it, and so does this once the cart is up.
pub fn warm(regs: bus.Regs, opt: Options) Error!Report {
    try checkGlass(regs);
    try hold(regs);
    const osd_bits = regs.read(map.REG_CTRL) & OSD_BITS;
    regs.write(map.REG_CTRL, osd_bits | map.CTRL_WARM | map.CTRL_KEY_FLUSH);
    regs.write(map.REG_CTRL, osd_bits | map.CTRL_WARM | map.CTRL_RUN);
    var report = Report{ .image_bytes = regs.read(map.REG_LOAD_SIZE), .packed_bytes = 0, .polls = 0 };
    if (opt.wait_boot) try waitBoot(regs, opt, &report);
    regs.write(map.REG_CTRL, regs.read(map.REG_CTRL) & ~map.CTRL_WARM);
    return report;
}

fn waitBoot(regs: bus.Regs, opt: Options, report: *Report) Error!void {
    while (report.polls < opt.boot_polls) : (report.polls += 1) {
        const state = regs.read(map.REG_CART_STATE);
        switch (state & map.CART_STATE_MASK) {
            map.CART_RUNNING => {
                report.fw = state >> map.CART_ARG_SHIFT;
                return;
            },
            map.CART_TRAPPED => {
                report.trap = state >> map.CART_ARG_SHIFT;
                try hold(regs);
                return if (report.trap == map.TRAP_WARM_LOST) error.WarmLost else error.CartTrapped;
            },
            else => opt.idle(),
        }
    }
    try hold(regs);
    return error.CartSilent;
}
