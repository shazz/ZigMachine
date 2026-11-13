// The Wi-Fi job's thread (wifi_job.zig): one job at a time, started from the menu, finished
// off glass's loop, picked up by app_wifi.tick a tick later. The main thread never waits on it:
// start() refuses while a job runs, poll() only looks at a flag. And the board's runner: each
// command spawned from its argv (std.process.run: no shell), its stdout kept, bounded in time.
const std = @import("std");
const job = @import("wifi_job.zig");
const cmd = @import("wifi_cmd.zig");

pub const SCRATCH = 64 * 1024; // `iw scan` of a busy street: ~1-2 KB an access point

pub const Worker = struct {
    env: job.Env,
    req: job.Request = .{ .kind = .status },
    res: job.Result = .{},
    scratch: [SCRATCH]u8 = undefined,
    thread: ?std.Thread = null,
    done: std.atomic.Value(bool) = .init(false),

    /// Run `req` on the thread; error.Busy while the last job runs. `req.pass` is zeroed either way.
    pub fn start(self: *Worker, req: *job.Request) error{ Busy, NoThread }!void {
        defer std.crypto.secureZero(u8, &req.pass);
        if (self.thread != null) return error.Busy;
        self.req = req.*;
        self.done.store(false, .release);
        self.thread = std.Thread.spawn(.{}, body, .{self}) catch {
            std.crypto.secureZero(u8, &self.req.pass);
            return error.NoThread;
        };
    }

    fn body(self: *Worker) void {
        job.perform(&self.env, &self.req, &self.res, &self.scratch);
        self.done.store(true, .release);
    }

    pub fn busy(self: *const Worker) bool {
        return self.thread != null;
    }

    /// The finished job's result (valid until the next start), or null while it runs or none ran.
    pub fn poll(self: *Worker) ?*job.Result {
        const t = self.thread orelse return null;
        if (!self.done.load(.acquire)) return null;
        t.join();
        self.thread = null;
        return &self.res;
    }

    /// Waits for a running job (glass exiting, a test's end).
    pub fn deinit(self: *Worker) void {
        if (self.thread) |t| t.join();
        self.thread = null;
    }
};

/// The board's runner: `ctx` is a *Spawn.
pub const Spawn = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    path_env: []const u8 = cmd.DEFAULT_PATH,
    timeout_s: u32 = 40, // above the slowest bounded command (udhcpc: 5 tries x 2 s, a scan ~4 s)

    pub fn runner(self: *Spawn) job.Runner {
        return .{ .ctx = self, .run = run };
    }

    fn run(ctx: ?*anyopaque, argv: []const []const u8, ram: bool, out: []u8) job.Ran {
        const self: *Spawn = @ptrCast(@alignCast(ctx.?));
        var env = std.process.Environ.Map.init(self.gpa);
        defer env.deinit();
        env.put("PATH", self.path_env) catch return .{ .ok = false, .out = "" };
        if (ram) env.put("LD_LIBRARY_PATH", cmd.RAM_DIR) catch return .{ .ok = false, .out = "" };
        const r = std.process.run(self.gpa, self.io, .{
            .argv = argv,
            .environ_map = &env,
            .stdout_limit = .unlimited, // a crowded scan past SCRATCH is cut below, not refused (StreamTooLong)
            .stderr_limit = .unlimited,
            .timeout = .{ .duration = .{ .raw = .fromSeconds(self.timeout_s), .clock = .awake } },
        }) catch |err| {
            std.log.warn("wifi: {s}: {t}", .{ std.fs.path.basename(argv[0]), err });
            return .{ .ok = false, .out = "" };
        };
        defer self.gpa.free(r.stdout);
        defer self.gpa.free(r.stderr);
        const n = @min(out.len, r.stdout.len);
        @memcpy(out[0..n], r.stdout[0..n]);
        const ok = r.term == .exited and r.term.exited == 0;
        if (!ok) std.log.info("wifi: {s} {s}: {s}", .{ std.fs.path.basename(argv[0]), if (argv.len > 1) argv[1] else "", std.mem.trimEnd(u8, r.stderr[0..@min(r.stderr.len, 120)], "\n") });
        return .{ .ok = ok, .out = out[0..n] };
    }
};

/// The board's nap: the worker's thread only.
pub fn napMs(ms: u32) void {
    const ts = std.os.linux.timespec{ .sec = @intCast(ms / 1000), .nsec = @intCast((ms % 1000) * std.time.ns_per_ms) };
    _ = std.os.linux.nanosleep(&ts, null);
}
