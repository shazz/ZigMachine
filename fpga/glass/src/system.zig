// The system image and lean carts (decisions.md 2026-10-15): the SD card carries the
// firmware + machine + ROM + BARD once, as zigmachine/system.rv32, and each fat disk only
// its cart. glass reads and depacks the system once, at start-up; a load writes it at the
// window's start and the cart at map_cart.CART_IMG_AT. A cart built for another table
// version is refused here, before DDR or the CPU are touched; the firmware checks again
// (TRAP_CART_ABI). fpga/tools/split_image.py writes and reads the same bytes.
const std = @import("std");
const zx0 = @import("zx0");
const map = @import("map.zig");
const mc = @import("map_cart.zig");

pub const FILE = "system.rv32";
pub const Error = error{ NoSystem, BadSystem, BadCart, CartAbi };

pub const System = struct {
    version: u32, // the table it serves, major << 16 | minor
    image: []u8, // what goes at the window's start

    pub fn deinit(self: System, gpa: std.mem.Allocator) void {
        gpa.free(self.image);
    }
};

pub const Cart = struct {
    version: u32, // the table it needs
    bss_end: u32, // window offset: the disk may start here
};

/// What the last refusal compared (for the OSD: both versions); glass is single-threaded.
pub var last_abi: struct { need: u32 = 0, have: u32 = 0 } = .{};

/// cycles/bsys_abi.h's rule: the same major; the cart's minor at most the system's.
pub fn abiOk(need: u32, have: u32) bool {
    return need >> 16 == have >> 16 and need & 0xFFFF <= have & 0xFFFF;
}

pub fn isCart(image: []const u8) bool {
    return image.len >= 4 and std.mem.readInt(u32, image[0..4], .little) == mc.CART_HDR_MAGIC;
}

/// A lean cart's header: what it needs and where its .bss ends.
pub fn cart(image: []const u8) Error!Cart {
    if (!isCart(image) or image.len < mc.CART_HDR_BSS_END_AT + 4) return error.BadCart;
    const ver = std.mem.readInt(u32, image[mc.CART_HDR_VERSION_AT..][0..4], .little);
    const bss_cpu = std.mem.readInt(u32, image[mc.CART_HDR_BSS_END_AT..][0..4], .little);
    if (bss_cpu < map.CART_CPU_BASE) return error.BadCart;
    const end = bss_cpu - map.CART_CPU_BASE;
    if (end < mc.CART_IMG_AT + image.len or end > map.DISK_END) return error.BadCart;
    return .{ .version = ver, .bss_end = end };
}

/// The cart, if `sys` runs it: CartAbi (with last_abi set) if not, NoSystem if there is none.
pub fn check(sys: ?System, image: []const u8) Error!Cart {
    const c = try cart(image);
    const s = sys orelse return error.NoSystem;
    if (!abiOk(c.version, s.version)) {
        last_abi = .{ .need = c.version, .have = s.version };
        return error.CartAbi;
    }
    return c;
}

/// A system.rv32 (ZX0-packed, or not) -> its version and image.
pub fn parse(gpa: std.mem.Allocator, file: []const u8) (Error || error{OutOfMemory})!System {
    const data = if (zx0.isPacked(file)) try depack(gpa, file) else try gpa.dupe(u8, file);
    defer gpa.free(data);
    const head = mc.SYS_HEAD_WORDS * 4;
    if (data.len < head) return error.BadSystem;
    var w: [4]u32 = undefined;
    for (&w, 0..) |*x, i| x.* = std.mem.readInt(u32, data[i * 4 ..][0..4], .little);
    if (w[0] != mc.SYS_MAGIC or w[3] != ~(w[0] ^ w[1] ^ w[2])) return error.BadSystem;
    if (w[2] != data.len - head or w[2] > mc.CART_IMG_AT) return error.BadSystem;
    return .{ .version = w[1], .image = try gpa.dupe(u8, data[head..]) };
}

fn depack(gpa: std.mem.Allocator, file: []const u8) (Error || error{OutOfMemory})![]u8 {
    const n = zx0.depackedLen(file) orelse return error.BadSystem;
    if (n > mc.CART_IMG_AT + mc.SYS_HEAD_WORDS * 4) return error.BadSystem;
    const out = try gpa.alloc(u8, n);
    errdefer gpa.free(out);
    if ((zx0.depack(file, out) orelse return error.BadSystem) != n) return error.BadSystem;
    return out;
}

/// The card's system image, once at start-up: null if the card has none (monolithic carts
/// still load) or it does not parse (logged; lean carts then say NoSystem).
pub fn load(gpa: std.mem.Allocator, io: std.Io, dir: []const u8) ?System {
    const path = std.fs.path.join(gpa, &.{ dir, FILE }) catch return null;
    defer gpa.free(path);
    const file = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(8 << 20)) catch |err| {
        if (err != error.FileNotFound) std.log.warn("{s}: {t}", .{ path, err });
        return null;
    };
    defer gpa.free(file);
    const sys = parse(gpa, file) catch |err| {
        std.log.warn("{s}: {t}", .{ path, err });
        return null;
    };
    std.log.info("{s}: table {d}.{d}, {d} bytes", .{ path, sys.version >> 16, sys.version & 0xFFFF, sys.image.len });
    return sys;
}
