// Loading a cart: the .zmd's rv32 board image, depacked, placed in the cart
// CPU's DDR window, and the CPU let out of reset (docs/FPGA_GLASS.md, "Cart
// load"). Every step that can fail says which, and a failure leaves the cart
// CPU HELD IN RESET: never running a half-written image.
const std = @import("std");
const map = @import("map.zig");
const bus = @import("bus.zig");
const mc = @import("map_cart.zig");
const plan_mod = @import("plan.zig");
const system = @import("system.zig");

pub const Error = plan_mod.Error || error{
    NoGlass, // the PL does not answer with ID_VALUE: wrong bitstream, or none
    OldGlass, // the PL predates 1.3.0: it ignores LOAD_BASE, the cart would run over the initramfs
    WontStop, // the cart CPU did not go into reset
    DdrMismatch, // the window did not read back what was written
    CartTrapped, // the firmware reported a trap while booting
    CartSilent, // the firmware never reported RUNNING
    WarmLost, // a warm boot found no cart memory to keep (TRAP_WARM_LOST): reset cold
    NoCart, // the firmware found no lean cart at CART_IMG_AT (TRAP_NO_CART)
    SystemRefused, // the firmware refused the lean cart's table version (TRAP_CART_ABI)
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
    /// The card's system image (system.zig, read once at start-up): what a lean cart runs on.
    system: ?system.System = null,
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

pub const unpack = plan_mod.unpack;
pub const Plan = plan_mod.Plan;
pub const diskAt = plan_mod.diskAt;

/// Steps 2 and 3 of the load (and the disk's place): parse, depack, fit. Touches nothing.
pub fn plan(gpa: std.mem.Allocator, disk: []const u8, window: usize) Error!Plan {
    return plan_mod.planAs(gpa, disk, window, map.DISK_MAGIC, null);
}

/// plan, the descriptor saying `magic` (Options.disk_magic), no system image.
pub fn planAs(gpa: std.mem.Allocator, disk: []const u8, window: usize, magic: u32) Error!Plan {
    return plan_mod.planAs(gpa, disk, window, magic, null);
}

/// plan for a load with these options: their descriptor magic and system image.
pub fn planFor(gpa: std.mem.Allocator, disk: []const u8, window: usize, opt: Options) Error!Plan {
    return plan_mod.planAs(gpa, disk, window, opt.disk_magic, opt.system);
}

/// The whole sequence, from a disk image in memory to a running cart.
pub fn load(gpa: std.mem.Allocator, regs: bus.Regs, ddr: bus.Ddr, disk: []const u8, opt: Options) Error!Report {
    try checkGlass(regs);
    var p = try planFor(gpa, disk, ddr.bytes(), opt);
    defer p.deinit(gpa);
    const parts = p.parts();
    try hold(regs);
    ddr.placeParts(&parts);
    if (opt.verify and ddr.verifyParts(&parts) != null) return error.DdrMismatch;
    regs.write(map.REG_LOAD_BASE, map.DDR_CART_BASE);
    regs.write(map.REG_LOAD_SIZE, p.imageEnd());
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
                return switch (report.trap) {
                    map.TRAP_WARM_LOST => error.WarmLost,
                    mc.TRAP_CART_ABI => error.SystemRefused,
                    mc.TRAP_NO_CART => error.NoCart,
                    else => error.CartTrapped,
                };
            },
            else => opt.idle(),
        }
    }
    try hold(regs);
    return error.CartSilent;
}
