// --------------------------------------------------------------------------
// THE GAG: "...oh, the KESTREL can do more than that!"
//
//   0..150    the ST screen goes on, but its timing slips: more and more lines
//             of the copper take random colours, and on more and more frames
//             the border flicker misses the magic column, so the machine
//             paints noise in every open border (a botched cycle count on a
//             real ST does exactly that)
//   150..200  the picture freezes, the music dies, every frame mistimed
//   200..330  black; a terminal types its verdict
//   330..360  the screen burns to white, and the newschool starts
//
// Deterministic: the "random" is a hash of the tick and the line.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const T = @import("timeline.zig");
const raster = @import("raster.zig");
const old = @import("old.zig");
const logo = @import("logo.zig");
const app = @import("app.zig");

pub const FREEZE: u32 = 150;
pub const TERM: u32 = 200;
pub const BURN: u32 = 330;
const INK: u8 = 250;
const PAPER: u8 = 0;
const SPEED = 2; // ticks a character

const LINES = [_][]const u8{
    "KESTREL SOC  ZIGGY RV32IMF @ 100 MHZ",
    "ST COMPATIBLE MODE ............. OK",
    "",
    "HOLD ON.",
    "THE KESTREL CAN DO MORE THAN THAT.",
    "",
    "RUN ANIMA.NEW",
};

fn hash(a: u32, b: u32) u32 {
    var h = a *% 0x9E37_79B1 ^ b *% 0x85EB_CA6B;
    h ^= h >> 15;
    return h *% 0x2C1B_3C6D;
}

var term_ready = false;

pub fn enter(fb: *zg.LogicalFB, bl: *zg.Blitter, jumped: bool) void {
    if (jumped) old.enter(fb, bl); // dropped into the gag: set the ST screen up first
    term_ready = false;
}

pub fn draw(fb: *zg.LogicalFB, bl: *zg.Blitter, lt: u32, advance: bool) void {
    if (lt < FREEZE) {
        logo.tear = @min(5, lt * lt * 6 / (FREEZE * FREEZE));
        old.draw(fb, bl, T.GAG - 1 + lt, false, advance);
        const sev = lt * lt * 256 / (FREEZE * FREEZE); // 0..255, slipping faster and faster
        for (0..raster.ROWS) |r| {
            if (hash(lt, @intCast(r)) & 255 < sev / 2) raster.lines[r][0] = hash(r, lt) | 0xFF00_0000;
        }
        raster.timing(fb, hash(lt, 7) & 255 >= sev);
        return;
    }
    if (lt < TERM) {
        raster.timing(fb, false);
        return;
    }
    raster.timing(fb, true);
    if (!term_ready) {
        term_ready = true;
        bl.clear(fb, PAPER);
        raster.use(&.{});
        raster.openAll();
        for (0..256) |i| fb.palette[i] = 0xFF00_0000;
    }
    fb.palette[INK] = if (lt >= BURN) white(lt) else 0xFF66_FF99;
    if (lt >= BURN) fb.palette[PAPER] = white(lt);
    typeText(fb, lt - TERM);
}

fn white(lt: u32) u32 {
    const k = (lt - BURN) * 255 / (T.TUNNEL - T.GAG - BURN);
    return 0xFF00_0000 | k << 16 | k << 8 | k;
}

/// The terminal: characters typed SPEED ticks apart, a block cursor blinking.
fn typeText(fb: *zg.LogicalFB, lt: u32) void {
    var left: u32 = lt / SPEED;
    const os = app.os orelse return;
    for (LINES, 0..) |line, i| {
        const y: i16 = @intCast(84 + i * 14);
        const n = @min(line.len, left);
        os.printText(fb, "> ", 44, y, INK, PAPER);
        os.printText(fb, line[0..n], 60, y, INK, PAPER);
        if (n < line.len or i == LINES.len - 1) {
            const cur: []const u8 = if (lt & 16 != 0) "_" else " ";
            os.printText(fb, cur, @intCast(60 + n * 8), y, INK, PAPER);
            return;
        }
        left = if (left > n + 6) left - @as(u32, @intCast(n)) - 6 else 0; // a pause at a line's end
    }
}
