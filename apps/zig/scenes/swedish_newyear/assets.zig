// The pictures and fonts, part by part. Every .raw ships ZX0-packed (build.zig:
// packed_assets.swedish_newyear); on entering a part its set is depacked into the
// one part buffer (ram.zig), after which the part's own scratch sits. Only one
// part runs at a time, so the buffer is the LARGEST set, not the sum: OMEGA's
// ~248 KB against ~620 KB of pictures unpacked.
//
// The Imgs keep assets_gen.zig's size, depth and LUT; only `.data` is filled here.
const std = @import("std");
const zx0 = @import("depackers").zx0;
const PACKED = @import("packed_assets").swedish_newyear;
const gen = @import("assets_gen.zig");
const Img = @import("image.zig").Img;
const ram = @import("ram.zig");
const tcb1 = @import("tcb1.zig");
const org = @import("tcb2_org.zig");

pub const Set = enum { menu, sync, tcb1, tcb2, omega };

pub var main_px: []const u8 = &.{}; // 320x200, a byte a pixel (main_lut's row-local index)
pub var font7 = blank(gen.font7);
pub var block = blank(gen.block);
pub var banner = blank(gen.banner);
pub var syncfont = blank(gen.syncfont);
pub var logo = blank(gen.logo);
pub var sync1 = blank(gen.sync1);
pub var sync2 = blank(gen.sync2);
pub var tcb = blank(gen.tcb);
pub var kh = blank(gen.kh);
pub var kh2 = blank(gen.kh2);
pub var edge = blank(gen.edge);
pub var tcblogo = blank(gen.tcblogo);
pub var wizcoder = blank(gen.wizcoder);
pub var ancool = blank(gen.ancool);
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
    entry(.sync, PACKED.banner, gen.banner, &banner),
    entry(.sync, PACKED.syncfont, gen.syncfont, &syncfont),
    entry(.sync, PACKED.logo, gen.logo, &logo),
    entry(.sync, PACKED.sync1, gen.sync1, &sync1),
    entry(.sync, PACKED.sync2, gen.sync2, &sync2),
    entry(.tcb1, PACKED.tcb, gen.tcb, &tcb),
    entry(.tcb2, PACKED.kh, gen.kh, &kh),
    entry(.tcb2, PACKED.kh2, gen.kh2, &kh2),
    entry(.tcb2, PACKED.edge, gen.edge, &edge),
    entry(.tcb2, PACKED.tcblogo, gen.tcblogo, &tcblogo),
    entry(.tcb2, PACKED.wizcoder, gen.wizcoder, &wizcoder),
    entry(.tcb2, PACKED.ancool, gen.ancool, &ancool),
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
        .tcb1 => tcb1.Noise,
        .tcb2 => org.Scratch,
        else => void,
    };
}

/// The part buffer: the largest set with its scratch.
pub const PART_LEN: usize = blk: {
    var most: usize = 0;
    for (std.enums.values(Set)) |s| most = @max(most, scratchAt(s) + @sizeOf(ScratchOf(s)));
    break :blk most;
};

/// A part's scratch; valid while its set is the one loaded.
pub fn scratch(comptime set: Set) *ScratchOf(set) {
    return @ptrCast(@alignCast(ram.buf.part[scratchAt(set)..][0..@sizeOf(ScratchOf(set))]));
}

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
