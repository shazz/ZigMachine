// --------------------------------------------------------------------------
// F3's parameter panel: twelve values (the curve's walker steps -- eight
// words, four bytes) printed in hex at the top of both screens, a cursor
// arrow, and the keys that edit them ($183CE, every 5th frame):
//   F1..F10 ($3B..$44), Tab..' ($0F..$28)   load one of 36 presets (then a
//            VBL that redraws all twelve values, $1895E)
//   1..0 ($02..$0B)                         the balls' colour set ($1B53C)
//   left / right ($4B/$4D)                  the column; down / up the row
//   Insert / Home ($52/$47)                 the value -1 / +1
//   Help / Undo ($62/$61)                   the value -8 / +8
// The ST reads $FFFC02, the last byte the keyboard sent, so a key acts on
// the next tick; here a press is kept until then (and acts once).
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const draw = @import("f3_draw.zig");

const TICK: u32 = 0x1AAA6;
const CURSOR: u32 = 0x1AAA2; // screen offset of the cursor
const INDEX: u32 = 0x1AA84; // the parameter under the cursor, 0..11
const VALUES: u32 = 0x1B4D8; // 12 x (screen offset, value address)
const CURSORS: u32 = 0x1B4A8; // 12 cursor offsets
const DIGITS: u32 = 0x1B3E2;
const FONT: u32 = 0x1C98C; // 8x8, a byte a row
const ARROW: u32 = 0x1B538;
const BLANK: u32 = 0x1B53A;
const F_PRESETS: u32 = 0x1AAF2;
const K_PRESETS: u32 = 0x1ACD2;
const WALKERS: u32 = 0x1AAAE;
const COLOURS: u32 = 0x1B53C;
const PALETTE: u32 = 0x1CA44;

var scan: u8 = 0;
var redraw: bool = false;

pub fn press(code: u8) void {
    scan = code;
}

pub fn reset() void {
    scan = 0;
    redraw = false;
}

/// $18AD4: a string of glyph numbers ($FF ends it) into one plane, a byte a
/// character (the next byte of the plane word, then the next group's).
fn text(r: *const st.Ram, s: u32, at: u32, odd: bool) void {
    var a = at + @intFromBool(odd);
    var bit = odd;
    var p = s;
    while (r.b(p) != 0xFF) : (p += 1) {
        const glyph = FONT + 8 * @as(u32, r.b(p));
        for (0..8) |row| r.sb(a + @as(u32, @intCast(row)) * st.LINE, r.b(glyph + @as(u32, @intCast(row))));
        a += if (bit) 7 else 1;
        bit = !bit;
    }
}

/// $18A40: parameter `INDEX`'s value in hex on the screen being drawn.
fn value(r: *const st.Ram) void {
    const i: u32 = r.w(INDEX);
    const at = r.l(VALUES + 8 * i);
    const src = r.l(VALUES + 8 * i + 4);
    const n: u32 = if (i <= 7) 4 else 2;
    const v: u16 = if (i <= 7) r.w(src) else r.b(src);
    for (0..n) |k| r.sb(DIGITS + @as(u32, @intCast(k)), @intCast((v >> @intCast(4 * (n - 1 - k))) & 15));
    r.sb(DIGITS + n, 0xFF);
    text(r, DIGITS, r.l(draw.DRAW) + at, false);
}

/// The main loop's tail: a value, or (every 5th frame) the keys.
pub fn tick(r: *const st.Ram) void {
    r.sl(TICK, r.l(TICK) -% 1);
    if (r.l(TICK) != 0) return value(r);
    r.sl(TICK, 5);
    for ([2]u32{ 0x60000, 0x70000 }) |s| text(r, BLANK, s + r.l(CURSOR), true);
    var d7 = r.w(INDEX);
    keys(r, scan, &d7);
    scan = 0;
    if (d7 >= 12) d7 = r.w(INDEX);
    r.sw(INDEX, d7);
    r.sl(CURSOR, r.l(CURSORS + 4 * @as(u32, d7)));
    for ([2]u32{ 0x70000, 0x60000 }) |s| text(r, ARROW, s + r.l(CURSOR), true);
}

fn keys(r: *const st.Ram, k: u8, d7: *u16) void {
    switch (k) {
        0x3B...0x44 => return preset(r, F_PRESETS + 4 * @as(u32, k - 0x3B)),
        0x0F...0x28 => return preset(r, K_PRESETS + 4 * @as(u32, k - 0x0F)),
        0x02...0x0B => return colours(r, COLOURS + 8 * @as(u32, k - 2)),
        0x4B, 0x4D => return column(d7, k),
        0x50 => d7.* +%= 1,
        0x48 => d7.* -%= 1,
        else => {},
    }
    const delta: i16 = switch (k) {
        0x52 => -1,
        0x47 => 1,
        0x62 => -8,
        0x61 => 8,
        else => return,
    };
    const at = r.l(VALUES + 8 * @as(u32, d7.*) + 4); // the NEW row's value
    if (r.w(INDEX) <= 7) {
        r.sw(at, r.w(at) +% @as(u16, @bitCast(delta)));
    } else {
        r.sb(at, r.b(at) +% @as(u8, @truncate(@as(u16, @bitCast(delta)))));
    }
}

/// Left / right: a column of the panel (four rows apart).
fn column(d7: *u16, k: u8) void {
    d7.* = if (k == 0x4B) d7.* -% 4 else d7.* +% 4;
}

fn preset(r: *const st.Ram, entry: u32) void {
    r.cp(WALKERS, r.l(entry), 44);
    redraw = true;
}

fn colours(r: *const st.Ram, set: u32) void {
    for (0..4) |k| {
        const at = PALETTE + 2 + 8 * @as(u32, @intCast(k));
        r.sl(at, r.l(set));
        r.sw(at + 4, r.w(set + 4));
    }
}

/// $1895E, the VBL a preset installs: all twelve values on both screens.
/// True if this VBL was it (the main loop then waits for the next one).
pub fn redrawAll(r: *const st.Ram) bool {
    if (!redraw) return false;
    redraw = false;
    const keep = r.w(INDEX);
    const drawn = r.l(draw.DRAW);
    for ([2]u32{ 0x70000, 0x60000 }) |s| {
        r.sl(draw.DRAW, s);
        var i: u16 = 12;
        while (i > 0) : (i -= 1) {
            r.sw(INDEX, i - 1);
            value(r);
        }
    }
    r.sl(draw.DRAW, drawn);
    r.sw(INDEX, keep);
    return true;
}
