// --------------------------------------------------------------------------
// P1 ".dhS." logo. Kernel $1CED8 (generated code at $9617E), top border open,
// 270 lines. Line i: the line colour d0 = LC[T][i] is written in the blank of
// the line before (rel 248+512i), then 52 x 8 px cells from rel 336+512i, each
// register[logo pixel] with register 0 = d0 and 1..13 the palette; a row not
// revealed yet is 52 x d0. The rows are revealed 3 a frame in the order of the
// table at $4302E; the line-colour tables and the palette fade through 16 / 24
// steps built with the global fader.
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const assets = @import("assets.zig");

const ROWS = 270;

var revealed: [ROWS]bool = undefined;
var cnt: u32 = 0; // $1D0A2
var palofs: u32 = 0; // $42CA4, 30 bytes a palette
var T: u32 = 0; // $42CA6, $21C bytes a line-colour table
var c1ce50: u32 = 0;
var t1ce74: u16 = 0;
var i1ce76: u32 = 0;
var t1ce2e: u16 = 0;
var c1ced4: u16 = 0;
var c1ced6: u32 = 0;
var pal: [24][15]u16 = undefined;
var lines: [16][ROWS]u16 = undefined;

pub fn reset() void {
    @memset(&revealed, false);
    cnt = 0;
    palofs = rip.P1_PALOFS;
    T = rip.P1_T;
    c1ce50 = 1;
    t1ce74 = 0;
    i1ce76 = rip.P1_I1CE76;
    t1ce2e = 0;
    c1ced4 = 1;
    c1ced6 = 1;
}

/// $1CDE6: the palette fade (23 steps) and the line-colour tables: 7 fade
/// steps from black, then 8 all-component steps towards white.
pub fn init() void {
    core.colour = 0;
    var p = [_]u16{0} ** 15;
    pal[0] = p;
    for (1..24) |k| {
        core.step1(&p, &rip.P1_PAL_TGT);
        pal[k] = p;
    }
    @memset(&lines[0], 0);
    for (1..8) |k| {
        lines[k] = lines[k - 1];
        core.step1(&lines[k], &rip.P1_LINE_TGT);
    }
    @memset(&lines[15], 0x777);
    for (0..8) |k| core.step3(&lines[8 + k], &lines[7 + k], &lines[15]);
}

pub fn vbl() void {
    core.colour = 0;
}

/// $1D02C: three more rows a frame.
pub fn reveal() void {
    for (0..3) |_| {
        revealed[rip.P1_ORDER[cnt]] = true;
        if (cnt != 0x10D) cnt += 1;
    }
}

/// $1CE30: every 25 frames the next line-colour table, up to table 7.
pub fn linesUp() void {
    c1ce50 -= 1;
    if (c1ce50 == 0) {
        c1ce50 = 0x19;
        if (T != 0xEC4) T += 0x21C;
    }
}

/// $1CE52: every second frame the next table from the list at $1CE78.
pub fn linesSeq() void {
    t1ce74 ^= 0xFFFF;
    if (t1ce74 == 0) {
        T = rip.P1_TSEQ[i1ce76 >> 1];
        if (i1ce76 != 0x2E) i1ce76 += 2;
    }
}

/// $1CE16: every second frame the palette one step darker.
pub fn palDown() void {
    t1ce2e ^= 0xFFFF;
    if (t1ce2e != 0 and palofs != 0) palofs -= 0x1E;
}

/// $1CEA8: jump to the white table, then walk back down, one every 2 frames.
pub fn whiteOut() void {
    c1ced4 -%= 1;
    if (c1ced4 == 0) T = 0x1FA4;
    c1ced6 -= 1;
    if (c1ced6 == 0) {
        c1ced6 = 2;
        if (T != 0) T -= 0x21C;
    }
}

pub fn kernel(l0: u32) void {
    const p = &pal[palofs / 30];
    const lt = &lines[T / 0x21C];
    for (0..ROWS) |i| {
        const d0 = lt[i];
        const line: u32 = @intCast(512 * i);
        out.emit(l0, 248 + line, d0);
        var regs: [14]u16 = undefined;
        regs[0] = d0;
        @memcpy(regs[1..14], p[1..14]);
        const row = assets.p1_logo[i * 52 ..][0..52];
        for (0..52) |j| {
            const v = if (revealed[i]) regs[@min(row[j], 13)] else d0;
            out.emit(l0, 336 + 8 * @as(u32, @intCast(j)) + line, v);
        }
    }
    out.emit(l0, 336 + 8 * 52 + 512 * 269 + 4, 0);
    core.colour = 0;
}
