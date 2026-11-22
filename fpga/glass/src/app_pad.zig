// One evdev pad record, for the App (app.zig): the pad's own state (pads.zig), the OSD menu when
// it is open, else player 1 into REG_JOY and player 2 into the key FIFO (map.zig "player 2").
const std = @import("std");
const map = @import("map.zig");
const pad = @import("pad.zig");
const pads = @import("pads.zig");
const splash = @import("app_splash.zig");
const cart = @import("app_cart.zig");
const App = @import("app.zig").App;

const menu_keys = [_][2]u32{
    .{ map.JOY_UP, map.KEY_ARROW_UP },     .{ map.JOY_DOWN, map.KEY_ARROW_DOWN },
    .{ map.JOY_LEFT, map.KEY_ARROW_LEFT }, .{ map.JOY_RIGHT, map.KEY_ARROW_RIGHT },
    .{ map.JOY_FIRE, map.KEY_ENTER },
};

pub fn event(app: *App, dev: u16, ev_type: u16, code: u16, value: i32, x: pad.Range, y: pad.Range, name: []const u8) void {
    app.pad_name_len = @min(name.len, app.pad_name.len);
    @memcpy(app.pad_name[0..app.pad_name_len], name[0..app.pad_name_len]);
    const i = app.pads.slot(dev) orelse return;
    if (app.pads.firstUnknown(ev_type, code)) {
        std.log.info("pad {s} (event{d}, player {d}): no meaning for type 0x{X} code 0x{X} value {d}", .{ name, dev, i + 1, ev_type, code, value });
    }
    const p = &app.pads.slots[i].pad;
    const before = p.bits;
    p.x = x;
    p.y = y;
    if (!p.update(ev_type, code, value)) return;
    const pressed = p.bits & ~before;
    if (splash.skip(app, null, pressed != 0)) return;
    if (!app.open) return send(app);
    for (menu_keys) |k| if (pressed & k[0] != 0) cart.act(app, app.menu.key(k[1] | map.KEY_DOWN)); // the menu takes down edges as keys
}

/// Tell the cart what changed: player 1 in REG_JOY, player 2 as a KEY_P2_STATE word.
fn send(app: *App) void {
    const now = [2]u32{ app.pads.player(0), app.pads.player(1) };
    if (now[0] != app.pads.sent[0]) app.regs.write(map.REG_JOY, now[0]);
    if (now[1] != app.pads.sent[1]) app.regs.write(map.REG_KEY_PUSH, pads.p2Word(now[1]));
    app.pads.sent = now;
}

/// The OSD opened: let go of both players (the pads' own state stays, so a held stick is sent
/// again by its next event once the menu closes).
pub fn releaseAll(app: *App) void {
    app.regs.write(map.REG_JOY, 0);
    if (app.pads.sent[1] != 0) app.regs.write(map.REG_KEY_PUSH, pads.p2Word(0));
    app.pads.sent = .{ 0, 0 };
}
