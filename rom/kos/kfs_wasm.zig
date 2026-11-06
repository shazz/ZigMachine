// --------------------------------------------------------------------------
// docs/kos-cfs.wasm: KFS (kfs.zig), C:'s writer where C: is an image, as one small wasm module with
// memory of its own. The page (docs/kos-cfile.js, sealed-loader.js) and node's harnesses instantiate
// it; the native host links the same module through wasm2c (fpga/host/kos_cfile.c). The host keeps
// the image: KFS asks it for sectors (env.kfsRead / env.kfsWrite, 512 bytes at an offset in this
// module's memory). The host copies a cart's request into kfsBuf() (path, path2, data) and calls
// kfsServe; the answer is a TOS code, kfsGen() the C: generation.
// --------------------------------------------------------------------------
const kfs = @import("kfs.zig");
const abi = @import("kfs_abi.zig");
const fat = @import("fat.zig");

extern "env" fn kfsRead(sector: u32, dst: u32) u32; // 1 read, 0 no such sector
extern "env" fn kfsWrite(sector: u32, src: u32) u32; // 1 written, 0 refused

const PATHS = 2 * 128;
var buf: [PATHS + abi.DATA_MAX]u8 align(4) = undefined;
var server: kfs.Server = .{};
var dummy: u8 = 0;

fn rd(_: *anyopaque, n: u32, dst: *[fat.SECTOR]u8) bool {
    return kfsRead(n, @intCast(@intFromPtr(dst))) == 1;
}

fn wr(_: *anyopaque, n: u32, src: *const [fat.SECTOR]u8) bool {
    return kfsWrite(n, @intCast(@intFromPtr(src))) == 1;
}

/// Where the host copies a request: path at +0 (128 bytes), path2 at +128, data at +256 (32 KB).
export fn kfsBuf() u32 {
    return @intCast(@intFromPtr(&buf));
}

export fn kfsGen() u32 {
    return server.gen;
}

/// The DOS time and date words stamped on what the next requests write (the page passes its clock;
/// the harnesses keep the default, 1 Jan 2026, so their images hash alike).
export fn kfsStamp(time: u32, date: u32) void {
    server.stamp = .{ @truncate(time), @truncate(date) };
}

/// A request whose lengths the host already bounded (path_len, path2_len <= 127, len <= 32 KB).
export fn kfsServe(op: u32, flags: u32, slot: u32, attr: u32, offset: u32, path_len: u32, path2_len: u32, len: u32) i32 {
    if (path_len > 127 or path2_len > 127 or len > abi.DATA_MAX) return -64; // ERANGE
    const r = kfs.Request{
        .op = @enumFromInt(op),
        .flags = flags,
        .slot = slot,
        .attr = attr,
        .offset = offset,
        .path = buf[0..path_len],
        .path2 = buf[128..][0..path2_len],
        .data = buf[PATHS..][0..len],
    };
    return server.serve(.{ .ctx = &dummy, .read_fn = rd, .write_fn = wr }, &r);
}
