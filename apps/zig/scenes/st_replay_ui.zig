// --------------------------------------------------------------------------
// ST Replay — screen layout. The original is not a windowed GEM application at
// all: it is one full-screen medium-res (640x200) panel of key bindings over a
// green stippled desktop, a one-line status strip, and a big waveform box with a
// red centre line. Geometry here is measured off a screenshot of the real 3.01
// screen, in the same 640x200 the original ran in:
//
//   panel   x 14..625  y   6..107   (2px black border, white ground)
//   status  x 29..610  y 110..121
//   wave    x 17..621  y 125..191   centre line at y 159
//   rows    y 26, step 8 (ten rows of bindings)
//
// Split from st_replay.zig so the app file stays state + input and this one is
// the picture. The binding tables are data: one row each, laid out by column.
// --------------------------------------------------------------------------
const rom = @import("rom_sdk");
const Rect = rom.Rect;

pub const SW: i16 = 640;
pub const SH: i16 = 200;

pub const PANEL = Rect{ .x = 14, .y = 6, .w = 612, .h = 102 };
pub const STATUS = Rect{ .x = 29, .y = 110, .w = 582, .h = 12 };
pub const WAVE = Rect{ .x = 17, .y = 125, .w = 605, .h = 67 };
pub const WAVE_MID: i16 = 159;

const TITLE_Y: i16 = 10;
const ROW0: i16 = 26; // first binding row
const ROW_H: i16 = 8;
pub const ROWS: usize = 10;

// Each column aligns its bindings on the '=': the key is right-aligned before
// it, the description left-aligned two cells after it.
const LEFT_EQ: i16 = 72;
const MID_EQ: i16 = 256;
const RIGHT_EQ: i16 = 440;

// App-local palette entries (GEM owns 0..7, the spectrum ramp starts at 16).
pub const GREEN: u8 = 8;
pub const GREEN_DK: u8 = 9;
pub const RED: u8 = 10;

pub fn installPalette(fb: *@import("zigos").LogicalFB) void {
    fb.setPaletteEntry(GREEN, .{ .r = 134, .g = 249, .b = 134, .a = 255 });
    fb.setPaletteEntry(GREEN_DK, .{ .r = 19, .g = 249, .b = 19, .a = 255 });
    fb.setPaletteEntry(RED, .{ .r = 249, .g = 19, .b = 19, .a = 255 });
}

// A binding carries the codepoint its key sends, so a MOUSE CLICK on the row can
// dispatch through exactly the same path as pressing the key — one handler, no
// chance of the two drifting apart.
pub const Binding = struct { key: []const u8, what: []const u8, cp: u32 };

pub const K_F1: u32 = 0xE001; // .. 0xE00A = f10 (mirrored in docs/sealed-loader.js)
pub const K_INSERT: u32 = 0xE00B;
pub const K_DELETE: u32 = 0xE00C;
pub const K_UNDO: u32 = 0xE010;
pub const K_HELP: u32 = 0xE011;
pub const K_ESC: u32 = 0xE012;
pub const K_ALT: u32 = 0xE013;

// The left column selects the replay rate (f1..f8), then the machine's modes.
//
// Monitor and Sample are GONE. Both drove the original's audio INPUT — monitoring
// the incoming signal and recording from the cartridge port — and this machine has
// no input to monitor or sample, so they were two keys that could never do
// anything. Their rows went to the two rates the ladder was missing: 12.5 KHz, and
// 44 KHz at the top, which is the one rate that needs no resampling at all (the
// audio worklet runs at 44100).
pub const LEFT = [ROWS]Binding{
    .{ .key = "f1", .what = "5 KHz", .cp = K_F1 + 0 },
    .{ .key = "f2", .what = "7.5 KHz", .cp = K_F1 + 1 },
    .{ .key = "f3", .what = "10 KHz", .cp = K_F1 + 2 },
    .{ .key = "f4", .what = "12.5 KHz", .cp = K_F1 + 3 },
    .{ .key = "f5", .what = "15 KHz", .cp = K_F1 + 4 },
    .{ .key = "f6", .what = "20 KHz", .cp = K_F1 + 5 },
    .{ .key = "f7", .what = "31 KHz", .cp = K_F1 + 6 },
    .{ .key = "f8", .what = "44 KHz", .cp = K_F1 + 7 },
    .{ .key = "f9", .what = "Magnify", .cp = K_F1 + 8 },
    .{ .key = "f10", .what = "Replay", .cp = K_F1 + 9 },
};
pub const RATE_ROWS: usize = 8; // f1..f8 are the selectable replay rates
pub const RATES = [RATE_ROWS]u32{ 5000, 7500, 10000, 12500, 15000, 20000, 31000, 44100 };

// The middle column is headed EDITOR CONTROLS and starts two rows down.
pub const MID_HEADING = "EDITOR CONTROLS";
pub const MID_ROW0: usize = 2;
pub const MID = [_]Binding{
    .{ .key = "M", .what = "Mark block", .cp = 'M' },
    .{ .key = "C", .what = "Copy block", .cp = 'C' },
    .{ .key = "O", .what = "Overlay block", .cp = 'O' },
    .{ .key = "R", .what = "Reverse sample", .cp = 'R' },
    .{ .key = "<", .what = "Fade in", .cp = '<' },
    .{ .key = ">", .what = "Fade out", .cp = '>' },
    .{ .key = "Insert", .what = "move up", .cp = K_INSERT },
    .{ .key = "Delete", .what = "move down", .cp = K_DELETE },
};

pub const RIGHT = [ROWS]Binding{
    .{ .key = "Q", .what = "Loop mode", .cp = 'Q' },
    .{ .key = "W", .what = "Wipe area", .cp = 'W' },
    .{ .key = "V", .what = "Volume set mode", .cp = 'V' },
    .{ .key = "L", .what = "Load from disc", .cp = 'L' },
    .{ .key = "S", .what = "Save to disc", .cp = 'S' },
    .{ .key = "X", .what = "eXit programme", .cp = 'X' },
    .{ .key = "Alt", .what = "ALTernate O/P", .cp = K_ALT },
    .{ .key = "Esc", .what = "ESCape function", .cp = K_ESC },
    .{ .key = "Undo", .what = "RESET cursors", .cp = K_UNDO },
    .{ .key = "Help", .what = "Extra system data", .cp = K_HELP },
};

pub fn rowY(row: usize) i16 {
    return ROW0 + @as(i16, @intCast(row)) * ROW_H;
}

// The green stippled desktop the panels sit on.
pub fn desktop(g: rom.Gui) void {
    g.rect(.{ .x = 0, .y = 0, .w = SW, .h = SH }, GREEN);
    var y: i16 = 0;
    while (y < SH) : (y += 2) {
        var x: i16 = @rem(y, 4); // offset every other stipple row
        while (x < SW) : (x += 4) g.plot(x, y, GREEN_DK);
    }
}

// A white box with the 2px black border every panel on this screen has.
pub fn panel(g: rom.Gui, r: Rect) void {
    g.rect(r, rom.WHITE);
    g.frame(r, rom.BLACK);
    g.frame(.{ .x = r.x + 1, .y = r.y + 1, .w = r.w - 2, .h = r.h - 2 }, rom.BLACK);
}

// One binding row: key right-aligned onto the '=' column, description after it.
// The clickable extent of a binding row: its key through its description.
pub fn bindingRect(b: Binding, eq: i16, y: i16) Rect {
    const kx = eq - 8 - @as(i16, @intCast(b.key.len)) * 8;
    return .{ .x = kx - 4, .y = y, .w = (eq + 16 - kx) + @as(i16, @intCast(b.what.len)) * 8 + 8, .h = 8 };
}

pub fn binding(g: rom.Gui, b: Binding, eq: i16, y: i16, sel: bool) void {
    const ink: u8 = if (sel) rom.WHITE else rom.BLACK;
    const paper: u8 = if (sel) rom.BLACK else rom.WHITE;
    const r = bindingRect(b, eq, y);
    if (sel) g.rect(r, rom.BLACK);
    g.text(b.key, r.x + 4, y, ink, paper);
    g.text("=", eq, y, ink, paper);
    g.text(b.what, eq + 16, y, ink, paper);
}

pub fn centred(g: rom.Gui, s: []const u8, cx: i16, y: i16) void {
    g.text(s, cx - @as(i16, @intCast(s.len)) * 4, y, rom.BLACK, rom.WHITE);
}

// Right edge at rx, so a number that grows leftwards stays inside the panel.
pub fn rightAligned(g: rom.Gui, s: []const u8, rx: i16, y: i16) void {
    g.text(s, rx - @as(i16, @intCast(s.len)) * 8, y, rom.BLACK, rom.WHITE);
}

pub const COL_EQ = [3]i16{ LEFT_EQ, MID_EQ, RIGHT_EQ };
pub const TITLE_ROW = TITLE_Y;
