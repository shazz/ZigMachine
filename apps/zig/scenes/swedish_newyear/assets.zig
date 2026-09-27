// The pictures and fonts, part by part. Every .raw ships ZX0-packed (build.zig:
// packed_assets.swedish_newyear); on entering a part its set is depacked into the
// one part buffer (ram.zig), after which the part's own scratch sits. Only one
// part runs at a time, so the buffer is the LARGEST set, not the sum. The SYNC
// and TCB "sets" are the real parts as the loader reads them, and their scratch
// is the rest of the part's memory (st.zig); TCB's 480 KB is the largest.
//
// The Imgs keep assets_gen.zig's size, depth and LUT; only `.data` is filled here.
const std = @import("std");
const zx0 = @import("depackers").zx0;
const PACKED = @import("packed_assets").swedish_newyear;
const gen = @import("assets_gen.zig");
const Img = @import("image.zig").Img;
const ram = @import("ram.zig");
const sync1 = @import("sync1.zig");
const tcb1 = @import("tcb1.zig");

pub const Set = enum { menu, sync, tcb, omega };

pub const SYNC_IMAGE: usize = 11 * 9 * 2 * 512;
/// SYNC's memory, $20000..$80000: the tracks, its buffers, its two screens.
pub const SYNC_RAM: usize = sync1.TOP - sync1.BASE;
pub const TCB_IMAGE: usize = 26 * 9 * 2 * 512;
/// TCB's memory, $8000..$80000.
pub const TCB_RAM: usize = tcb1.TOP - tcb1.BASE;

pub var main_px: []const u8 = &.{}; // 320x200, a byte a pixel (main_lut's row-local index)
/// The SYNC part as the loader read it (tracks 45..55, 101,376 bytes to $20000).
pub var sync_part: []const u8 = &.{};
pub var font7 = blank(gen.font7);
pub var block = blank(gen.block);
/// The TCB part as the loader read it (tracks 12..37, 239,616 bytes to $8000).
pub var tcb_part: []const u8 = &.{};
pub var omain = blank(gen.omain);
pub var omega = blank(gen.omega);
pub var ofont = blank(gen.ofont);
pub var vumeter = blank(gen.vumeter);
pub var atari = blank(gen.atari);

fn blank(comptime img: Img) Img {
    return .{ .w = img.w, .h = img.h, .bits = img.bits, .data = &.{}, .lut = img.lut };
}

fn imgLen(comptime img: Img) usize {
    const w: usize = @intCast(img.w);
    const h: usize = @intCast(img.h);
    return h * if (img.bits == 8) w else (w + 1) / 2;
}

const Entry = struct { set: Set, src: []const u8, len: usize, data: *[]const u8 };

fn entry(set: Set, src: []const u8, comptime img: Img, dst: *Img) Entry {
    return .{ .set = set, .src = src, .len = imgLen(img), .data = &dst.data };
}

const ENTRIES = [_]Entry{
    .{ .set = .menu, .src = PACKED.main, .len = 320 * 200, .data = &main_px },
    entry(.menu, PACKED.font7, gen.font7, &font7),
    entry(.menu, PACKED.block, gen.block, &block),
    .{ .set = .sync, .src = PACKED.sync_part, .len = SYNC_IMAGE, .data = &sync_part },
    .{ .set = .tcb, .src = PACKED.tcb_part, .len = TCB_IMAGE, .data = &tcb_part },
    entry(.omega, PACKED.omain, gen.omain, &omain),
    entry(.omega, PACKED.omega, gen.omega, &omega),
    entry(.omega, PACKED.ofont, gen.ofont, &ofont),
    entry(.omega, PACKED.vumeter, gen.vumeter, &vumeter),
    entry(.omega, PACKED.atari, gen.atari, &atari),
};

/// Bytes a set's pictures take, depacked.
fn assetsLen(comptime set: Set) usize {
    var n: usize = 0;
    for (ENTRIES) |e| if (e.set == set) {
        n += e.len;
    };
    return n;
}

/// The part's scratch, placed after its pictures (4-aligned).
fn scratchAt(comptime set: Set) usize {
    return std.mem.alignForward(usize, assetsLen(set), 4);
}

fn ScratchOf(comptime set: Set) type {
    return switch (set) {
        .tcb => [TCB_RAM - TCB_IMAGE]u8,
        .sync => [SYNC_RAM - SYNC_IMAGE]u8, // the part's memory above its tracks
        else => void,
    };
}

/// The part buffer: the largest set with its scratch.
pub const PART_LEN: usize = blk: {
    var most: usize = 0;
    for (std.enums.values(Set)) |s| most = @max(most, scratchAt(s) + @sizeOf(ScratchOf(s)));
    break :blk most;
};

/// Depack `set` into the part buffer. False (nothing usable) if a blob does not
/// depack to its picture's size: a build fault, never expected at run time.
pub fn load(set: Set) bool {
    var off: usize = 0;
    for (ENTRIES) |e| {
        e.data.* = &.{};
        if (e.set != set) continue;
        const dst = ram.buf.part[off..][0..e.len];
        if ((zx0.depack(e.src, dst) orelse return false) != e.len) return false;
        e.data.* = dst;
        off += e.len;
    }
    return true;
}
