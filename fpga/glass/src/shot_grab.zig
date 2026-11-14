// What a screenshot copies out of the cart window (app_shot.zig): the picture FRESCO shows.
//
// FRESCO composites each frame into one of two 800x280 pictures of {0, B, G, R} words in the cart
// window (fpga/rtl/video/README.md "The pictures") and scans the other out: every plane, palette,
// mode, scroll, border, true-colour plane and per-line change (HBL handlers, copper, linepal,
// BEAM) is already in it, and so is GEM's arrow (cycles/bcursor.c); the OSD is not (the PL lays
// it over the scanout). So nothing is composited here: the shot IS the front picture. ZIGGY's
// debug mailbox (cycles/bmailbox.h, the window's last 256 bytes) says where the pictures are and,
// asked to freeze, stops the cart after a whole frame and names the one on screen, which then
// holds still while it is copied (fpga/tools/board_shot.py does the same from U-Boot).
//
// The desk mode (RES_DESK) has no picture: the scanout shows plane 0's 640x480 bytes through
// palette 0 (rtl/video/zm_video_desk.v), so that is what is copied, as an indexed image.
const std = @import("std");
const bus = @import("bus.zig");
const mm = @import("memmap");
const mc = @import("map_cart.zig");

// cycles/bmailbox.h's words (MB_*): CPU bus addresses, a window offset = address - cpu_base.
pub const MB_FB0 = 2;
pub const MB_FB1 = 3;
pub const MB_PFB = 6;
pub const MB_PIC_W = 9;
pub const MB_PIC_H = 10;
pub const MB_CPU_BASE = 11;
pub const MB_FREEZE = 13;
pub const MB_FROZEN = 14;
pub const MB_FRONT = 15;
const MAX_SIDE = 4096; // a picture word count from a corrupt mailbox must not size an allocation

pub const Error = error{ NoMailbox, BadMailbox, FreezeTimeout, OutOfMemory };

pub const Env = struct {
    ddr: bus.Ddr,
    nap: *const fn (ms: u32) void, // the worker's thread sleeps while the cart finishes its frame
    freeze_ms: u32 = 2000, // a 1 fps cart still answers; a hung firmware never does
    clock: *const fn () i64 = noClock, // ms, monotonic (App.clock): how long the cart was held
};

fn noClock() i64 {
    return 0;
}

/// The copied image, ready for shot_png (px owned; `pal` used by the desk only).
pub const Shot = struct {
    w: u32,
    h: u32,
    desk: bool,
    px: []u8,
    pal: [768]u8 = undefined,
    frozen_ms: i64 = 0, // the stall the shot cost the cart: from its frame's end to the copy's

    pub fn deinit(s: Shot, gpa: std.mem.Allocator) void {
        gpa.free(s.px);
    }
};

/// The cart frozen for the copy only (from a frame's end until the copy is done), then let go;
/// the conversion runs after. The freeze is cleared on every path: one left set stops the console.
pub fn grab(gpa: std.mem.Allocator, env: Env, desk: bool) Error!Shot {
    const mb = try mailbox(env.ddr);
    try freeze(env, mb);
    const t0 = env.clock();
    if (desk) {
        var s = blk: {
            defer mb[MB_FREEZE] = 0;
            break :blk try deskShot(gpa, env.ddr, mb);
        };
        s.frozen_ms = env.clock() - t0;
        return s;
    }
    const pic = blk: {
        defer mb[MB_FREEZE] = 0;
        break :blk try picture(gpa, env.ddr, mb);
    };
    const held = env.clock() - t0;
    defer gpa.free(pic.raw);
    var s = try fromPicture(gpa, pic.raw, pic.w, pic.h);
    s.frozen_ms = held;
    return s;
}

fn mailbox(ddr: bus.Ddr) Error![]volatile u32 {
    const n = mc.MB_BYTES / 4;
    if (ddr.words.len < n) return error.NoMailbox;
    const mb = ddr.words[ddr.words.len - n ..];
    if (mb[0] != mc.MB_MAGIC) return error.NoMailbox;
    return mb;
}

fn freeze(env: Env, mb: []volatile u32) Error!void {
    mb[MB_FREEZE] = 1;
    var waited: u32 = 0;
    while (mb[MB_FROZEN] == 0) : (waited += 1) {
        if (waited >= env.freeze_ms) {
            mb[MB_FREEZE] = 0;
            return error.FreezeTimeout;
        }
        env.nap(1);
    }
}

/// `words` words at CPU address `addr`, or BadMailbox when that is not inside the window.
fn at(ddr: bus.Ddr, mb: []volatile u32, addr: u32, words: usize) Error![]volatile u32 {
    const off = addr -% mb[MB_CPU_BASE];
    if (off % 4 != 0 or off / 4 + words > ddr.words.len - mc.MB_BYTES / 4) return error.BadMailbox;
    return ddr.words[off / 4 ..][0..words];
}

const Picture = struct { raw: []u32, w: u32, h: u32 };

/// The front picture's words, copied.
fn picture(gpa: std.mem.Allocator, ddr: bus.Ddr, mb: []volatile u32) Error!Picture {
    const w = mb[MB_PIC_W];
    const h = mb[MB_PIC_H];
    if (w == 0 or h == 0 or w % 2 != 0 or w > MAX_SIDE or h > MAX_SIDE) return error.BadMailbox;
    const src = try at(ddr, mb, if (mb[MB_FRONT] != 0) mb[MB_FB1] else mb[MB_FB0], w * h);
    const raw = try gpa.alloc(u32, src.len);
    for (raw, src) |*d, s| d.* = s; // one aligned word at a time (bus.zig)
    return .{ .raw = raw, .w = w, .h = h };
}

/// RGB from {0, B, G, R} words. Low-res pixels are doubled across the picture (every column
/// pair equal): one pixel each then, 400x280, square on the TV, which doubles the lines. A
/// picture with any 1:1 detail (a medium plane, an odd-placed arrow) keeps its columns and has
/// its lines doubled instead, 800x560, as the TV shows it. Lossless either way.
pub fn fromPicture(gpa: std.mem.Allocator, raw: []const u32, w: u32, h: u32) Error!Shot {
    const pairs = for (0..raw.len / 2) |i| {
        if (raw[2 * i] != raw[2 * i + 1]) break false;
    } else true;
    const ow = if (pairs) w / 2 else w;
    const oh = if (pairs) h else 2 * h;
    const px = try gpa.alloc(u8, @as(usize, ow) * oh * 3);
    for (0..oh) |y| for (0..ow) |x| {
        const v = raw[(if (pairs) y else y / 2) * w + (if (pairs) 2 * x else x)];
        px[(y * ow + x) * 3 ..][0..3].* = .{ @truncate(v), @truncate(v >> 8), @truncate(v >> 16) };
    };
    return .{ .w = ow, .h = oh, .desk = false, .px = px };
}

fn deskShot(gpa: std.mem.Allocator, ddr: bus.Ddr, mb: []volatile u32) Error!Shot {
    const vbase = mb[MB_PFB] -% @as(u32, mm.OFF_PFB); // the PFB sits at a fixed offset of the video region
    const regs = try at(ddr, mb, vbase, mm.OFF_VRAM / 4);
    const base = (regs[mm.REG_FB_BASE / 4] & ~@as(u32, 7)) +% vbase; // a beat, as the scanout reads it
    const plane = try at(ddr, mb, base, mm.DESK_FB_BYTES / 4);
    var s = Shot{ .w = mm.DESK_WIDTH, .h = mm.DESK_HEIGHT, .desk = true, .px = try gpa.alloc(u8, mm.DESK_FB_BYTES) };
    for (plane, 0..) |v, i| std.mem.writeInt(u32, s.px[4 * i ..][0..4], v, .little); // byte 0 is the leftmost pixel
    for (0..mm.PAL_ENTRIES) |i| { // palette 0's RGBA words, alpha never shown
        const v = regs[mm.OFF_PAL / 4 + i];
        s.pal[3 * i ..][0..3].* = .{ @truncate(v), @truncate(v >> 8), @truncate(v >> 16) };
    }
    return s;
}
