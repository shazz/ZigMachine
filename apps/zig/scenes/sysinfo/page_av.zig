// --------------------------------------------------------------------------
// SysInfo pages 2 and 3 — VIDEO and SOUND (HWAM's Graphics and Sound panels).
//
// Video: the screen geometry is the ABI's (memmap.zig, the console's fixed
// identity); every plane's mode, stride and screen base, the resolution and
// the BEAM/flicker counters are read off the machine's registers; the blitter
// is asked to fill and read back (probe.blitterTest).
//
// Sound: a cart can read the player the host mirrors in (ZigOS.audio_mode;
// the board's firmware leaves it at 0), the song clock, the YM registers'
// mirror and its own queues' drop counts. Which chips are fitted, BARD and
// the audio module's version are not readable from a cart: n/a. Under them,
// the sound files on the disk (sysinfo/sound_list.zig): the selected one in
// inverse, as a GEM list shows its selection, and the one playing marked.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const hw = @import("hardware");
const sound_list = @import("sound_list.zig");
const sound_play = @import("sound_play.zig");
const grid = @import("grid.zig");
const pages = @import("pages.zig");
const probe = @import("probe.zig");

const L: usize = 0;
const R: usize = grid.COL2;
const N_A = pages.N_A;

pub fn video(g: *grid.Grid, c: *const pages.Ctx) void {
    pages.heading(g, 2, L, "VIDEO:");
    g.fieldf(3, L, "LOW RES", "{d}*{d}", .{ hw.WIDTH, hw.HEIGHT });
    g.fieldf(4, L, "MEDIUM RES", "{d}*{d}", .{ hw.MEDIUM_WIDTH, hw.MEDIUM_HEIGHT });
    g.fieldf(5, L, "WITH BORDERS", "{d}*{d}", .{ hw.PHYSICAL_WIDTH, hw.PHYSICAL_HEIGHT });
    g.field(6, L, "OVERSCAN", "BY THE RES TRICK");
    g.fieldf(7, L, "COLOURS", "{d} A PLANE", .{hw.PAL_BYTES / 4});
    g.field(8, L, "RESOLUTION REG", resName(probe.reg8(hw.REG_RESOLUTION)));
    g.fieldf(9, L, "BACKGROUND", "${X:0>6}", .{probe.reg32(hw.REG_BACKGROUND) & 0xFF_FFFF});
    g.fieldf(10, L, "RES FLICKERS", "{d}", .{probe.reg16(hw.REG_RES_FLICKER)});
    g.fieldf(11, L, "BEAM REFUSED", "{d}", .{probe.reg32(hw.REG_BEAM_DROPPED)});
    pages.heading(g, 13, L, "BLITTER:");
    g.field(14, L, "BLITTER", if (c.blit.works) "PRESENT (TESTED)" else "NOT FOUND");
    g.fieldf(15, L, "8 PX FILL COST", "{d} UNITS", .{c.blit.cycles});
    g.field(16, L, "CHISEL / SOFT", N_A);
    planes(g, c);
}

fn resName(r: u8) []const u8 {
    return switch (r) {
        hw.RES_PLANES => "LOW (PLANES)",
        hw.RES_TRUECOLOR => "TRUECOLOUR",
        hw.RES_MEDIUM => "MEDIUM",
        else => "UNKNOWN",
    };
}

fn planes(g: *grid.Grid, c: *const pages.Ctx) void {
    pages.heading(g, 2, R, "PLANES:");
    for (0..hw.NB_PLANES) |i| {
        const p = probe.plane(c.os, i);
        const row = 3 + i * 3;
        g.print(row, R, "PLANE {d}: {s} {s}", .{ i, if (p.enabled) "ON " else "OFF", probe.modeName(p.mode) });
        g.print(row + 1, R + 2, "BASE ${X:0>6} STRIDE {d} HSCROLL {d}", .{ p.fb, p.stride, p.hscroll });
    }
    pages.kbField(g, 16, R, "VRAM POOL", hw.VRAM_BYTES);
    pages.kbField(g, 17, R, "VRAM IN USE", probe.vramTop(c.os));
}

pub fn sound(g: *grid.Grid, c: *const pages.Ctx) void {
    pages.heading(g, 2, L, "SOUND:");
    g.field(3, L, "CHIPS FITTED", N_A);
    g.field(4, L, "SOUND CPU", N_A);
    g.field(5, L, "AUDIO VERSION", N_A);
    g.fieldf(6, L, "PLAYER", "{d} {s}", .{ c.os.audio_mode, playerName(c.os.audio_mode) });
    songTime(g, 7, c.os.song_ms);
    g.fieldf(8, L, "SNDH CALLS LOST", "{d}", .{zg.sndhCallsDropped()});
    g.fieldf(9, L, "EFFECTS LOST", "{d}", .{zg.sfxDropped()});
    g.put(11, L, "THE PLAYER IS WHAT THE HOST MIRRORS IN;", .plain);
    g.put(12, L, "THE BOARD'S FIRMWARE LEAVES IT AT 0.", .plain);
    ymRegs(g, c);
    soundFiles(g, c.snd);
}

const FILES_ROW: usize = 14;
const ROW_W: usize = 64; // a file's line, the inverse bar's width

/// The disk's sound files, the status of the last play, and the keys.
fn soundFiles(g: *grid.Grid, l: *const sound_list.List) void {
    pages.heading(g, FILES_ROW, L, "SOUND FILES ON DRIVE A:");
    if (l.n == 0) g.put(FILES_ROW + 1, L, "NO SOUND FILES ON THE DISK", .plain);
    for (l.items[0..l.n], 0..) |*e, idx| {
        const i: u8 = @intCast(idx);
        var b: [ROW_W]u8 = undefined;
        @memset(&b, ' ');
        const mark = if (l.playing == i) "PLAYING" else "";
        _ = std.fmt.bufPrint(&b, " {s:<14} {d:>6} BYTES  {s:<22} {s}", .{ sound_list.List.nameOf(e), e.len, kindName(e.kind), mark }) catch {};
        g.put(FILES_ROW + 1 + i, L, &b, if (l.sel == i) .inverse else .plain);
    }
    const row = FILES_ROW + 2 + sound_list.MAX;
    if (l.playing) |i| g.fieldf(row, L, "STATUS", "PLAYING {s}", .{sound_list.List.nameOf(&l.items[i])}) else g.field(row, L, "STATUS", statusName(l.status));
    g.put(row + 1, L, "UP/DOWN: SELECT   P OR FIRE: PLAY   S: STOP", .plain);
}

fn kindName(k: sound_list.Kind) []const u8 {
    return switch (k) {
        .sndh => "SNDH (68000 + YM)",
        .sap => "SAP (6502 + POKEY)",
        .pcm => std.fmt.comptimePrint("PCM {d} HZ", .{sound_play.PCM_HZ}),
    };
}

fn statusName(s: sound_list.Status) []const u8 {
    return switch (s) {
        .idle, .playing => "READY",
        .stopped => "STOPPED",
        .not_found => "NOT READ OFF THE DISK",
        .too_big => "TOO BIG FOR THE BUFFER",
        .bad_image => "NOT WHAT ITS NAME SAYS",
        .refused => "REFUSED BY THE HOST",
    };
}

/// What ZigOS.audio_mode means (apps/zig/demo_audio_*.zig set it).
fn playerName(mode: u8) []const u8 {
    return switch (mode) {
        0 => "NONE",
        1 => "PAULA (MOD/XM)",
        2 => "YM DUMP",
        3 => "SAMPLE",
        4 => "SNDH (68000)",
        5 => "SAP (POKEY)",
        else => "UNKNOWN",
    };
}

fn songTime(g: *grid.Grid, row: usize, ms: u32) void {
    g.fieldf(row, L, "SONG TIME", "{d}:{d:0>2}.{d}", .{ ms / 60_000, ms / 1000 % 60, ms / 100 % 10 });
}

/// The YM2149's 14 registers as the host mirrors them, HWAM-style hex.
fn ymRegs(g: *grid.Grid, c: *const pages.Ctx) void {
    pages.heading(g, 2, R, "YM2149 REGISTERS (MIRROR):");
    for (0..14) |r| {
        const row = 3 + r % 7;
        const col = R + (r / 7) * 18;
        g.print(row, col, "R{d:0>2}: ${X:0>2}", .{ r, c.os.ym_regs[r] });
    }
}
