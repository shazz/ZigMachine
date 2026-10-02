// USB keyboards and pads through Linux evdev (/dev/input/event*). Linux owns
// USB HID, so a keyboard is a stream of (type, code, value) records here and
// nothing more: keymap.zig and pad.zig give them meaning.
//
// Devices come and go (a pad plugged in after boot), so the set is rescanned
// every few seconds; a device that fails to read is dropped and found again.
const std = @import("std");
const linux = std.os.linux;
const pad = @import("pad.zig");

pub const MAX_DEVICES = 8;
const SCAN = 16; // /dev/input/event0..15

// The kernel writes `struct input_event` with the CALLER's long for the time
// fields: 16 bytes for a 32-bit ARM process, 24 on a 64-bit desktop.
pub const EVENT_BYTES = 2 * @sizeOf(c_ulong) + 8;

pub const Raw = struct { dev: u8, type: u16, code: u16, value: i32 };

pub fn decode(dev: u8, rec: *const [EVENT_BYTES]u8) Raw {
    const t = 2 * @sizeOf(c_ulong);
    return .{
        .dev = dev,
        .type = std.mem.readInt(u16, rec[t..][0..2], .little),
        .code = std.mem.readInt(u16, rec[t + 2 ..][0..2], .little),
        .value = std.mem.readInt(i32, rec[t + 4 ..][0..4], .little),
    };
}

pub const Device = struct { fd: i32, num: u8, x: pad.Range, y: pad.Range, dead: bool = false };

pub const Inputs = struct {
    devs: [MAX_DEVICES]Device = undefined,
    n: usize = 0,

    /// Drop unplugged devices, open new ones; devices still there stay open,
    /// so no key held across a rescan loses its release.
    pub fn rescan(self: *Inputs) void {
        var kept: usize = 0;
        for (self.devs[0..self.n]) |d| {
            if (d.dead) _ = linux.close(d.fd) else {
                self.devs[kept] = d;
                kept += 1;
            }
        }
        self.n = kept;
        var path_buf: [32]u8 = undefined;
        for (0..SCAN) |i| {
            if (self.n == MAX_DEVICES) break;
            if (self.has(@intCast(i))) continue;
            const path = std.fmt.bufPrintZ(&path_buf, "/dev/input/event{d}", .{i}) catch continue;
            const rc = linux.open(path, .{ .ACCMODE = .RDONLY, .NONBLOCK = true, .CLOEXEC = true }, 0);
            if (linux.errno(rc) != .SUCCESS) continue;
            const fd: i32 = @intCast(rc);
            self.devs[self.n] = .{ .fd = fd, .num = @intCast(i), .x = absRange(fd, pad.ABS_X), .y = absRange(fd, pad.ABS_Y) };
            self.n += 1;
        }
    }

    fn has(self: *const Inputs, num: u8) bool {
        for (self.devs[0..self.n]) |d| if (d.num == num) return true;
        return false;
    }

    pub fn closeAll(self: *Inputs) void {
        for (self.devs[0..self.n]) |d| _ = linux.close(d.fd);
        self.n = 0;
    }

    /// Wait up to `timeout_ms` for input, then read what is there into `out`.
    pub fn poll(self: *Inputs, timeout_ms: i32, out: []Raw) usize {
        var fds: [MAX_DEVICES]linux.pollfd = undefined;
        for (self.devs[0..self.n], 0..) |d, i| fds[i] = .{ .fd = d.fd, .events = linux.POLL.IN, .revents = 0 };
        _ = linux.poll(&fds, self.n, timeout_ms);
        var got: usize = 0;
        for (fds[0..self.n], 0..) |f, i| {
            if (f.revents == 0) continue;
            got += self.drain(@intCast(i), out[got..]);
        }
        return got;
    }

    fn drain(self: *Inputs, dev: u8, out: []Raw) usize {
        var got: usize = 0;
        var rec: [EVENT_BYTES]u8 = undefined;
        while (got < out.len) {
            const rc = linux.read(self.devs[dev].fd, &rec, EVENT_BYTES);
            const err = linux.errno(rc);
            if (err == .AGAIN) break; // drained
            if (err != .SUCCESS or rc != EVENT_BYTES) { // ENODEV: unplugged
                self.devs[dev].dead = true;
                break;
            }
            out[got] = decode(dev, &rec);
            got += 1;
        }
        return got;
    }
};

// EVIOCGABS(axis) = _IOR('E', 0x40 + axis, struct input_absinfo): six s32.
fn absRange(fd: i32, axis: u32) pad.Range {
    var info = [_]i32{0} ** 6; // value, minimum, maximum, fuzz, flat, resolution
    const req: u32 = (2 << 30) | (@sizeOf(@TypeOf(info)) << 16) | ('E' << 8) | (0x40 + axis);
    if (linux.errno(linux.ioctl(fd, req, @intFromPtr(&info))) != .SUCCESS or info[2] <= info[1]) return .{};
    return .{ .min = info[1], .max = info[2] };
}

test "an input_event record decodes at this ABI's offsets" {
    var rec = [_]u8{0xEE} ** EVENT_BYTES;
    const t = 2 * @sizeOf(c_ulong);
    std.mem.writeInt(u16, rec[t..][0..2], 1, .little); // EV_KEY
    std.mem.writeInt(u16, rec[t + 2 ..][0..2], 88, .little); // KEY_F12
    std.mem.writeInt(i32, rec[t + 4 ..][0..4], 2, .little); // repeat
    const r = decode(3, &rec);
    try std.testing.expectEqual(Raw{ .dev = 3, .type = 1, .code = 88, .value = 2 }, r);
}
