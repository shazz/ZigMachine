// The board's two windows, through /dev/mem: the register block on M_AXI_GP0
// and the cart CPU's RAM in the DDR Linux was told not to touch (a
// reserved-memory node with no-map, boot/zigmachine.dtsi). O_SYNC makes the
// kernel map both uncached, so a store reaches the PL or DDR without a cache
// flush, and the cart CPU (which reads DDR through an HP port, not coherent
// with the ARM's caches) sees exactly what was written.
//
// Linux-only; needs root (or CAP_SYS_RAWIO). Nothing here runs in the tests.
const std = @import("std");
const linux = std.os.linux;
const map = @import("map.zig");
const bus = @import("bus.zig");

pub const Error = error{ DevMemOpen, DevMemMap };

pub const Board = struct {
    regs_words: []volatile u32,
    ddr_words: []volatile u32,

    pub fn regs(self: Board) bus.Regs {
        return bus.Regs.mapped(self.regs_words);
    }

    pub fn ddr(self: Board) bus.Ddr {
        return .{ .words = self.ddr_words };
    }
};

fn mapWindow(fd: i32, phys: u32, len: u32) Error![]volatile u32 {
    const rc = linux.mmap(null, len, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, phys);
    if (linux.errno(rc) != .SUCCESS) {
        std.log.err("mmap /dev/mem at 0x{X:0>8} (+0x{X}): {t}", .{ phys, len, linux.errno(rc) });
        return error.DevMemMap;
    }
    const p: [*]volatile u32 = @ptrFromInt(rc);
    return p[0 .. len / 4];
}

pub fn open() Error!Board {
    const rc = linux.open("/dev/mem", .{ .ACCMODE = .RDWR, .SYNC = true, .CLOEXEC = true }, 0);
    if (linux.errno(rc) != .SUCCESS) {
        std.log.err("open /dev/mem: {t} (run as root, kernel with CONFIG_DEVMEM)", .{linux.errno(rc)});
        return error.DevMemOpen;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd); // the mappings outlive the descriptor
    return .{
        .regs_words = try mapWindow(fd, map.GP0_BASE, map.WINDOW_BYTES),
        .ddr_words = try mapWindow(fd, map.DDR_CART_BASE, map.DDR_CART_BYTES),
    };
}

/// A millisecond's nap between polls of the PL (loader.Options.idle).
pub fn napMs() void {
    const ts = linux.timespec{ .sec = 0, .nsec = 1_000_000 };
    _ = linux.nanosleep(&ts, null);
}
