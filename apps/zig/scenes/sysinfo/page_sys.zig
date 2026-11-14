// --------------------------------------------------------------------------
// SysInfo page 1 — SYSTEM INFO and MEMORY, HWAM's first page.
//
// The left column is the machine, as ident.zig found it at start: the host
// (the board, by ASTROLABE's cycle count; the browser, by its clock), the cart
// CPU and its measured clock (board), the coprocessors, KOS's system variables.
// HW VERSION is the SDK this cart was built against (memmap.ZM_HW_VERSION):
// the running machine's hwVersion() is not in the system table, so a cart
// cannot ask it. SYSTEM TABLE: the board refuses a cart built for a newer
// table than its own, so a running cart proves the system has at least the
// table of its imports (pages.TABLE_MIN); the browser binds imports by name.
//
// The right column is the cart's RAM window, the arena, the ROM chip's window
// and the VRAM pool, all from the hw* calls and the video registers.
// --------------------------------------------------------------------------
const hw = @import("hardware");
const grid = @import("grid.zig");
const pages = @import("pages.zig");
const probe = @import("probe.zig");
const ident = @import("ident.zig");

const L: usize = 0;
const R: usize = grid.COL2;
const N_A = pages.N_A;

pub fn fill(g: *grid.Grid, c: *const pages.Ctx) void {
    system(g, c);
    memory(g);
    pointers(g);
    g.put(22, L, "n/a: THIS HOST DOES NOT TELL A CART", .plain);
}

fn system(g: *grid.Grid, c: *const pages.Ctx) void {
    const id = c.id;
    pages.heading(g, 2, L, "SYSTEM INFO:");
    g.field(3, L, "TYPE", "ZIGMACHINE");
    g.field(4, L, "HOST", hostName(id.host));
    g.field(5, L, "PROCESSOR", processor(id.host));
    frequency(g, 6, id.mhz10);
    g.field(7, L, "CO-PROCESSOR", if (!id.astro_ok) N_A else if (id.astro_arm) "ASTROLABE (ARM F64)" else "ASTROLABE (MACHINE)");
    g.field(8, L, "BARD JOBS", jobsName(id.jobs));
    g.fieldf(9, L, "HW VERSION", "{d}.{d}.{d} (SDK)", .{ hw.ZM_HW_VERSION >> 16, hw.ZM_HW_VERSION >> 8 & 0xFF, hw.ZM_HW_VERSION & 0xFF });
    g.field(10, L, "ROM CHIP", if (hw.hwRomRamSize() != 0) "FITTED" else "NOT FITTED");
    if (id.kos) |k| g.fieldf(11, L, "ROM/GEM VERSION", "KOS {d}.{d}", .{ k.kos_version >> 16, k.kos_version & 0xFFFF }) else g.field(11, L, "ROM/GEM VERSION", N_A);
    g.field(12, L, "SYSTEM TABLE", if (id.host == .board) ">= " ++ pages.TABLE_MIN ++ " (IMPORTS)" else "NONE (BY NAME)");
    g.field(13, L, "GEM", if (c.gem_ok and c.dialog_ok) "CONTEXT + DIALOGS" else if (c.gem_ok) "CONTEXT ONLY" else "NOT AVAILABLE");
    g.field(14, L, "RESOLUTION", probe.modeName(probe.plane(c.os, 0).mode, probe.reg8(hw.REG_RESOLUTION)));
    g.fieldf(15, L, "PLANES", "{d}", .{probe.planesReg()});
    g.fieldf(16, L, "FRAMES SHOWN", "{d}", .{probe.frameCounter()});
    frameTime(g, 17, c.frame_us);
    boot(g, 18, id);
}

fn hostName(h: ident.Host) []const u8 {
    return switch (h) {
        .board => "KESTREL BOARD",
        .browser => "BROWSER",
        .unclocked => "NATIVE OR HARNESS",
    };
}

/// The cart CPU of the host found: the board's is ZIGGY; elsewhere the host's JIT runs the wasm.
fn processor(h: ident.Host) []const u8 {
    return switch (h) {
        .board => "ZIGGY (RV32IM)",
        .browser => "WASM32 (HOST JIT)",
        .unclocked => N_A,
    };
}

fn frequency(g: *grid.Grid, row: usize, mhz10: u32) void {
    if (mhz10 == 0) return g.field(row, L, "FREQUENCY", N_A);
    var b: [16]u8 = undefined;
    g.fieldf(row, L, "FREQUENCY", "{s} MHZ (MEASURED)", .{pages.tenths(&b, mhz10)});
}

pub fn jobsName(j: ident.Jobs) []const u8 {
    return switch (j) {
        .coprocessor => "COPROCESSOR (TESTED)",
        .ziggy => "IN THE CART (TESTED)",
        .failed => "FAILED",
    };
}

fn boot(g: *grid.Grid, row: usize, id: *const ident.Ident) void {
    const k = id.kos orelse return g.field(row, L, "BOOT DEVICE", N_A);
    const dev: []const u8 = switch (k.boot_dev) {
        0 => "THE DESKTOP",
        1 => "DRIVE A",
        2 => "CARTRIDGE SLOT",
        else => "?",
    };
    g.fieldf(row, L, "BOOT DEVICE", "{s} ({s})", .{ dev, if (k.boot_kind == 1) "WARM" else "COLD" });
    if (k.ram_total == 0) return g.field(row + 1, L, "MACHINE RAM", N_A); // the host never called kosSetBoot
    g.fieldf(row + 1, L, "MACHINE RAM", "{d} Kbytes", .{k.ram_total / 1024});
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
