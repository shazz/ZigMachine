// --------------------------------------------------------------------------
// SysInfo page 3 — SOUND (HWAM's Sound panel).
//
// A cart reads the player the host mirrors in (ZigOS.audio_mode, song_ms and
// the YM registers: the page's worklet in the browser, BARD's S2C bank on the
// board since system table 1.2, decisions.md 2026-10-18) and its own queues'
// drop counts. The chips are the audio SDK's set, which every host of this
// machine plays; WHO plays them is the host's (ident.zig): BARD, the sound CPU,
// and CHORUS's four Paula channels on the board, the AudioWorklet on the page.
// The audio module's version is not in the system table: n/a. Under them, the
// sound files on the disk (sysinfo/sound_list.zig): the selected one in
// inverse, as a GEM list shows its selection, and the one playing marked.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const hw = @import("hardware");
const sound_list = @import("sound_list.zig");
const sound_play = @import("sound_play.zig");
const grid = @import("grid.zig");
const pages = @import("pages.zig");
const ident = @import("ident.zig");

const L: usize = 0;
const R: usize = grid.COL2;
const N_A = pages.N_A;

pub fn sound(g: *grid.Grid, c: *const pages.Ctx) void {
    pages.heading(g, 2, L, "SOUND:");
    const h = c.id.host;
    g.field(3, L, "CHIPS FITTED", "YM POKEY SID AY PAULA");
    g.field(4, L, "SOUND CPU", if (h == .board) "BARD (RV32I)" else if (h == .browser) "AUDIOWORKLET" else N_A);
    g.field(5, L, "PAULA", if (h == .board) "CHORUS, 4 CH, PAN" else if (h == .browser) "4 CH (WORKLET)" else N_A);
    g.field(6, L, "AUDIO VERSION", N_A);
    g.fieldf(7, L, "PLAYER", "{d} {s}", .{ c.os.audio_mode, playerName(c.os.audio_mode) });
    songTime(g, 8, c.os.song_ms);
    g.fieldf(9, L, "SNDH CALLS LOST", "{d}", .{zg.sndhCallsDropped()});
    g.fieldf(10, L, "EFFECTS LOST", "{d}", .{zg.sfxDropped()});
    g.put(11, L, "PLAYER AND YM: THE HOST'S MIRROR (THE", .plain);
    g.put(12, L, "WORKLET, OR BARD'S S2C BANK ON THE BOARD).", .plain);
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
        .xm => "XM (TRACKER + PAULA)",
        .hip => "HIP (68000 + PAULA)",
        .kt => "KT (KLYSTRACK + PAULA)",
        .sid => "SID (6502 + SID)",
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
        .rsid => "RSID: A C64 PROGRAM, CANNOT PLAY",
    };
}

/// What ZigOS.audio_mode means (apps/zig/demo_audio_*.zig set it).
fn playerName(mode: u8) []const u8 {
    return switch (mode) {
        0 => "NONE",
        1 => "PAULA (MOD/XM/HIP/KT/SID)",
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
