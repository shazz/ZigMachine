// --------------------------------------------------------------------------
// SysInfo page 2 — VIDEO (HWAM's Graphics panel).
//
// The screen geometry is the ABI's (memmap.zig, the console's fixed
// identity); every plane's mode, stride and screen base, the resolution and
// the BEAM/flicker counters are read off the machine's registers. The blitter
// is asked to fill and read back, directly and through its QUEUE (probe.zig,
// ident.zig); the desk mode is the machine's answer (hwDeskAvailable). The
// true-colour plane is the SDK's (HW 1.15.0): every machine of this SDK has it.
// Who composes the planes is the host's: FRESCO on the board, the page's
// canvases in the browser.
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
    pages.heading(g, 2, L, "VIDEO:");
    g.fieldf(3, L, "LOW RES", "{d}*{d}, {d} COLOURS", .{ hw.WIDTH, hw.HEIGHT, hw.PAL_BYTES / 4 });
    g.fieldf(4, L, "MEDIUM RES", "{d}*{d}", .{ hw.MEDIUM_WIDTH, hw.MEDIUM_HEIGHT });
    g.fieldf(5, L, "WITH BORDERS", "{d}*{d}", .{ hw.PHYSICAL_WIDTH, hw.PHYSICAL_HEIGHT });
    g.field(6, L, "DESK MODE", if (c.id.desk_ok) "640*480 (AVAILABLE)" else "NOT ON THIS MACHINE");
    g.field(7, L, "TRUE COLOUR", "RGB565 PLANES (SDK)");
    g.field(8, L, "OVERSCAN", "BY THE RES TRICK");
    g.field(9, L, "RESOLUTION REG", resName(probe.reg8(hw.REG_RESOLUTION)));
    g.fieldf(10, L, "RES FLICKERS", "{d}", .{probe.reg16(hw.REG_RES_FLICKER)});
    g.fieldf(11, L, "BEAM REFUSED", "{d}", .{probe.reg32(hw.REG_BEAM_DROPPED)});
    g.field(12, L, "COMPOSITOR", compositor(c.id.host));
    pages.heading(g, 14, L, "BLITTER:");
    g.field(15, L, "BLITTER", if (c.blit.works) "PRESENT (TESTED)" else "NOT FOUND");
    g.fieldf(16, L, "8 PX FILL COST", "{d} UNITS", .{c.blit.cycles});
    g.field(17, L, "QUEUE (V2)", if (c.id.queue_ok) "PRESENT (TESTED)" else "NOT FOUND");
    g.field(18, L, "ENGINE", engine(c.id.host));
    planes(g, c);
}

fn compositor(h: ident.Host) []const u8 {
    return switch (h) {
        .board => "FRESCO, 4 PLANES",
        .browser => "THE PAGE'S CANVASES",
        .unclocked => N_A,
    };
}

/// The board's blitter is CHISEL (RTL); elsewhere the machine's own code does the ops.
fn engine(h: ident.Host) []const u8 {
    return switch (h) {
        .board => "CHISEL (KESTREL)",
        .browser => "THE MACHINE (SOFT)",
        .unclocked => N_A,
    };
}

fn resName(r: u8) []const u8 {
    return switch (r) {
        hw.RES_PLANES => "LOW (PLANES)",
        hw.RES_TRUECOLOR => "TRUECOLOUR",
        hw.RES_MEDIUM => "MEDIUM",
        hw.RES_DESK => "DESK",
        else => "UNKNOWN",
    };
}

fn planes(g: *grid.Grid, c: *const pages.Ctx) void {
    pages.heading(g, 2, R, "PLANES:");
    const res = probe.reg8(hw.REG_RESOLUTION);
    for (0..hw.NB_PLANES) |i| {
        const p = probe.plane(c.os, i);
        const row = 3 + i * 3;
        g.print(row, R, "PLANE {d}: {s} {s}", .{ i, if (p.enabled) "ON " else "OFF", probe.modeName(p.mode, if (i == 0) res else 0) });
        g.print(row + 1, R + 2, "BASE ${X:0>6} STRIDE {d} HSCROLL {d}", .{ p.fb, p.stride, p.hscroll });
    }
    pages.kbField(g, 16, R, "VRAM POOL", hw.VRAM_BYTES);
    pages.kbField(g, 17, R, "VRAM IN USE", probe.vramTop(c.os));
}
