// The control channel's transport (docs/FPGA_GLASS.md, "The control channel"): a unix
// stream socket the running glass listens on, and `glass ctl ...`, the client a shell
// line runs. One connection = one command line in, the reply out, then EOF: a script on
// the serial console gets its answer on its own stdout, never mixed into glass's log.
//
// The glass serves from its main loop (main.zig polls the socket beside the input
// devices), so a command runs between two input events, like a key would. A client that
// never sends its line is dropped after CLIENT_MS, so it cannot freeze the OSD.
// The socket is root-only (0600); a `load` names a shelf entry, never a path (app_ctl.zig).
const std = @import("std");
const linux = std.os.linux;

pub const PATH = "/tmp/glass.sock";
pub const LINE_MAX = 256;
pub const REPLY_MAX = 16 << 10; // `list` of a full card fits
pub const CLIENT_MS = 1000; // a client's whole command line must arrive within this
pub const REPLY_MS = 60_000; // a load waits up to 10 s for the boot; the rest is margin

pub const Handler = *const fn (ctx: *anyopaque, line: []const u8, w: *std.Io.Writer) void;

pub const Error = error{ PathTooLong, Socket, NoGlass, Timeout, Io };

fn address(path: []const u8) Error!linux.sockaddr.un {
    var addr = linux.sockaddr.un{ .path = [_]u8{0} ** 108 };
    if (path.len >= addr.path.len) return error.PathTooLong;
    @memcpy(addr.path[0..path.len], path);
    return addr;
}

fn ok(rc: usize) bool {
    return linux.errno(rc) == .SUCCESS;
}

/// The listening socket, non-blocking, for main.zig's poll; a stale socket file from a
/// glass that died is replaced (S99glass restarts glass in a loop).
pub fn listen(path: []const u8) Error!i32 {
    var addr = try address(path);
    const rc = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC, 0);
    if (!ok(rc)) return error.Socket;
    const fd: i32 = @intCast(rc);
    errdefer _ = linux.close(fd);
    const z: [*:0]const u8 = @ptrCast(&addr.path);
    _ = linux.unlink(z);
    if (!ok(linux.bind(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.un)))) return error.Socket;
    _ = linux.chmod(z, 0o600);
    if (!ok(linux.listen(fd, 4))) return error.Socket;
    return fd;
}

/// Every client waiting on `fd`: its line to `handler`, the reply back.
pub fn serve(fd: i32, ctx: *anyopaque, handler: Handler) void {
    while (true) {
        const rc = linux.accept4(fd, null, null, linux.SOCK.CLOEXEC);
        if (!ok(rc)) return; // EAGAIN: nobody else waiting
        const c: i32 = @intCast(rc);
        defer _ = linux.close(c);
        var in: [LINE_MAX]u8 = undefined;
        const n = readLine(c, &in, CLIENT_MS) catch continue;
        var out: [REPLY_MAX]u8 = undefined;
        var w = std.Io.Writer.fixed(&out);
        handler(ctx, in[0..n], &w);
        writeAll(c, w.buffered()) catch {};
    }
}

/// Wait up to `ms` for `fd` to be readable.
fn wait(fd: i32, ms: i32) Error!void {
    var p = [1]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
    const rc = linux.poll(&p, 1, ms);
    if (!ok(rc)) return error.Io;
    if (rc == 0) return error.Timeout;
}

/// Bytes up to the first newline (not kept) or EOF.
fn readLine(fd: i32, buf: []u8, ms: i32) Error!usize {
    var n: usize = 0;
    while (n < buf.len) {
        try wait(fd, ms);
        const rc = linux.read(fd, buf[n..].ptr, buf.len - n);
        if (!ok(rc)) return error.Io;
        if (rc == 0) return n;
        if (std.mem.indexOfScalar(u8, buf[n .. n + rc], '\n')) |at| return n + at;
        n += rc;
    }
    return n;
}

fn writeAll(fd: i32, data: []const u8) Error!void {
    var at: usize = 0;
    while (at < data.len) {
        const rc = linux.write(fd, data[at..].ptr, data.len - at);
        if (!ok(rc) or rc == 0) return error.Io;
        at += rc;
    }
}

/// The client: `line` to the glass listening at `path`, its whole reply into `out`.
pub fn request(path: []const u8, line: []const u8, out: *std.Io.Writer, ms: i32) Error!void {
    var addr = try address(path);
    const rc = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);
    if (!ok(rc)) return error.Socket;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    if (!ok(linux.connect(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.un)))) return error.NoGlass;
    try writeAll(fd, line);
    try writeAll(fd, "\n");
    var buf: [4096]u8 = undefined;
    while (true) {
        try wait(fd, ms);
        const n = linux.read(fd, &buf, buf.len);
        if (!ok(n)) return error.Io;
        if (n == 0) return;
        out.writeAll(buf[0..n]) catch return error.Io;
    }
}

/// `glass ctl WORD...`: exit 0 on an answer, 1 on an `err` answer, 3 if no glass is
/// listening, 4 if it did not answer in REPLY_MS.
pub fn client(words: []const []const u8) u8 {
    var line_buf: [LINE_MAX]u8 = undefined;
    var lw = std.Io.Writer.fixed(&line_buf);
    for (words, 0..) |word, i| lw.print("{s}{s}", .{ if (i == 0) "" else " ", word }) catch return 2;
    var out_buf: [REPLY_MAX]u8 = undefined;
    var out = std.Io.Writer.fixed(&out_buf);
    request(PATH, lw.buffered(), &out, REPLY_MS) catch |err| {
        std.debug.print("glass ctl: {t}{s}\n", .{ err, if (err == error.NoGlass) " (is `glass run` up?)" else "" });
        return if (err == error.NoGlass) 3 else 4;
    };
    const reply = out.buffered();
    writeAll(1, reply) catch {};
    return if (std.mem.startsWith(u8, reply, "err") or std.mem.indexOf(u8, reply, "\nerr") != null) 1 else 0;
}
