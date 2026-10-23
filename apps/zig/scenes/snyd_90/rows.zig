// --------------------------------------------------------------------------
// The shifter's pixels (shifter.zig), row by physical row, INCREMENTALLY: on
// KESTREL every store is a blocking bus write (~27 cycles) and a load is
// nearly free, and an ST part changes a few 16-pixel groups of its screen a
// VBL. So a capture does not build a chunky frame: it compares each group's
// four plane words with the copy it took last time (loads) and notes which
// groups changed; present() converts only those, straight into the plane, and
// stores only the plane words that differ. Same pixels as converting the whole
// screen (apps/snyd_90_pins.mjs pins every frame to the old full conversion).
// A row is one of:
//   blank   all colour 0 (borders, lines the part does not show)
//   planar  `ng` groups of four plane words from an ST address, group g's
//           first pixel at plane x `x0 + 16 g` (the window: 40, 20 groups; a
//           full-overscan line: -12, 26), colour 0 outside them
//   live    like planar, for a part that rewrites its whole picture every VBL
//           (F5's texture): no copy, no compare at capture -- present()
//           converts every group from the part's memory, which nothing writes
//           between a capture and the next present() (a new part's entry
//           captures every row again)
//   custom  palette indices the part computes itself (the intro's Spectrum
//           512 slots, F6's raster lines), copied word by word on change
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const st = @import("../swedish_newyear/st.zig");
const chunky = @import("chunky.zig");

pub const PW: usize = zg.PHYSICAL_WIDTH; // 400
pub const PH: usize = zg.PHYSICAL_HEIGHT; // 280
const MAXG = 26; // groups of a full-overscan line
const WPR = PW / 4; // plane words a row

pub const Kind = enum(u8) { blank, planar, live, custom };
pub const Key = packed struct(u32) { kind: Kind, ng: u8 = 0, x0: i16 = 0 };

var next: [PH]Key = undefined; // what each row is to show (the last capture)
var shown: [PH]Key = undefined; // what the plane holds
var dirty: [PH]u32 = undefined; // planar: the groups changed since present(); custom: != 0
var cache: *[PH][MAXG * 4]u16 = undefined; // planar: the plane words last read, as loaded
var custom: *[PH][PW]u8 = undefined;
var live_src: [PH][*]const u8 = undefined; // live: the row's first group in the part's memory

/// Once per cart load: the plane was just cleared.
pub fn init() void {
    cache = zg.mem.mustAlloc([MAXG * 4]u16, PH)[0..PH];
    const c = zg.mem.mustAlloc(u32, PH * WPR);
    custom = @ptrCast(c.ptr);
    @memset(&next, .{ .kind = .blank });
    @memset(&shown, .{ .kind = .blank });
    @memset(&dirty, 0);
}

pub fn blank(py: usize) void {
    if (next[py] != Key{ .kind = .blank }) next[py] = .{ .kind = .blank };
}

/// Row `py` shows `ng` groups read from ST address `addr` of `r`, group 0 at plane x `x0`.
pub fn planar(r: *const st.Ram, py: usize, addr: u32, x0: i16, ng: u8) void {
    const key = Key{ .kind = .planar, .ng = ng, .x0 = x0 };
    const fresh = next[py] != key;
    if (fresh) next[py] = key;
    const src: [*]align(2) const u16 = @ptrCast(@alignCast(r.bytes(addr, @as(usize, ng) * 8).ptr));
    const c = &cache[py];
    var mask = dirty[py];
    for (0..ng) |g| {
        var changed = fresh;
        inline for (0..4) |k| {
            const v = src[4 * g + k];
            if (c[4 * g + k] != v) {
                c[4 * g + k] = v;
                changed = true;
            }
        }
        if (changed) mask |= @as(u32, 1) << @intCast(g);
    }
    if (mask != dirty[py]) dirty[py] = mask;
}

/// Row `py` shows `ng` groups at `src` (a part's memory), converted whole at present().
pub fn live(py: usize, src: [*]const u8, x0: i16, ng: u8) void {
    const key = Key{ .kind = .live, .ng = ng, .x0 = x0 };
    if (next[py] != key) next[py] = key;
    live_src[py] = src;
    dirty[py] = 1;
}

/// Row `py` as indices the caller writes; zeroed when the row was not custom.
pub fn customRow(py: usize) *[PW]u8 {
    if (next[py].kind != .custom) {
        next[py] = .{ .kind = .custom };
        @memset(&custom[py], 0);
    }
    dirty[py] = 1;
    return &custom[py];
}

/// The captured rows into the plane: only what changed, only the words that differ.
pub fn present(fb: [*]u8) void {
    const plane: [*]u32 = @ptrCast(@alignCast(fb));
    for (0..PH) |py| {
        const row = plane[py * WPR ..][0..WPR];
        const key = next[py];
        const fresh = key != shown[py];
        if (!fresh and dirty[py] == 0) continue;
        switch (key.kind) {
            .blank => for (row) |*w| put(w, 0),
            .custom => {
                const src: *const [WPR]u32 = @ptrCast(@alignCast(&custom[py]));
                for (row, src) |*w, v| put(w, v);
            },
            .planar => presentPlanar(row, py, key, fresh),
            .live => presentLive(row, live_src[py], key, fresh),
        }
        if (fresh) shown[py] = key;
        dirty[py] = 0;
    }
}

fn presentPlanar(row: *[WPR]u32, py: usize, key: Key, fresh: bool) void {
    if (fresh) edges(row, key);
    const mask = if (fresh) (@as(u32, 1) << @intCast(key.ng)) - 1 else dirty[py];
    convert(row, @ptrCast(&cache[py]), key, mask);
}

fn presentLive(row: *[WPR]u32, src: [*]const u8, key: Key, fresh: bool) void {
    if (fresh) edges(row, key);
    convert(row, src, key, (@as(u32, 1) << @intCast(key.ng)) - 1);
}

/// Colour 0 outside the row's groups.
fn edges(row: *[WPR]u32, key: Key) void {
    const w0: i32 = @divExact(@as(i32, key.x0), 4);
    for (row, 0..) |*w, i| {
        const k = @as(i32, @intCast(i)) - w0;
        if (k < 0 or k >= 4 * @as(i32, key.ng)) put(w, 0);
    }
}

/// The groups in `mask` of plane words at `bytes` into the row (the words inside the plane).
fn convert(row: *[WPR]u32, bytes: [*]const u8, key: Key, mask: u32) void {
    const w0: i32 = @divExact(@as(i32, key.x0), 4); // the row's first word (may be left of the plane)
    for (0..key.ng) |g| {
        if (mask & (@as(u32, 1) << @intCast(g)) == 0) continue;
        const words = chunky.groupWords(bytes[8 * g ..][0..8]);
        inline for (0..4) |k| {
            const i = w0 + @as(i32, @intCast(4 * g + k));
            if (i >= 0 and i < WPR) put(&row[@intCast(i)], words[k]);
        }
    }
}

/// A plane word, stored only when it differs (reading the plane back is free).
inline fn put(w: *u32, v: u32) void {
    if (w.* != v) w.* = v;
}

test "a row key packs into one word" {
    try std.testing.expect(Key{ .kind = .planar, .ng = 20, .x0 = 40 } != Key{ .kind = .planar, .ng = 26, .x0 = -12 });
}
