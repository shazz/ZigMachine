// --------------------------------------------------------------------------
// P7 216-frame animation. Kernel $187D2: 200 lines, line k runs routine RT[k]:
// 52 writes from rel 332+512k: d0, d0, 48 x 8 px cells, d0, d0 (registers
// d0..a5 = 14 palette words); a hidden line is 52 x d0. Routine r holds
// animation row r, so each row shows 8 lines. The lines are revealed and
// hidden in the order of the table at $3ABA0.
// One animation frame is rendered per main call ($18F64). Timer A preempts
// that render at row 22, cell 4: rows 0..21 and 4 cells of row 22 are new when
// the kernel runs, the rest is written after it. That tear is the original's.
// --------------------------------------------------------------------------
const core = @import("core.zig");
const out = @import("out.zig");
const rip = @import("rip.zig");
const assets = @import("assets.zig");

const NONE: u8 = 0xFF;
const SPLIT_ROW = 22;
const SPLIT_CELL = 4;

var fr: u32 = 0; // $18F8A, byte offset of the next animation frame
var rev: u32 = 0; // $1913C
var hid: u32 = 0; // $1916E
var pal: [16]u16 = undefined;
var c187a0: u16 = 0;
var t187a2: u16 = 0;
var c187d0: u32 = 0;
var rows: [25][48]u8 = undefined;
var rt: [200]u8 = undefined; // animation row per line, NONE = hidden

pub fn reset() void {
    fr = rip.P7_FR;
    rev = rip.P7_REV;
    hid = rip.P7_HID;
    pal = rip.P7_PAL;
    c187a0 = rip.P7_C187A0;
    t187a2 = rip.P7_T187A2;
    c187d0 = rip.P7_C187D0;
    for (&rows) |*r| @memset(r, 0);
    @memset(&rt, NONE);
}

pub fn init() void {
    core.colour = 0;
    for (&rows) |*r| @memset(r, 0);
    @memset(&rt, NONE);
}

pub fn vbl() void {
    core.colour = 0;
}

/// Nibble `i` of the animation (two a byte, high first).
inline fn anim(i: u32) u8 {
    const b = assets.p7_anim[i >> 1];
    return if (i & 1 == 0) b >> 4 else b & 15;
}

fn copyRow(o: u32, r: usize, from: usize) void {
    for (from..48) |c| rows[r][c] = anim(o + @as(u32, @intCast(r * 48 + c)));
}

/// $18F64 up to where Timer A stops it; the rest runs after the kernel.
fn render() void {
    const o = fr;
    for (0..SPLIT_ROW) |r| copyRow(o, r, 0);
    for (0..SPLIT_CELL) |c| rows[SPLIT_ROW][c] = anim(o + SPLIT_ROW * 48 + @as(u32, @intCast(c)));
    core.later(.p7_rest, o);
    fr = if (fr >= 0x3EFD0) 0 else fr + 0x4B0;
}

pub fn renderRest(o: u32) void {
    copyRow(o, SPLIT_ROW, 0);
    for (SPLIT_ROW + 1..25) |r| copyRow(o, r, 0);
}

pub fn reveal() void {
    const k = rip.P7_ORDER[rev];
    rt[k] = k / 8;
    if (rev < 0xC7) rev += 1;
}

fn hide() void {
    rt[rip.P7_ORDER[hid]] = NONE;
    if (hid < 0xC7) hid += 1;
}

pub fn m18748() void {
    render();
    core.later(.p7_reveal, 0);
    core.later(.p7_reveal, 0);
}

pub fn m18756() void {
    render();
    core.later(.p7_m18756b, 0);
}

pub fn m18756b() void {
    c187a0 -%= 1;
    if (c187a0 == 0) {
        @memset(&pal, 0x444);
        return;
    }
    t187a2 ^= 0xFFFF;
    if (t187a2 == 0) core.step1(&pal, &rip.P7_TGT_27444);
}

pub fn m187a4() void {
    render();
    core.later(.p7_m187a4b, 0);
}

pub fn m187a4b() void {
    hide();
    c187d0 -= 1;
    if (c187d0 == 0) {
        c187d0 = 4;
        core.step1(&pal, &rip.P7_TGT_273E4);
    }
}

pub fn kernel(l0: u32) void {
    const d0 = pal[0];
    for (rt, 0..) |r, k| {
        const base: u32 = 332 + 512 * @as(u32, @intCast(k));
        for (0..52) |i| {
            const v = if (r == NONE or i < 2 or i >= 50) d0 else pal[@min(rows[r][i - 2], 13)];
            out.emit(l0, base + 8 * @as(u32, @intCast(i)), v);
        }
    }
    out.emit(l0, 102716, 0);
    core.colour = 0;
}
