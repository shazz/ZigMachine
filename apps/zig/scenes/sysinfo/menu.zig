// --------------------------------------------------------------------------
// SysInfo — the "SysInfo Menu", HWAM's GEM dialog: a framed box over the
// page, its title ruled off, a column of F-key buttons that pick a page and
// the exit buttons, Cancel the default (thick border). It is drawn ONCE when it
// opens; while it is up the app only tests clicks against the buttons' rects,
// and closing it redraws the page underneath.
// --------------------------------------------------------------------------
const rom = @import("rom_sdk");
const Rect = rom.Rect;

pub const Action = enum(u8) { system, video, sound, disk, speed, info, run, quit, cancel };

pub const K_F1: u32 = 0xE001; // docs/sealed-loader.js KEY_CODES
pub const K_UNDO: u32 = 0xE010;
pub const K_HELP: u32 = 0xE011;
pub const K_ESC: u32 = 0xE012;

pub const BOX = Rect{ .x = 104, .y = 28, .w = 432, .h = 144 };
const BH: i16 = 12; // button height
const EXIT_H: i16 = 16; // the exit buttons: Cancel's thick border must clear its label
const ROW_STEP: i16 = 20;
const LEFT_X: i16 = BOX.x + 56;
const RIGHT_X: i16 = BOX.x + 288;
const CLOSER = Rect{ .x = BOX.x + BOX.w - 18, .y = BOX.y + 5, .w = 11, .h = 10 };

const Button = struct { key: []const u8, label: []const u8, r: Rect, act: Action, border: u32 };

fn row(i: i16) i16 {
    return BOX.y + 26 + i * ROW_STEP;
}

const BUTTONS = [_]Button{
    .{ .key = "F1:", .label = "System & Memory", .r = .{ .x = LEFT_X, .y = row(0), .w = 160, .h = BH }, .act = .system, .border = 1 },
    .{ .key = "F2:", .label = "Video", .r = .{ .x = LEFT_X, .y = row(1), .w = 160, .h = BH }, .act = .video, .border = 1 },
    .{ .key = "F3:", .label = "Sound", .r = .{ .x = LEFT_X, .y = row(2), .w = 160, .h = BH }, .act = .sound, .border = 1 },
    .{ .key = "F4:", .label = "Disk & Carts", .r = .{ .x = LEFT_X, .y = row(3), .w = 160, .h = BH }, .act = .disk, .border = 1 },
    .{ .key = "F5:", .label = "Speed Tests", .r = .{ .x = LEFT_X, .y = row(4), .w = 160, .h = BH }, .act = .speed, .border = 1 },
    .{ .key = "HELP:", .label = "Program Info", .r = .{ .x = RIGHT_X, .y = row(0), .w = 128, .h = BH }, .act = .info, .border = 1 },
    .{ .key = "R:", .label = "Run Tests", .r = .{ .x = RIGHT_X, .y = row(1), .w = 128, .h = BH }, .act = .run, .border = 1 },
    .{ .key = "Q:", .label = "Quit", .r = .{ .x = RIGHT_X, .y = row(4) - 2, .w = 56, .h = EXIT_H }, .act = .quit, .border = 1 },
    .{ .key = "", .label = "Cancel", .r = .{ .x = RIGHT_X + 64, .y = row(4) - 2, .w = 64, .h = EXIT_H }, .act = .cancel, .border = 3 },
};

pub fn draw(g: rom.Gui) void {
    g.box(BOX, 1);
    g.frame(.{ .x = BOX.x + 3, .y = BOX.y + 3, .w = BOX.w - 6, .h = BOX.h - 6 }, rom.BLACK);
    g.text("SysInfo Menu", BOX.x + 16, BOX.y + 7, rom.BLACK, rom.WHITE);
    g.fill(BOX.x + 8, BOX.y + 18, BOX.w - 16, 1, rom.BLACK);
    g.frame(CLOSER, rom.BLACK);
    for (BUTTONS) |b| {
        const kx = b.r.x - 8 - @as(i16, @intCast(b.key.len)) * rom.CELL;
        if (b.key.len > 0) g.text(b.key, kx, b.r.y + @divTrunc(b.r.h - 8, 2), rom.BLACK, rom.WHITE);
        _ = g.button(b.r, b.label, false, b.border);
    }
}

/// The button a press started on this frame, shown pressed (inverse) as GEM
/// does; the closer box is Cancel.
pub fn click(g: rom.Gui) ?Action {
    if (!g.edge()) return null;
    if (g.hit(CLOSER)) return .cancel;
    for (BUTTONS) |b| {
        if (!g.hit(b.r)) continue;
        _ = g.button(b.r, b.label, true, b.border);
        return b.act;
    }
    return null;
}

/// The keys the menu's labels name; Esc, Undo, Space and Return cancel.
pub fn key(cp: u32) ?Action {
    if (cp >= K_F1 and cp < K_F1 + 5) return @enumFromInt(cp - K_F1);
    return switch (cp) {
        K_HELP => .info,
        'r', 'R' => .run,
        'q', 'Q' => .quit,
        K_ESC, K_UNDO, ' ', 13 => .cancel,
        else => null,
    };
}
