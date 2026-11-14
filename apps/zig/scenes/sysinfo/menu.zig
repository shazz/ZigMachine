// --------------------------------------------------------------------------
// SysInfo — the "SysInfo Menu", HWAM's GEM dialog: a framed box over the
// page, its title ruled off, a column of F-key buttons that pick a page and
// the exit buttons, Cancel the default (thick border). It is drawn ONCE when it
// opens; while it is up the app only tests clicks against the buttons' rects,
// and closing it redraws the page underneath. Its geometry follows the screen
// mode: centred on the desk, narrower in low res (320 pixels).
// --------------------------------------------------------------------------
const rom = @import("rom_sdk");
const Rect = rom.Rect;
const view = @import("view.zig");

pub const Action = enum(u8) { system, video, sound, disk, speed, info, run, rez, quit, cancel };

pub const K_F1: u32 = 0xE001; // docs/sealed-loader.js KEY_CODES
pub const K_F6: u32 = 0xE006;
pub const K_UNDO: u32 = 0xE010;
pub const K_HELP: u32 = 0xE011;
pub const K_ESC: u32 = 0xE012;

const BH: i16 = 12; // button height
const EXIT_H: i16 = 16; // the exit buttons: Cancel's thick border must clear its label
const ROW_STEP: i16 = 20;
const BOX_H: i16 = 144;

const Button = struct { key: []const u8, label: []const u8, r: Rect, act: Action, border: u32 };

/// The box and its two columns in mode `m`: x of each column and its buttons' width.
const Geo = struct { box: Rect, lx: i16, lw: i16, rx: i16, rw: i16, quit_w: i16, cancel_w: i16 };

fn geo(m: view.Mode) Geo {
    if (m == .low) {
        const b = Rect{ .x = 4, .y = 28, .w = 312, .h = BOX_H };
        return .{ .box = b, .lx = b.x + 32, .lw = 120, .rx = b.x + 204, .rw = 100, .quit_w = 40, .cancel_w = 56 };
    }
    const y: i16 = if (m == .desk) @divTrunc(view.height(m) - BOX_H, 2) else 28;
    const b = Rect{ .x = 104, .y = y, .w = 432, .h = BOX_H };
    return .{ .box = b, .lx = b.x + 56, .lw = 160, .rx = b.x + 288, .rw = 128, .quit_w = 56, .cancel_w = 64 };
}

pub fn box(m: view.Mode) Rect {
    return geo(m).box;
}

fn row(b: Rect, i: i16) i16 {
    return b.y + 26 + i * ROW_STEP;
}

fn closer(b: Rect) Rect {
    return .{ .x = b.x + b.w - 18, .y = b.y + 5, .w = 11, .h = 10 };
}

fn buttons(m: view.Mode) [10]Button {
    const g = geo(m);
    const b = g.box;
    const L = struct {
        fn at(x: i16, y: i16, w: i16) Rect {
            return .{ .x = x, .y = y, .w = w, .h = BH };
        }
    };
    return .{
        .{ .key = "F1:", .label = "System & Memory", .r = L.at(g.lx, row(b, 0), g.lw), .act = .system, .border = 1 },
        .{ .key = "F2:", .label = "Video", .r = L.at(g.lx, row(b, 1), g.lw), .act = .video, .border = 1 },
        .{ .key = "F3:", .label = "Sound", .r = L.at(g.lx, row(b, 2), g.lw), .act = .sound, .border = 1 },
        .{ .key = "F4:", .label = "Disk & Carts", .r = L.at(g.lx, row(b, 3), g.lw), .act = .disk, .border = 1 },
        .{ .key = "F5:", .label = "Speed Tests", .r = L.at(g.lx, row(b, 4), g.lw), .act = .speed, .border = 1 },
        .{ .key = "HELP:", .label = "Program Info", .r = L.at(g.rx, row(b, 0), g.rw), .act = .info, .border = 1 },
        .{ .key = "R:", .label = "Run Tests", .r = L.at(g.rx, row(b, 1), g.rw), .act = .run, .border = 1 },
        .{ .key = "F6:", .label = "Resolution", .r = L.at(g.rx, row(b, 2), g.rw), .act = .rez, .border = 1 },
        .{ .key = "Q:", .label = "Quit", .r = .{ .x = g.rx, .y = row(b, 4) - 2, .w = g.quit_w, .h = EXIT_H }, .act = .quit, .border = 1 },
        .{ .key = "", .label = "Cancel", .r = .{ .x = g.rx + g.quit_w + 8, .y = row(b, 4) - 2, .w = g.cancel_w, .h = EXIT_H }, .act = .cancel, .border = 3 },
    };
}

pub fn draw(g: rom.Gui, m: view.Mode) void {
    const b = box(m);
    g.box(b, 1);
    g.frame(.{ .x = b.x + 3, .y = b.y + 3, .w = b.w - 6, .h = b.h - 6 }, rom.BLACK);
    g.text("SysInfo Menu", b.x + 16, b.y + 7, rom.BLACK, rom.WHITE);
    g.fill(b.x + 8, b.y + 18, @intCast(b.w - 16), 1, rom.BLACK);
    g.frame(closer(b), rom.BLACK);
    for (buttons(m)) |bt| {
        const kx = bt.r.x - 8 - @as(i16, @intCast(bt.key.len)) * rom.CELL;
        if (bt.key.len > 0) g.text(bt.key, kx, bt.r.y + @divTrunc(bt.r.h - 8, 2), rom.BLACK, rom.WHITE);
        _ = g.button(bt.r, bt.label, false, bt.border);
    }
}

/// The button a press started on this frame, shown pressed (inverse) as GEM
/// does; the closer box is Cancel.
pub fn click(g: rom.Gui, m: view.Mode) ?Action {
    if (!g.edge()) return null;
    if (g.hit(closer(box(m)))) return .cancel;
    for (buttons(m)) |bt| {
        if (!g.hit(bt.r)) continue;
        _ = g.button(bt.r, bt.label, true, bt.border);
        return bt.act;
    }
    return null;
}

/// The keys the menu's labels name; Esc, Undo, Space and Return cancel.
pub fn key(cp: u32) ?Action {
    if (cp >= K_F1 and cp < K_F1 + 5) return @enumFromInt(cp - K_F1);
    return switch (cp) {
        K_HELP => .info,
        K_F6 => .rez,
        'r', 'R' => .run,
        'q', 'Q' => .quit,
        K_ESC, K_UNDO, ' ', 13 => .cancel,
        else => null,
    };
}
