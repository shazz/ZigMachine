// --------------------------------------------------------------------------
// SysInfo — reading the machine. Every value on the pages comes from here, and
// here only from what a cart may reach: the hw* calls of the system table
// (fpga/cycles/sys_abi.txt), the machine's registers through hwVideoBase(),
// the ROM's exports, the drive, and the ABI's own constants (memmap.zig).
//
// hwVersion(), hwPlanesNumber() and the hwPhys* calls are NOT used: they are
// machine exports outside the system table, so a cart importing them could
// not link lean for the board (fpga/tools/host_split.py refuses it). Their
// values show as n/a; the report proposes them as table entries.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const hw = @import("hardware");
const rom = @import("rom_sdk");
const diskinfo = @import("diskinfo.zig");

pub fn base() usize {
    return @intCast(hw.hwVideoBase());
}
pub fn reg8(off: usize) u8 {
    return @as(*const volatile u8, @ptrFromInt(base() + off)).*;
}
pub fn reg16(off: usize) u16 {
    return @as(*const volatile u16, @ptrFromInt(base() + off)).*;
}
pub fn reg32(off: usize) u32 {
    return @as(*const volatile u32, @ptrFromInt(base() + off)).*;
}

// Two read-only registers the SDK header does not re-export: their offsets are
// memmap.zig's (the ABI), mirrored here.
const REG_NB_PLANES: usize = 0x01; // u8 (ro)
const REG_FRAME: usize = 0x30; // u32 (ro): +1 at every hwClear, i.e. every frame the host shows

pub fn frameCounter() u32 {
    return reg32(REG_FRAME);
}
pub fn planesReg() u8 {
    return reg8(REG_NB_PLANES);
}

pub const Plane = struct { enabled: bool, mode: u8, stride: u16, fb: u32, hscroll: u16 };

pub fn plane(os: *const zg.ZigOS, i: usize) Plane {
    return .{
        .enabled = os.lfbs[i].is_enabled,
        .mode = reg8(hw.REG_FB_MODE + i),
        .stride = reg16(hw.REG_FB_STRIDE + i * 2),
        .fb = reg32(hw.REG_FB_BASE + i * 4),
        .hscroll = reg16(hw.REG_HSCROLL + i * 2),
    };
}

pub fn modeName(mode: u8) []const u8 {
    return switch (mode) {
        hw.FB_MODE_NORMAL => "LOW 320*200",
        hw.FB_MODE_FULLSCREEN => "LOW 400*280 FULL",
        hw.FB_MODE_SCROLL => "LOW SCROLL",
        hw.FB_MODE_MEDIUM => "MEDIUM 640*200",
        hw.FB_MODE_OVERSCAN => "LOW OVERSCAN",
        else => "UNKNOWN",
    };
}

/// A plane's buffer size by its mode, or 0 where the mode does not say (SCROLL).
fn planeBytes(p: Plane) u32 {
    return switch (p.mode) {
        hw.FB_MODE_NORMAL => hw.NORMAL_FB_BYTES,
        hw.FB_MODE_FULLSCREEN, hw.FB_MODE_OVERSCAN => hw.FULLSCREEN_FB_BYTES,
        hw.FB_MODE_MEDIUM => if (p.stride >= hw.RASTER_WIDTH) hw.MEDIUM_FULL_FB_BYTES else hw.MEDIUM_FB_BYTES,
        else => 0,
    };
}

/// The highest byte of the VRAM pool the four planes' buffers reach, from
/// their FB_BASE and mode registers (the pool is a bump allocator: no free list).
pub fn vramTop(os: *const zg.ZigOS) u32 {
    var top: u32 = 0;
    for (0..hw.NB_PLANES) |i| {
        const p = plane(os, i);
        const end = p.fb + planeBytes(p);
        if (end > hw.OFF_VRAM) top = @max(top, end - @as(u32, hw.OFF_VRAM));
    }
    return top;
}

pub const Blit = struct { works: bool, cycles: u32 };

/// Is there a blitter? Ask it: FILL 8 pixels of a hidden plane and read them
/// back. A machine without one leaves the bytes alone.
pub fn blitterTest(blit: *zg.Blitter, fb: *zg.LogicalFB) Blit {
    const v: u8 = 0xA5;
    @memset(fb.fb[0..8], 0);
    blit.fill(fb, 0, 0, 8, 1, v);
    const cycles = blit.cycles();
    var works = true;
    for (fb.fb[0..8]) |b| works = works and b == v;
    blit.fill(fb, 0, 0, 8, 1, 0);
    return .{ .works = works, .cycles = cycles };
}

/// The mounted disk's descriptor, read through the drive (null: no disk).
pub fn readDisk() ?diskinfo.Info {
    var b: [3][diskinfo.BLOCK]u8 = undefined;
    for (&b, 0..) |*blk, i| {
        if (zg.readBlock(@intCast(i), blk) < diskinfo.BLOCK) return null;
    }
    return diskinfo.parse(&b[0], &b[1], &b[2]);
}

/// romScratchLen() == 0 means an old rom.wasm without the scratch exports.
pub fn romScratch() struct { ptr: u32, len: u32 } {
    return .{ .ptr = rom.romScratchPtr(), .len = rom.romScratchLen() };
}
