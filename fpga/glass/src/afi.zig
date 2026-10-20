// HP1's AFI write width: the board half of the W64 switch (glass run --fw-opt, map_cart.zig
// FW_OPT_W64). The video DMA writes 4-byte beats into a 32-bit write channel (WRCHAN_CTRL 0xF01)
// unless the firmware sets hp_cfg W64, whose 8-byte beats need the channel 64-bit (0xF00). The two
// change together or every other word is lost: 8-byte beats into a 32-bit channel keep their low
// half (UG585 5.3.6), 4-byte beats into a 64-bit one land in the low lane only (HP3, 2026-10-10).
// The width may only change while nothing runs on HP1: CTRL.RUN low (the video DMA finishes the
// burst it has, then grants nothing, the scanout included: soc/zm_video_axi.py `enable`) and a
// pause for that burst (fpga/boards/microphase_z7_7010/README.md "Lessons").
//
// Only 64 -> 32 may happen at run time. A channel that has carried 32-bit writes and is then set
// 64-bit reads back 0xF00 but writes each 8-byte beat's low lane on even beats and its high lane on
// odd ones (words 0 and 3 of every 16 bytes; 1 and 2 never written): the board, 2026-10-19,
// prototypes/w64_re/. Set 64-bit from boot (boot.cmd, before any HP1 traffic) it writes every word,
// and a 64 -> 32 switch at run time writes correctly too. So W64 needs a channel still 64-bit since
// boot, and a W64 run on a 32-bit channel is refused (reboot) rather than switched.
//
// W64 is the default since boot.cmd sets HP1 0xF00 (2026-10-19): a run without --fw-opt on a channel
// that reads 0xF00 runs W64 (every load writes the W64 word); on 0xF01 (an older boot.scr) it writes
// no word and leaves the width. --fw-opt=N (N & FW_OPT_MASK): 2 W64, 0x10 plane-major (no line-major
// groups), 0x20 the top layer keeps its PFB store; every cart the run loads gets the word. An
// explicit N without W64 on 0xF00 is the A/B's W32 arm: 64 -> 32 at run time is correct, but it is
// one way, so every later run of this boot (the S99glass loop's too) is W32 until a reboot.
const std = @import("std");
const bus = @import("bus.zig");
const loader = @import("loader.zig");
const mc = @import("map_cart.zig");

pub const HP1_PAGE: u32 = 0xF800_9000; // AFI_HP1: answers only while the PL is loaded
pub const PAGE_BYTES: u32 = 0x1000;
pub const WRCHAN_CTRL: u32 = 0x14;
pub const WR32: u32 = 0xF01;
pub const WR64: u32 = 0xF00;

pub const Error = loader.Error || error{ AfiReadback, W64NeedsBoot };

/// What a run does: the width to set (null: leave it) and the word every load writes (null: none).
pub const Plan = struct { width: ?u32, opt: ?u32 };

/// --fw-opt decides; without it the channel does (0xF00 from boot: W64). W64 on a channel that is
/// not 0xF00 is an error: a run-time 32 -> 64 switch drops half the words (header).
pub fn resolve(fw_opt: ?u32, now: u32) error{W64NeedsBoot}!Plan {
    const opt = fw_opt orelse if (now == WR64) mc.FW_OPT_W64 else null;
    const w64 = if (opt) |o| o & mc.FW_OPT_W64 != 0 else false;
    if (w64 and now != WR64) return error.W64NeedsBoot;
    const v: u32 = if (w64) WR64 else WR32;
    return .{ .width = if (v == now) null else v, .opt = opt };
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

/// At glass run's start: our PL answers (checkGlass), then HP1's width as the run asks. Returns the
/// word every load of this run writes (App.opt.fw_opt).
pub fn forRun(regs: bus.Regs, afi: bus.Regs, fw_opt: ?u32, pause: *const fn () void) Error!?u32 {
    try loader.checkGlass(regs); // the AFI registers hang the ARM unless the PL is loaded
    const now = afi.read(WRCHAN_CTRL);
    const p = try resolve(fw_opt, now);
    if (p.width) |width| {
        try setHp1(regs, afi, width, pause);
        if (now == WR64) std.log.warn("HP1 set 64 -> 32-bit: W64 is off until the next reboot", .{});
    }
    std.log.info("HP1 write channel 0x{X}, fw-opt {s}0x{X}", .{ p.width orelse now, if (p.opt == null) "none " else "", p.opt orelse 0 });
    return p.opt;
}
