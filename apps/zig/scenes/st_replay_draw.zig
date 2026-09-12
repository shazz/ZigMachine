// --------------------------------------------------------------------------
// ST Replay — drawing the screen. st_replay_ui.zig owns the geometry and the
// binding tables; this file composes them into the picture, and st_replay.zig
// keeps the state. The app hands over one View: everything the screen needs and
// nothing it can change.
// --------------------------------------------------------------------------
const std = @import("std");
const rom = @import("rom_sdk");
const ui = @import("st_replay_ui.zig");
const Rect = rom.Rect;

pub const View = struct {
    rate: usize,
    looping: bool,
    monitor: bool,
    marked: bool,
    playing: bool,
    playhead: f32,
    low: u32,
    high: u32,
    bytes: u32,
    free: u32, // machine RAM still available, straight from hwRamFree()
    sample: []const u8,
};

pub fn screen(g: rom.Gui, v: View) void {
    ui.desktop(g);
    panelBox(g, v);
    statusBar(g, v);
    waveBox(g, v);
}

fn panelBox(g: rom.Gui, v: View) void {
    ui.panel(g, ui.PANEL);
    const cx = ui.PANEL.x + @divTrunc(ui.PANEL.w, 2);
    ui.centred(g, "ST Replay / Editor - ZigMachine", cx, ui.TITLE_ROW);
    // The original reports the machine's free memory on the title line. Ours is
    // the real number the hardware hands back, not a constant: a cart's window is
    // shared with the ROM's statics, so it differs per build.
    var mem: [24]u8 = undefined;
    const free = std.fmt.bufPrint(&mem, "{d} BYTES FREE", .{v.free}) catch "";
    ui.rightAligned(g, free, ui.PANEL.x + ui.PANEL.w - 6, ui.TITLE_ROW);

    var row: usize = 0;
    while (row < ui.ROWS) : (row += 1) {
        const y = ui.rowY(row);
        ui.binding(g, ui.LEFT[row], ui.COL_EQ[0], y, row == v.rate);
        ui.binding(g, rightRow(v, row), ui.COL_EQ[2], y, false);
    }
    ui.centred(g, ui.MID_HEADING, ui.COL_EQ[1] + 24, ui.rowY(0));
    for (ui.MID, 0..) |b, i| ui.binding(g, b, ui.COL_EQ[1], ui.rowY(ui.MID_ROW0 + i), false);
}

// The Loop row reports its state in the label, as the original does.
fn rightRow(v: View, row: usize) ui.Binding {
    if (row != 0) return ui.RIGHT[row];
    return .{
        .key = ui.RIGHT[0].key,
        .what = if (v.looping) "Loop mode (ON)" else "Loop mode (OFF)",
        .cp = ui.RIGHT[0].cp,
    };
}

// The status strip: five fields, the 2nd and 4th in inverse video.
fn statusBar(g: rom.Gui, v: View) void {
    ui.panel(g, ui.STATUS);
    var buf: [40]u8 = undefined;
    var x = ui.STATUS.x + 3;
    const y = ui.STATUS.y + 2;
    const cell = @divTrunc(ui.STATUS.w - 6, 5);
    const fields = [5][]const u8{
        std.fmt.bufPrint(buf[0..12], "LOW : {d:>5}", .{v.low}) catch "LOW :",
        if (v.marked) "MARKED" else "UNMARKED",
        std.fmt.bufPrint(buf[12..26], "SIZE: {d:>7}", .{v.bytes}) catch "SIZE:",
        if (v.monitor) "MONITOR" else "INTERNAL",
        std.fmt.bufPrint(buf[26..40], "HIGH: {d:>7}", .{v.high}) catch "HIGH:",
    };
    for (fields, 0..) |f, i| {
        const inv = i % 2 == 1;
        if (inv) g.rect(.{ .x = x, .y = y, .w = cell, .h = 8 }, rom.BLACK);
        g.text(f, x + 2, y, if (inv) rom.WHITE else rom.BLACK, if (inv) rom.BLACK else rom.WHITE);
        x += cell;
    }
}

fn waveBox(g: rom.Gui, v: View) void {
    ui.panel(g, ui.WAVE);
    const c = Rect{ .x = ui.WAVE.x + 2, .y = ui.WAVE.y + 2, .w = ui.WAVE.w - 4, .h = ui.WAVE.h - 4 };
    const half = @divTrunc(c.h, 2) - 1;
    var x: i16 = 0;
    while (x < c.w) : (x += 1) {
        const si: usize = @intCast(@divTrunc(@as(i32, x) * @as(i32, @intCast(v.sample.len)), c.w));
        const s8: i32 = @as(i8, @bitCast(v.sample[si]));
        const amp: i16 = @intCast(@divTrunc(s8 * @as(i32, half), 128));
        if (amp == 0) continue;
        const y0 = @min(ui.WAVE_MID, ui.WAVE_MID - amp);
        g.fill(c.x + x, y0, 1, @intCast(@abs(amp)), rom.BLACK);
    }
    g.fill(c.x, ui.WAVE_MID, @intCast(c.w), 1, ui.RED); // centre line
    if (!v.playing) return;
    const span = @as(f32, @floatFromInt(v.sample.len));
    const hx = c.x + @as(i16, @intFromFloat(v.playhead / span * @as(f32, @floatFromInt(c.w))));
    g.fill(hx, c.y, 1, @intCast(c.h), ui.RED); // playhead
}
