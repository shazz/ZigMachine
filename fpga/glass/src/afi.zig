// HP1's AFI write width: the board half of the W64 switch (glass run --fw-opt, map_cart.zig
// FW_OPT_W64). The video DMA writes 4-byte beats into a 32-bit write channel (WRCHAN_CTRL 0xF01,
// boot/boot.cmd) unless the firmware sets hp_cfg W64, whose 8-byte beats need the channel 64-bit
// (0xF00). The two change together or every other word is lost: 8-byte beats into a 32-bit channel
// keep their low half (UG585 5.3.6), 4-byte beats into a 64-bit one land in the low lane only
// (HP3, 2026-10-10). The width may only change while nothing runs on HP1: CTRL.RUN low (the video
// DMA finishes the burst it has, then grants nothing, the scanout included: soc/zm_video_axi.py
// `enable`) and a pause for that burst (fpga/boards/microphase_z7_7010/README.md "Lessons").
//
// --fw-opt=N (N & FW_OPT_MASK): 2 W64, 0x10 plane-major (no line-major groups), 0x20 the top layer
// keeps its PFB store. Every cart the run loads gets the word; a run without --fw-opt writes none.
const std = @import("std");
const bus = @import("bus.zig");
const loader = @import("loader.zig");
const mc = @import("map_cart.zig");

pub const HP1_PAGE: u32 = 0xF800_9000; // AFI_HP1: answers only while the PL is loaded
pub const PAGE_BYTES: u32 = 0x1000;
pub const WRCHAN_CTRL: u32 = 0x14;
pub const WR32: u32 = 0xF01;
pub const WR64: u32 = 0xF00;

pub const Error = loader.Error || error{AfiReadback};

/// The width to set, or null to leave it: --fw-opt decides; without it, a channel a W64 run
/// left 64-bit goes back to boot.cmd's 32-bit, since no firmware will write 8-byte beats now.
pub fn want(fw_opt: ?u32, now: u32) ?u32 {
    const v: u32 = if (fw_opt) |o| (if (o & mc.FW_OPT_W64 != 0) WR64 else WR32) else WR32;
    return if (v == now) null else v;
}

/// Hold the cart CPU, let HP1 drain, set the width and read it back.
pub fn setHp1(regs: bus.Regs, afi: bus.Regs, value: u32, pause: *const fn () void) Error!void {
    try loader.hold(regs);
    pause();
    afi.write(WRCHAN_CTRL, value);
    if (afi.read(WRCHAN_CTRL) != value) return error.AfiReadback;
}

/// --fw-opt's value: a number (0x.. allowed) with no bit outside FW_OPT_MASK, or null.
pub fn parseOpt(text: []const u8) ?u32 {
    const v = std.fmt.parseInt(u32, text, 0) catch return null;
    return if (v & ~mc.FW_OPT_MASK != 0) null else v;
}

/// At glass run's start: our PL answers (checkGlass), then HP1's width as the run asks.
pub fn forRun(regs: bus.Regs, afi: bus.Regs, fw_opt: ?u32, pause: *const fn () void) Error!void {
    try loader.checkGlass(regs); // the AFI registers hang the ARM unless the PL is loaded
    const width = want(fw_opt, afi.read(WRCHAN_CTRL)) orelse return;
    try setHp1(regs, afi, width, pause);
    std.log.info("HP1 write channel set to 0x{X}", .{width});
}
