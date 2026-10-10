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
};

fn noIdle() void {}

pub const Report = struct { image_bytes: u32, packed_bytes: u32, polls: u32, trap: u32 = 0, fw: u32 = 0 };

/// Stop the cart CPU, keeping the OSD bit as it is (and dropping WARM: the next
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

/// The whole sequence, from a disk image in memory to a running cart.
pub fn load(gpa: std.mem.Allocator, regs: bus.Regs, ddr: bus.Ddr, disk: []const u8, opt: Options) Error!Report {
    try checkGlass(regs);
    const board = try (try zmd.parse(disk)).boardImage();
    const image = try unpack(gpa, board, ddr.bytes());
    defer gpa.free(image);
    try hold(regs);
    ddr.place(image);
    if (opt.verify and ddr.verify(image) != null) return error.DdrMismatch;
    regs.write(map.REG_LOAD_BASE, map.DDR_CART_BASE);
    regs.write(map.REG_LOAD_SIZE, @intCast(image.len));
    // Keys typed for the previous cart (or the menu) must not reach this one.
    regs.write(map.REG_CTRL, (regs.read(map.REG_CTRL) & map.CTRL_OSD) | map.CTRL_KEY_FLUSH);
    regs.write(map.REG_CTRL, regs.read(map.REG_CTRL) | map.CTRL_RUN);
    var report = Report{ .image_bytes = @intCast(image.len), .packed_bytes = @intCast(board.len), .polls = 0 };
    if (opt.wait_boot) try waitBoot(regs, opt, &report);
    return report;
}

/// The ST's reset button: the cart CPU restarts over the memory it has, which
/// nothing here touches. The firmware sees CTRL_WARM at boot (glass_boot.h); a
/// cold load writes CTRL without it, and so does this once the cart is up.
pub fn warm(regs: bus.Regs, opt: Options) Error!Report {
    try checkGlass(regs);
    try hold(regs);
    const osd_bit = regs.read(map.REG_CTRL) & map.CTRL_OSD;
    regs.write(map.REG_CTRL, osd_bit | map.CTRL_WARM | map.CTRL_KEY_FLUSH);
    regs.write(map.REG_CTRL, osd_bit | map.CTRL_WARM | map.CTRL_RUN);
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
