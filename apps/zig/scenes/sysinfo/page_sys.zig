// --------------------------------------------------------------------------
// SysInfo page 1 — SYSTEM INFO and MEMORY, HWAM's first page.
//
// The left column is the machine. A cart cannot tell the browser from the
// KESTREL board, nor read the CPU, its clock, its FPU, the machine's
// hwVersion(), the ROM's version or the system table's: none of those is in
// the system table a lean cart links against (fpga/cycles/sys_abi.txt), so
// they read n/a. The speed tests (page 5) are what tells the hosts apart.
//
// The right column is the cart's RAM window, the arena, the ROM chip's window
// and the VRAM pool, all from the hw* calls and the video registers.
// --------------------------------------------------------------------------
const hw = @import("hardware");
const grid = @import("grid.zig");
const pages = @import("pages.zig");
const probe = @import("probe.zig");

const L: usize = 0;
const R: usize = grid.COL2;
const N_A = pages.N_A;

pub fn fill(g: *grid.Grid, c: *const pages.Ctx) void {
    system(g, c);
    memory(g);
    pointers(g);
    g.put(22, L, "n/a: NOT EXPOSED TO A CART BY THE MACHINE'S ABI", .plain);
}

fn system(g: *grid.Grid, c: *const pages.Ctx) void {
    pages.heading(g, 2, L, "SYSTEM INFO:");
    g.field(3, L, "TYPE", "ZIGMACHINE");
    g.field(4, L, "HOST", N_A);
    g.field(5, L, "PROCESSOR", N_A);
    g.field(6, L, "FREQUENCY", N_A);
    g.field(7, L, "CO-PROCESSOR", N_A);
    g.field(8, L, "HW VERSION", N_A);
    g.field(9, L, "ROM CHIP", if (hw.hwRomRamSize() != 0) "FITTED" else "NOT FITTED");
    g.field(10, L, "ROM/GEM VERSION", N_A);
    g.field(11, L, "SYSTEM TABLE", N_A);
    g.field(12, L, "GEM CONTEXT", if (c.gem_ok) "AVAILABLE" else "NOT AVAILABLE");
    g.field(13, L, "GEM DIALOGS", if (c.dialog_ok) "AVAILABLE" else "NOT AVAILABLE");
    g.field(14, L, "RESOLUTION", probe.modeName(probe.plane(c.os, 0).mode));
    g.fieldf(15, L, "PLANES", "{d}", .{probe.planesReg()});
    g.fieldf(16, L, "FRAMES SHOWN", "{d}", .{probe.frameCounter()});
    frameTime(g, 17, c.frame_us);
}

/// The measured frame period and rate: the host's real pace, not the dt it passes.
fn frameTime(g: *grid.Grid, row: usize, us: u32) void {
    if (us == 0) return g.field(row, L, "FRAME TIME", N_A);
    var a: [16]u8 = undefined;
    var b: [16]u8 = undefined;
    const ms = pages.tenths(&a, us / 100);
    const fps = pages.tenths(&b, @as(u64, 10_000_000) / us);
    g.fieldf(row, L, "FRAME TIME", "{s} MS ({s} FPS)", .{ ms, fps });
}

fn memory(g: *grid.Grid) void {
    pages.heading(g, 2, R, "MEMORY:");
    g.fieldf(3, R, "CART WINDOW", "${X:0>6}-${X:0>6}", .{ hw.hwRamBase(), hw.hwRamTop() });
    pages.kbField(g, 4, R, "WINDOW SIZE", hw.hwRamSize());
    pages.kbField(g, 5, R, "USED", hw.hwRamUsed());
    pages.bytesField(g, 6, R, "FREE", hw.hwRamFree());
    arenaTop(g, 7);
    g.fieldf(8, R, "ALLOC REFUSED", "{d:>9}", .{hw.hwRamAllocFailures()});
    g.fieldf(9, R, "ROM WINDOW", "${X:0>6}-${X:0>6}", .{ hw.hwRomRamBase(), hw.hwRomRamTop() });
    pages.kbField(g, 10, R, "ROM USED", hw.hwRomRamUsed());
    pages.kbField(g, 11, R, "ROM FREE", hw.hwRomRamFree());
    pages.kbField(g, 12, R, "VRAM POOL", hw.VRAM_BYTES);
}

fn arenaTop(g: *grid.Grid, row: usize) void {
    const top = hw.hwRamMark();
    if (top == 0) return g.field(row, R, "ARENA TOP", "NO ARENA");
    pages.hexField(g, row, R, "ARENA TOP", top);
}

fn pointers(g: *grid.Grid) void {
    const base: u32 = @intCast(probe.base());
    pages.heading(g, 15, R, "MEMORY POINTERS:");
    pages.hexField(g, 16, R, "VIDEO REGISTERS", base);
    pages.hexField(g, 17, R, "PALETTES", base + hw.OFF_PAL);
    pages.hexField(g, 18, R, "VRAM POOL", base + hw.OFF_VRAM);
    pages.hexField(g, 19, R, "PHYSICAL SCREEN", base + hw.OFF_PFB);
    const s = probe.romScratch();
    if (s.len == 0) return g.field(20, R, "ROM SCRATCH", "NONE");
    g.fieldf(20, R, "ROM SCRATCH", "${X:0>6} {d} B", .{ s.ptr, s.len });
}
