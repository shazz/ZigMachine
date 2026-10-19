// The control channel's parser (ctl.zig), its ZMSTAT line (zmstat.zig) and its socket
// (ctl_sock.zig), on their own; app_ctl_test.zig drives them through the app.
const std = @import("std");
const map = @import("map.zig");
const mc = @import("map_cart.zig");
const ctl = @import("ctl.zig");
const zmstat = @import("zmstat.zig");
const stats = @import("stats.zig");
const snd_info = @import("snd_info.zig");
const ctl_sock = @import("ctl_sock.zig");

test "every command parses, with its defaults" {
    const load = try ctl.parse("load demo-union.zmd\n");
    try std.testing.expectEqualStrings("demo-union.zmd", load.load.file);
    try std.testing.expectEqual(@as(?[]const u8, null), load.load.program);
    try std.testing.expectEqualStrings("SNAKE.PRG", (try ctl.parse("load gem.zmd SNAKE.PRG")).load.program.?);
    try std.testing.expectEqual(ctl.Cmd{ .key = .{ .code = '1', .mode = .tap } }, try ctl.parse("key 1"));
    try std.testing.expectEqual(ctl.Cmd{ .key = .{ .code = map.KEY_ENTER, .mode = .down } }, try ctl.parse("  KEY Enter down "));
    try std.testing.expectEqual(ctl.Cmd{ .key = .{ .code = map.KEY_F1 + 9, .mode = .up } }, try ctl.parse("key f10 up"));
    try std.testing.expectEqual(ctl.Cmd{ .key = .{ .code = 0xE012, .mode = .tap } }, try ctl.parse("key 0xE012"));
    try std.testing.expectEqual(ctl.Cmd{ .key = .{ .code = ' ', .mode = .tap } }, try ctl.parse("key space tap"));
    try std.testing.expectEqual(ctl.Cmd{ .joy = map.JOY_UP | map.JOY_FIRE }, try ctl.parse("joy up+fire"));
    try std.testing.expectEqual(ctl.Cmd{ .joy = 0x20 }, try ctl.parse("joy 0x20"));
    try std.testing.expectEqual(ctl.Cmd{ .joy = 0 }, try ctl.parse("joy 0"));
    try std.testing.expectEqual(ctl.Cmd{ .stats = ctl.DEFAULT_STATS_S }, try ctl.parse("stats"));
    try std.testing.expectEqual(ctl.Cmd{ .stats = 10 }, try ctl.parse("stats 10"));
    try std.testing.expectEqual(ctl.Cmd{ .osd = true }, try ctl.parse("osd open"));
    try std.testing.expectEqual(ctl.Cmd{ .osd = false }, try ctl.parse("osd close"));
    try std.testing.expectEqual(ctl.Cmd.quit_cart, try ctl.parse("quit-cart"));
    try std.testing.expectEqual(ctl.Cmd.list, try ctl.parse("list"));
}

test "a malformed command says which way it is wrong" {
    const E = ctl.Error;
    try std.testing.expectError(E.Empty, ctl.parse("  \n"));
    try std.testing.expectError(E.UnknownCommand, ctl.parse("reboot"));
    try std.testing.expectError(E.MissingArgument, ctl.parse("load"));
    try std.testing.expectError(E.TooManyArguments, ctl.parse("load a.zmd B c"));
    try std.testing.expectError(E.TooManyArguments, ctl.parse("stats 5 6"));
    try std.testing.expectError(E.TooManyArguments, ctl.parse("list all"));
    try std.testing.expectError(E.BadKey, ctl.parse("key f11"));
    try std.testing.expectError(E.BadKey, ctl.parse("key nosuchkey"));
    try std.testing.expectError(E.BadKey, ctl.parse("key 0x0"));
    try std.testing.expectError(E.BadMode, ctl.parse("key a hold"));
    try std.testing.expectError(E.BadJoy, ctl.parse("joy up+jump"));
    try std.testing.expectError(E.BadJoy, ctl.parse("joy 0x100"));
    try std.testing.expectError(E.BadNumber, ctl.parse("stats 0"));
    try std.testing.expectError(E.BadNumber, ctl.parse("stats 51"));
    try std.testing.expectError(E.BadMode, ctl.parse("osd toggle"));
}

fn format(l: *const zmstat.Line) ![]const u8 {
    const S = struct {
        var buf: [512]u8 = undefined;
    };
    var w = std.Io.Writer.fixed(&S.buf);
    try zmstat.write(&w, l);
    return w.buffered();
}

test "the ZMSTAT line: every field key=value, no spaces in a value" {
    var snd = snd_info.Info{ .state = .ok, .version = 1, .route = mc.ROUTE_BARD, .player = mc.PLAYER_SNDH, .started = true, .cycles = 226_800, .samples = 1000, .peak_cycles = 453_600, .peak_samples = 1000 };
    @memcpy(snd.name_buf[0..9], "Wings Of\t");
    snd.name_len = 9;
    const l = zmstat.Line{ .cart = "demo-union.zmd", .state = .running, .rate = .{ .frames = 149, .ms = 5000, .missed = 151 }, .snd = snd, .beat = 1234 };
    try std.testing.expectEqualStrings("ZMSTAT cart=demo-union.zmd fps=29.8 frame_ms=33.5 bard=10/20 player=BARD:SNDH_68k state=running frames=149 secs=5.0 missed=151 beat=1234 trap=- err=- vs_n=- frame_c=- cart_c=- seq_c=- wait_ready=- drain=- painted=- hbl=- plan=- passes=- comp_busy=- dma_busy=- swap=- underrun=- overflow=- probe_c=- cal_mix1=- cal_mix2=- cal_fill1=- cal_fill2=- song=Wings_Of_\n", try format(&l));
}

test "the ZMSTAT line with nothing measured, a ZIGGY player and a failed load" {
    const none = zmstat.Line{};
    try std.testing.expectEqualStrings("ZMSTAT cart=- fps=- frame_ms=- bard=- player=- state=idle frames=- secs=- missed=- beat=0 trap=- err=- vs_n=- frame_c=- cart_c=- seq_c=- wait_ready=- drain=- painted=- hbl=- plan=- passes=- comp_busy=- dma_busy=- swap=- underrun=- overflow=- probe_c=- cal_mix1=- cal_mix2=- cal_fill1=- cal_fill2=- song=-\n", try format(&none));
    const ziggy = snd_info.Info{ .state = .ok, .version = 1, .route = mc.ROUTE_ZIGGY, .player = mc.PLAYER_MOD, .started = true, .cycles = 1, .samples = 1 };
    const l = zmstat.Line{ .cart = "a b.zmd", .state = .silent, .snd = ziggy, .trap = 5, .err = error.CartSilent };
    try std.testing.expectEqualStrings("ZMSTAT cart=a_b.zmd fps=- frame_ms=- bard=- player=ZIGGY:MOD state=silent frames=- secs=- missed=- beat=0 trap=5 err=CartSilent vs_n=- frame_c=- cart_c=- seq_c=- wait_ready=- drain=- painted=- hbl=- plan=- passes=- comp_busy=- dma_busy=- swap=- underrun=- overflow=- probe_c=- cal_mix1=- cal_mix2=- cal_fill1=- cal_fill2=- song=-\n", try format(&l));
}

test "the state tells a hang, a trap and a silent boot apart" {
    var s = stats.Stats{};
    const run = map.CART_RUNNING;
    try std.testing.expectEqual(zmstat.State.idle, zmstat.state(false, 0, 0, &s));
    try std.testing.expectEqual(zmstat.State.running, zmstat.state(true, run, zmstat.STALL_MS - 1, &s));
    try std.testing.expectEqual(zmstat.State.stalled, zmstat.state(true, run, zmstat.STALL_MS, &s));
    try std.testing.expectEqual(zmstat.State.booting, zmstat.state(true, map.CART_BOOTING, 0, &s));
    try std.testing.expectEqual(zmstat.State.trapped, zmstat.state(true, map.CART_TRAPPED, 0, &s));
    try std.testing.expectEqual(zmstat.State.request, zmstat.state(true, mc.CART_REQUEST | 3 << 8, 0, &s));
    s.failed(error.CartSilent);
    try std.testing.expectEqual(zmstat.State.silent, zmstat.state(false, 0, 0, &s));
    s.failed(error.CartTrapped);
    try std.testing.expectEqual(zmstat.State.trapped, zmstat.state(false, 0, 0, &s));
    s.failed(error.FileNotFound);
    try std.testing.expectEqual(zmstat.State.failed, zmstat.state(false, 0, 0, &s));
    s.stop = .quit;
    try std.testing.expectEqual(zmstat.State.quit, zmstat.state(false, 0, 0, &s));
}

fn echo(_: *anyopaque, line: []const u8, w: *std.Io.Writer) void {
    w.print("ok got [{s}]\n", .{line}) catch {};
}

const Client = struct {
    path: []const u8,
    buf: [64]u8 = undefined,
    got: []const u8 = "",
    err: ?ctl_sock.Error = null,

    fn run(c: *Client) void {
        var w = std.Io.Writer.fixed(&c.buf);
        ctl_sock.request(c.path, "stats 5", &w, 5000) catch |e| {
            c.err = e;
        };
        c.got = w.buffered();
    }
};

test "the socket carries a line in and the reply out; no glass is NoGlass" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [96]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, ".zig-cache/tmp/{s}/glass.sock", .{tmp.sub_path});
    var none: [8]u8 = undefined;
    var w = std.Io.Writer.fixed(&none);
    try std.testing.expectError(error.NoGlass, ctl_sock.request(path, "stats", &w, 100));
    const fd = try ctl_sock.listen(path);
    defer _ = std.os.linux.close(fd);
    var c = Client{ .path = path };
    const t = try std.Thread.spawn(.{}, Client.run, .{&c});
    var p = [1]std.os.linux.pollfd{.{ .fd = fd, .events = std.os.linux.POLL.IN, .revents = 0 }};
    _ = std.os.linux.poll(&p, 1, 5000);
    var ctx: u8 = 0;
    ctl_sock.serve(fd, &ctx, echo);
    t.join();
    try std.testing.expectEqual(@as(?ctl_sock.Error, null), c.err);
    try std.testing.expectEqualStrings("ok got [stats 5]\n", c.got);
}
