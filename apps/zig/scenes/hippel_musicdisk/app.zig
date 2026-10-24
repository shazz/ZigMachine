// --------------------------------------------------------------------------
// The musicdisk's one screen, its main loop ($0494) and its tune keys ($04E2).
// The scene header (../hippel_musicdisk.zig) maps every Amiga register used.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const C = @import("amiga_copper.zig");
const S = @import("screen.zig");
const tunes = @import("tunes.zig");

pub const BACK = 0; // the 400x280 overscan plane: nothing but COLOR00
pub const FRONT = 1; // the text and its shadow, a normal 320x200 plane
pub const SHADOW: u8 = 1 + C.COLUMNS; // COLOR09
/// Amiga beam line -> physical row: DIWSTRT's line $40 lands on the first
/// visible row (40), so the bars ($2F.., $108..) sit in the open borders.
pub const LINE0: u16 = 0x40 - zg.VERTICAL_BORDERS_HEIGHT;
/// The text field's left edge in the 320 window: the DIW ($81..$1C1) centred in
/// the 400-pixel raster, then DDFSTRT $48 is 32 pixels in.
pub const TEXT_X: usize = 32;
const K_ESC: u32 = 0xE012;

pub const TextPal = zg.LinePalette(C.COLUMNS);
pub var text_pal: TextPal = undefined;
pub var bars: [1]zg.copper.Table = undefined;

pub var ok: bool = false;
pub var phase: u32 = 0; // the original's frames (50 Hz)
var tick: u32 = 0; // 60 Hz frames into the 50 Hz phase: 5 steps every 6
var shown: u32 = 0xFFFF_FFFF;
pub var wants_quit: bool = false;

pub const Demo = struct {
    pub fn init(_: *Demo, zigos: *zg.ZigOS) void {
        ok = false;
        phase = 0;
        tick = 0;
        shown = 0xFFFF_FFFF;
        wants_quit = false;
        zigos.setBackgroundColor(zg.Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        for (2..zg.NB_PLANES) |p| zigos.lfbs[p].is_enabled = false;
        initBack(&zigos.lfbs[BACK]);
        initFront(&zigos.lfbs[FRONT]);
        tunes.select(tunes.START);
        ok = true;
    }

    pub fn update(_: *Demo, _: *zg.ZigOS, _: f32) void {
        if (!ok) return;
        tick += 5;
        if (tick >= 6) {
            tick -= 6;
            phase +%= 1;
        }
    }

    pub fn render(_: *Demo, _: *zg.ZigOS, _: f32) void {
        if (!ok or phase == shown) return;
        fillText(phase);
        fillBars(phase);
        shown = phase;
    }

    pub fn key(_: *Demo, cp: u32) void {
        if (cp == K_ESC) wants_quit = true;
        const lower = if (cp >= 'A' and cp <= 'Z') cp + 32 else cp;
        if (lower >= 'a' and lower < 'a' + tunes.KEYS.len) tunes.select(@intCast(lower - 'a'));
    }

    /// The joystick/remote Back (6) leaves too; 'a'/'d' also arrive here as
    /// left/right and mean nothing.
    pub fn input(_: *Demo, dir: u32) void {
        if (dir == 6) wants_quit = true;
    }

    pub fn pollCart(_: *Demo) i32 {
        return if (wants_quit) -1 else 0;
    }
};

/// COLOR00 on every line, edge to edge through every open border: an overscan
/// plane of index 0 whose entry the copper writes per line.
fn initBack(fb: *zg.LogicalFB) void {
    fb.is_enabled = true;
    fb.palette[0] = C.rgba(0x000);
    fb.setOverscanBuffer(); // all index 0
    zg.copper.install(fb, &.{0}, &bars, .{ .flicker = true });
}

/// PF1 over PF2 composed once: a text pixel takes the entry of the COLOR01 MOVE
/// it falls under (each lands one pixel before its 8-pixel column), a shadow
/// pixel COLOR09, anything else 0 (transparent: plane 0 shows through).
fn initFront(fb: *zg.LogicalFB) void {
    fb.is_enabled = true;
    fb.palette[SHADOW] = C.rgba(C.WALK.color09);
    for (0..zg.HEIGHT) |y| {
        const row = fb.fb[y * fb.stride ..][0..zg.WIDTH];
        @memset(row, 0);
        if (y >= S.LINES) continue;
        for (0..S.W + 1) |tx| {
            row[TEXT_X + tx] = if (S.bit(y + 1, tx))
                1 + @as(u8, @intCast(@min(C.COLUMNS - 1, (tx + 1) / 8)))
            else if (tx > 0 and S.bit(y, tx - 1)) SHADOW else 0;
        }
    }
    text_pal.init();
    for (S.TEXT_LINES) |n| text_pal.used[n] = C.COLUMNS;
    text_pal.install(fb);
}

/// The blitter's copper scroll ($03A6): line n shows copper row (n + phase) mod
/// 192. Lines $100..$106 have no MOVEs of their own: COLOR01 keeps line $FF's
/// last one. Only lines with text pixels are written.
fn fillText(p: u32) void {
    const k = p % C.TEXT_ROWS;
    const tail = C.TEXT_RGBA[(C.TEXT_ROWS - 1 + k) % C.TEXT_ROWS][C.COLUMNS - 1];
    for (S.TEXT_LINES) |n| {
        if (n < C.TEXT_ROWS) {
            text_pal.colours[n] = C.TEXT_RGBA[(n + k) % C.TEXT_ROWS];
        } else text_pal.colours[n] = @splat(tail);
    }
}

/// $025E's sixteen colours into each bar's COLOR00 moves. The top bar shows the
/// PREVIOUS rotation: the main loop starts at line $FF and its blits run ~107
/// lines, so the update lands after the top bar has gone by (the screenshot
/// shows exactly that), but before the bottom one.
fn fillBars(p: u32) void {
    const t = &bars[0];
    const top = &C.TOP_BAR[(p + 7) % 8];
    const bot = &C.BOTTOM_BAR[p % 8];
    for (0..C.BAR_LINES) |j| {
        t[C.WALK.move00_line[C.TOP_MOVE + j] - LINE0] = top[j];
        t[C.WALK.move00_line[C.BOTTOM_MOVE + j] - LINE0] = bot[j];
    }
}
