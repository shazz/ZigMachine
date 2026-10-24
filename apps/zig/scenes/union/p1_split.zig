// --------------------------------------------------------------------------
// Union main -- plane 1 carries the actors AND the scrolltext, with a palette
// split between them (the ST's split-palette trick, from the plane's HBL).
//
// The scrolltext had a plane of its own (P2): one more FRESCO pass per line,
// ~1.1 Mc a frame on the board. Its 252 colours (p2.pal 1..252) and the
// actors' 37 (runner 1..7, ghosts 17..47, credits 48..49) don't fit one
// palette, but they never share a line: the actors live on rows 23..146, the
// text on rows 207..259. So P1 holds p2.pal everywhere, and the actors' slots
// are switched: at line 0 they take the actors' colours (bank A), at SPLIT the
// scrolltext's (bank B). 74 colour writes a frame, in the handler that already
// flickers P1's borders open on every line.
//
// The text is opaque where it is drawn and was the top plane, drawn after
// everything on P1 here: the composited picture is the same (composite_hash.mjs).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;
const gpu = @import("../union_common/gpu.zig");

/// First line with bank B: after the actors' last row, at or before the text's first.
pub const SPLIT: u16 = 180;

/// The actors' slots: runner 1..7, ghost g at 17 + 8g .. 23 + 8g, credits FACE/SHADOW 48, 49.
pub const A_SLOTS = blk: {
    var t: [37]u8 = undefined;
    var n: usize = 0;
    for (1..8) |c| {
        t[n] = c;
        n += 1;
    }
    for (0..4) |g| for (1..8) |c| {
        t[n] = 16 + 8 * g + c;
        n += 1;
    };
    t[n] = 48;
    t[n + 1] = 49;
    break :blk t;
};

const p2_pal = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/union_main/p2.pal"));

/// Bank B: p2.pal's colours at the actors' slots.
const bank_b: [A_SLOTS.len]u32 = blk: {
    var t: [A_SLOTS.len]u32 = undefined;
    for (A_SLOTS, 0..) |s, i| t[i] = p2_pal[s].toRGBA();
    break :blk t;
};
var bank_a: [A_SLOTS.len]u32 = [_]u32{0} ** A_SLOTS.len; // the actors' colours, the credits' alpha live

fn indexOf(slot: u8) usize {
    for (A_SLOTS, 0..) |s, i| if (s == slot) return i;
    unreachable; // a slot outside bank A is not the actors'
}

/// Call after the actors set their colours on P1: bank A is read back from the plane, every
/// other slot takes p2.pal for good, and the handler takes over P1's HBL.
pub fn init(p1: *LogicalFB) void {
    for (A_SLOTS, 0..) |s, i| bank_a[i] = p1.palette[s];
    for (1..256) |s| {
        if (isA(@intCast(s))) continue;
        p1.palette[s] = p2_pal[s].toRGBA();
    }
    p1.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, handler);
}

fn isA(slot: u8) bool {
    for (A_SLOTS) |s| if (s == slot) return true;
    return false;
}

/// An actor's colour: shown from the next frame's line 0 (the slot holds bank B below SPLIT).
pub fn setA(slot: u8, c: Color) void {
    bank_a[indexOf(slot)] = c.toRGBA();
}

// P1 spans the full 400x280 plane (credits in the top border, the text across both side
// borders and into the bottom one): its borders stay open on every line, flickered at OVERSCAN_MAGIC_X.
fn handler(fb: *LogicalFB, zigos: *ZigOS, line: u16, x: u16) void {
    _ = zigos;
    _ = x;
    if (line == 0) write(fb, &bank_a) else if (line == SPLIT) write(fb, &bank_b);
    fb.flickerBorder();
}

fn write(fb: *LogicalFB, bank: *const [A_SLOTS.len]u32) void {
    for (A_SLOTS, bank) |s, v| fb.palette[s] = v;
}

// What P1 draws where: the bank each needs holds on its rows.
const credits_rows = @import("credits.zig").ROWS;
const runner = @import("runner.zig");
const runner_rows = runner.ROWS;
const band = @import("scroller.zig");
comptime {
    if (credits_rows[1] > SPLIT or runner_rows[1] > SPLIT or band.BAND_TOP < SPLIT)
        @compileError("p1_split: an actor reaches below SPLIT or the text above it");
}

/// Erase what P1 drew last frame: the whole plane the first time, then only the runner's
/// box. The credits page stays drawn while it shows (credits.zig erases its own box) and the
/// text's band is rewritten whole every frame (scroller.zig).
pub fn erase(p1: *LogicalFB, whole: bool) void {
    if (whole) return gpu.clear(p1, 0);
    const box = runner.BOX;
    gpu.fill(p1, box[0], runner_rows[0], box[1] - box[0], runner_rows[1] - runner_rows[0], 0);
}
