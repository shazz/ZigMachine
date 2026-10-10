// The console page: the machine itself rather than a cart.
//
//   row 0       title bar
//   rows 2..7   Cold reset, Warm reset, Volume, Mute, Debug, Back
//   row 9       a rule
//   rows 10..13 what the selected item does
//   row 15      status
//
// Up/Down select, Enter (or a pad's fire) acts, Left/Right change the volume
// or the mute, Esc or Backspace go back to the shelf. Back is an item too, for
// a pad, which has no Esc.
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");
const text = @import("text.zig");
const config = @import("config.zig");

pub const Item = enum { cold, warm, volume, mute, debug, back };
const ITEMS = std.enums.values(Item);
pub const FIRST = 2;
const RULE = 9;
const HELP = 10;
pub const VOL_STEP = 16;

pub const Key = enum { none, back, cold, warm, settings, debug };

const help = [_][]const u8{
    "Reload the cart from the SD card, clear all its memory and boot it: a power cycle. (R on the shelf)",
    "Restart the cart CPU and keep its memory: the ST's reset button. (W on the shelf)",
    "Master volume. Left/Right change it; saved to glass.cfg when you leave this page.",
    "Silence the console. Enter or Left/Right toggle it; saved with the volume.",
    "Versions, live stats of the running cart, and the board.",
    "Back to the shelf.",
};

pub const State = struct {
    cursor: usize = 0,

    pub fn key(self: *State, code: u32, s: *config.Settings) Key {
        const item = ITEMS[self.cursor];
        switch (code) {
            map.KEY_ARROW_UP => self.cursor -|= 1,
            map.KEY_ARROW_DOWN => self.cursor = @min(self.cursor + 1, ITEMS.len - 1),
            map.KEY_ESCAPE, map.KEY_BACKSPACE => return .back,
            map.KEY_ARROW_LEFT, map.KEY_ARROW_RIGHT => return adjust(item, code == map.KEY_ARROW_RIGHT, s),
            map.KEY_ENTER, ' ' => return switch (item) {
                .cold => .cold,
                .warm => .warm,
                .volume => .none,
                .mute => adjust(.mute, true, s),
                .debug => .debug,
                .back => .back,
            },
            else => {},
        }
        return .none;
    }

    pub fn draw(self: *const State, o: *osd.Osd, s: config.Settings) void {
        o.line(0, " ZIGMACHINE  CONSOLE       < Esc", true);
        var buf: [osd.COLS]u8 = undefined;
        var cells: [16]u8 = undefined;
        for (ITEMS, 0..) |item, i| {
            const row: u32 = FIRST + @as(u32, @intCast(i));
            const t = switch (item) {
                .cold => " Cold reset",
                .warm => " Warm reset",
                .volume => std.fmt.bufPrint(&buf, " Volume  {s} {d:>3}%", .{ text.bar(&cells, s.volume, 255, 16), percent(s.volume) }) catch "",
                .mute => if (s.mute) " Mute    on" else " Mute    off",
                .debug => " Debug...",
                .back => " Back",
            };
            o.line(row, t, i == self.cursor);
        }
        o.line(RULE, "-" ** osd.COLS, false);
        var rows: [4][]const u8 = undefined;
        var last: [osd.COLS]u8 = undefined;
        const n = text.wrap(help[self.cursor], osd.COLS, &rows, &last);
        for (rows[0..n], 0..) |r, k| o.line(HELP + @as(u32, @intCast(k)), r, false);
    }
};

fn percent(v: u8) u32 {
    return (@as(u32, v) * 100 + 127) / 255;
}

fn adjust(item: Item, up: bool, s: *config.Settings) Key {
    switch (item) {
        .volume => {
            const before = s.volume;
            s.volume = if (up) s.volume +| VOL_STEP else s.volume -| VOL_STEP;
            return if (s.volume == before) .none else .settings;
        },
        .mute => {
            s.mute = !s.mute;
            return .settings;
        },
        else => return .none,
    }
}
