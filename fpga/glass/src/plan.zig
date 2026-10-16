// What a load writes into the cart window, worked out before anything is touched (steps 2
// and 3 of loader.zig): a monolithic board image at 0, or the system image at 0 and a lean
// cart at map_cart.CART_IMG_AT (system.zig, decisions.md 2026-10-15); the shelf disk on the
// first DISK_ALIGN boundary after the image (after a lean cart's .bss), its descriptor near
// the top (map.zig, "the disk in the cart window"). Everything else is zero.
const std = @import("std");
const zx0 = @import("zx0");
const map = @import("map.zig");
const mc = @import("map_cart.zig");
const bus = @import("bus.zig");
const zmd = @import("zmd.zig");
const system = @import("system.zig");

pub const Error = zmd.Error || system.Error || error{
    BadImage, // the board image is a ZX0 container that does not depack
    TooBig, // larger than the cart CPU's window
    DiskTooBig, // the shelf disk does not fit between the image and the pictures (map.DISK_END)
    OutOfMemory,
};

/// Unpack the board image into a fresh buffer (a raw image is copied as is).
pub fn unpack(gpa: std.mem.Allocator, image: []const u8, window: usize) Error![]u8 {
    if (!zx0.isPacked(image)) {
        if (image.len > window) return error.TooBig;
        return gpa.dupe(u8, image);
    }
    const n = zx0.depackedLen(image) orelse return error.BadImage;
    if (n > window) return error.TooBig;
    const out = try gpa.alloc(u8, n);
    errdefer gpa.free(out);
    const got = zx0.depack(image, out) orelse return error.BadImage;
    if (got != n) return error.BadImage;
    return out;
}

pub const Plan = struct {
    sys: []const u8 = &.{}, // the system image (borrowed from the System), lean carts only
    image: []u8,
    image_at: u32 = 0,
    disk: []u8,
    disk_at: u32,
    desc: [map.DISK_DESC_WORDS * 4]u8,
    desc_at: u32,
    packed_bytes: u32,

    pub fn parts(self: *const Plan) [4]bus.Part {
        return .{
            .{ .at = 0, .bytes = self.sys },
            .{ .at = self.image_at, .bytes = self.image },
            .{ .at = self.disk_at, .bytes = self.disk },
            .{ .at = self.desc_at, .bytes = &self.desc },
        };
    }

    /// The window offset the image's bytes end at (LOAD_SIZE).
    pub fn imageEnd(self: *const Plan) u32 {
        return self.image_at + @as(u32, @intCast(self.image.len));
    }

    pub fn deinit(self: *Plan, gpa: std.mem.Allocator) void {
        gpa.free(self.image);
        gpa.free(self.disk);
    }
};

/// The plan of `disk`, the descriptor saying `magic` (map.DISK_MAGIC, or map_cart.zig's
/// DISK_MAGIC_PROGRAM for a program launched off the disk); `sys` for a lean cart.
pub fn planAs(gpa: std.mem.Allocator, disk: []const u8, window: usize, magic: u32, sys: ?system.System) Error!Plan {
    const d = try zmd.parse(disk);
    const board = try d.boardImage();
    const image = try unpack(gpa, board, window);
    errdefer gpa.free(image);
    var p = Plan{ .image = image, .disk = &.{}, .disk_at = 0, .desc = undefined, .desc_at = @intCast(window - map.DISK_DESC_FROM_TOP), .packed_bytes = @intCast(board.len) };
    var end: usize = image.len;
    if (system.isCart(image)) {
        const c = try system.check(sys, image);
        if (mc.CART_IMG_AT + image.len > window) return error.TooBig;
        p.sys = sys.?.image;
        p.image_at = mc.CART_IMG_AT;
        end = c.bss_end;
    }
    p.disk = try d.shelfDisk(gpa);
    errdefer gpa.free(p.disk);
    p.disk_at = try diskAt(end, p.disk.len, window);
    const size: u32 = @intCast(p.disk.len);
    const words = [map.DISK_DESC_WORDS]u32{ magic, p.disk_at, size, ~(magic ^ p.disk_at ^ size) };
    for (words, 0..) |w, i| std.mem.writeInt(u32, p.desc[i * 4 ..][0..4], w, .little);
    return p;
}

/// Where the disk goes: the first DISK_ALIGN boundary after `image_end`, ending by the
/// pictures (DISK_END) and below the descriptor.
pub fn diskAt(image_end: usize, disk_len: usize, window: usize) Error!u32 {
    const at = std.mem.alignForward(usize, image_end, map.DISK_ALIGN);
    const end = @min(map.DISK_END, window - map.DISK_DESC_FROM_TOP);
    if (at + disk_len > end) return error.DiskTooBig;
    return @intCast(at);
}
