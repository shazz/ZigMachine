// The debug page: read-only, redrawn a few times a second while it is open
// (App.tick). Every number comes from somewhere a bug report can name: the
// glass's registers, the glass program's own counters, or Linux.
//
//   row 0   title bar
//   row 1   glass  the ARM program's version and git hash (baked in at build)
//   row 2   PL     the register block's ID and VERSION
//   row 3   fw     the cart CPU firmware's version (CART_STATE 31:8 at boot)
//   row 4   cart   CART_STATE, and CART_BEAT = frames run
//   row 5   fps    measured from the beat; the last trap code
//   row 6   loads  how many, and how long the last took
//   row 7   up     the glass program's uptime
//   row 8   ddr    the cart window and the image's size (LOAD_BASE, LOAD_SIZE)
//   row 9   cpu    the Zynq's die temperature (XADC)
//   row 10  mem    Linux's available / total memory
//   row 11  pad    the last joypad that sent an event (its evdev name)
//   row 12  input  evdev nodes open
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");
const text = @import("text.zig");
const board_info = @import("board_info.zig");

pub const View = struct {
    glass_version: []const u8 = "?",
    git: []const u8 = "?",
    pl_id: u32 = 0,
    pl_version: u32 = 0,
    fw: ?u32 = null,
    cart_state: u32 = 0,
    beat: u32 = 0,
    fps_x10: ?u32 = null,
    last_trap: ?u32 = null,
    loads: u32 = 0,
    last_load_ms: i64 = 0,
    uptime_s: i64 = 0,
    load_base: u32 = 0,
    load_size: u32 = 0,
    board: board_info.Info = .{},
    pad: []const u8 = "",
    inputs: usize = 0,
};

const state_names = [_][]const u8{ "RESET", "BOOTING", "RUNNING", "TRAPPED" };

pub fn draw(o: *osd.Osd, v: *const View) void {
    o.line(0, " ZIGMACHINE  DEBUG     live  Esc", true);
    var b: [14][osd.COLS]u8 = undefined;
    var cut: [osd.COLS]u8 = undefined;
    var ver: [3][12]u8 = undefined;
    const st = v.cart_state & map.CART_STATE_MASK;
    const up: u64 = @intCast(@max(0, v.uptime_s)); // unsigned: a signed {d:0>2} prints "+2"
    const pl_name = if (v.pl_id == map.ID_VALUE) "ZMGL" else "ID?";
    const lines = [_][]const u8{
        p(&b[0], "glass {s} {s}", .{ v.glass_version, v.git }),
        p(&b[1], "PL    {s} {s}", .{ pl_name, semver(&ver[0], v.pl_version) }),
        p(&b[2], "fw    {s}", .{if (v.fw) |f| semver(&ver[1], f) else "-"}),
        p(&b[3], "cart  {s:<8} beat {d}", .{ if (st < 4) state_names[st] else "?", v.beat }),
        p(&b[4], "fps   {s:<8} trap {s}", .{ tenths(&ver[2], v.fps_x10), opt(&cut, v.last_trap) }),
        p(&b[5], "loads {d}  last {d} ms", .{ v.loads, v.last_load_ms }),
        p(&b[6], "up    {d}:{d:0>2}:{d:0>2}", .{ up / 3600, up / 60 % 60, up % 60 }),
        p(&b[7], "ddr   {X:0>8}+{d}M img {d}K", .{ v.load_base, map.DDR_CART_BYTES >> 20, v.load_size >> 10 }),
        temp(&b[8], v.board.temp_mc),
        mem(&b[9], v.board),
        p(&b[10], "pad   {s}", .{if (v.pad.len > 0) v.pad else "none seen"}),
        p(&b[11], "input {d} evdev nodes", .{v.inputs}),
    };
    for (lines, 0..) |l, i| o.line(@intCast(1 + i), l, false);
}

fn p(buf: *[osd.COLS]u8, comptime fmt: []const u8, args: anytype) []const u8 {
    var w = std.Io.Writer.fixed(buf);
    w.print(fmt, args) catch {}; // a long line is clipped at 32 columns
    return w.buffered();
}

fn semver(buf: *[12]u8, v: u32) []const u8 {
    return std.fmt.bufPrint(buf, "{d}.{d}.{d}", .{ v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF }) catch "?";
}

fn tenths(buf: *[12]u8, v: ?u32) []const u8 {
    const x = v orelse return "-";
    return std.fmt.bufPrint(buf, "{d}.{d}", .{ x / 10, x % 10 }) catch "?";
}

fn opt(buf: *[osd.COLS]u8, v: ?u32) []const u8 {
    return std.fmt.bufPrint(buf, "{d}", .{v orelse return "-"}) catch "?";
}

fn temp(buf: *[osd.COLS]u8, mc: ?i64) []const u8 {
    const t = mc orelse return "cpu   n/a (no XADC)";
    return p(buf, "cpu   {d}.{d} C", .{ @divTrunc(t, 1000), @divTrunc(@mod(t, 1000), 100) });
}

fn mem(buf: *[osd.COLS]u8, i: board_info.Info) []const u8 {
    const total = i.mem_total_kb orelse return "mem   n/a";
    const avail = i.mem_avail_kb orelse 0;
    return p(buf, "mem   {d}/{d} MB free", .{ avail >> 10, total >> 10 });
}

test "the debug page shows what it is given, and n/a for what Linux lacks" {
    var o = osd.Osd{};
    const v = View{ .glass_version = "0.2.0", .git = "1a2b3c4d", .pl_id = map.ID_VALUE, .pl_version = map.VERSION, .fw = 0x000100, .cart_state = map.CART_RUNNING, .beat = 1234, .fps_x10 = 499, .loads = 2, .last_load_ms = 412, .uptime_s = 3723, .load_base = map.DDR_CART_BASE, .load_size = 420 << 10, .pad = "Xbox Wireless Controller", .inputs = 3 };
    draw(&o, &v);
    var dump: [osd.ROWS * (osd.COLS + 1)]u8 = undefined;
    o.dump(&dump);
    for ([_][]const u8{ "glass 0.2.0 1a2b3c4d", "PL    ZMGL 1.3.0", "fw    0.1.0", "cart  RUNNING  beat 1234", "fps   49.9     trap -", "up    1:02:03", "ddr   1E000000+32M img 420K", "cpu   n/a", "mem   n/a", "pad   Xbox Wireless Controller" }) |want| {
        if (std.mem.indexOf(u8, &dump, want) == null) {
            std.debug.print("missing \"{s}\" in:\n{s}", .{ want, dump });
            return error.TestExpectedEqual;
        }
    }
}
