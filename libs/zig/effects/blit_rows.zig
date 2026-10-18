// --------------------------------------------------------------------------
// One row of a blit, written a WORD at a time.
//
// On the board ZIGGY's data cache is write-through: every store goes out to DDR
// over the bus (blocking, about +24 cycles each in fpga/CYCLES.md's model of the
// HP path), so a keyed or inked row stored one byte per pixel costs one bus
// write per pixel. Here the row's pixels are decided one byte at a time as
// before (`pick` sees the same source byte, destination byte and column), but
// they are gathered four by four and each destination word gets ONE store: a
// whole word when every byte is drawn, a merge with the bytes already there when
// some are keyed out, and no store at all when none is drawn. The bytes in
// memory end up exactly what the byte loop left (blit_rows_test.zig compares the
// two on every alignment and every key pattern).
//
// Word stores are made only at 4-aligned destination addresses: the board traps
// a misaligned word access and emulates it. The source is still read a byte at
// a time (loads hit the cache), so its alignment does not matter. Rows shorter
// than 8 pixels, and rows whose source overlaps the destination (where the byte
// loop's order is part of the result), keep the byte loop.
// --------------------------------------------------------------------------

/// What `pick` returns for one pixel: `put(v)` writes v, `skip` leaves the
/// destination. A plain integer, not a struct: ReleaseSmall kept a returned
/// struct on the stack (a byte store per pixel), an integer stays in a register.
pub const Px = u32;
pub const skip: Px = 0;
pub inline fn put(v: u8) Px {
    return 0x100 | @as(Px, v);
}

const MIN_WORDS_ROW = 8;

comptime {
    // a word's byte b is its bits 8b..8b+7: true of wasm32, rv32 and x86
    if (@import("builtin").cpu.arch.endian() != .little) @compileError("blit_rows: little-endian only");
}

/// For i in 0..out.len: `r = pick(ctx, in[i], out[i], i)`; out[i] = v where r is
/// put(v). pick is called exactly once per pixel, in increasing i, so a ctx
/// pointer may carry state from pixel to pixel. `reads_dst` says whether pick
/// looks at its destination byte (it is 0 otherwise). Inline, so the picks and
/// their ctx fold into the caller's loop and stay in registers.
pub inline fn row(out: []u8, in: []const u8, ctx: anytype, comptime pick: anytype, comptime reads_dst: bool) void {
    if (out.len < MIN_WORDS_ROW or overlaps(out, in)) return bytes(out, in, true, 0, out.len, ctx, pick, reads_dst);
    words(out, in, true, ctx, pick, reads_dst);
}

/// row() with no source: pick makes each pixel from its ctx and column alone
/// (its source byte is 0). For rows assembled from several sources, e.g. a
/// line of text glyph after glyph.
pub inline fn gen(out: []u8, ctx: anytype, comptime pick: anytype) void {
    if (out.len < MIN_WORDS_ROW) return bytes(out, out, false, 0, out.len, ctx, pick, false);
    words(out, out, false, ctx, pick, false);
}

inline fn words(out: []u8, in: []const u8, comptime has_src: bool, ctx: anytype, comptime pick: anytype, comptime reads_dst: bool) void {
    const n = out.len;
    const head = (4 -% @intFromPtr(out.ptr)) & 3;
    bytes(out, in, has_src, 0, head, ctx, pick, reads_dst);
    var i: usize = head;
    while (i + 4 <= n) : (i += 4) {
        const wp: *u32 = @ptrCast(@alignCast(out.ptr + i));
        const old: u32 = if (reads_dst) wp.* else 0;
        var nw: u32 = 0;
        var m: u32 = 0;
        inline for (0..4) |b| {
            const d: u8 = if (reads_dst) @truncate(old >> (8 * b)) else 0;
            const r: Px = pick(ctx, if (has_src) in[i + b] else 0, d, i + b);
            nw |= (r & 0xFF) << (8 * b); // skip is 0: adds nothing
            m |= ((r >> 8) * 0xFF) << (8 * b);
        }
        if (m == 0xFFFF_FFFF) {
            wp.* = nw;
        } else if (m != 0) {
            const cur: u32 = if (reads_dst) old else wp.*;
            wp.* = (cur & ~m) | nw;
        }
    }
    bytes(out, in, has_src, i, n, ctx, pick, reads_dst);
}

inline fn bytes(out: []u8, in: []const u8, comptime has_src: bool, from: usize, to: usize, ctx: anytype, comptime pick: anytype, comptime reads_dst: bool) void {
    var i = from;
    while (i < to) : (i += 1) {
        const r: Px = pick(ctx, if (has_src) in[i] else 0, if (reads_dst) out[i] else 0, i);
        if (r != skip) out[i] = @truncate(r);
    }
}

fn overlaps(out: []u8, in: []const u8) bool {
    const o0 = @intFromPtr(out.ptr);
    const s0 = @intFromPtr(in.ptr);
    return o0 < s0 + in.len and s0 < o0 + out.len;
}

pub inline fn keyedCopy(key: u8, p: u8, _: u8, _: usize) Px {
    return if (p != key) put(p) else skip;
}

/// The per-pixel rule of each blit.Ink mode, for row(): one function per mode, so each
/// mode keeps its own tight loop.
pub fn Inked(comptime V: type, comptime keyed: bool) type {
    return struct {
        key: u8,
        v: V,
        const C = @This();
        inline fn drawn(c: C, p: u8) bool {
            return !keyed or p != c.key;
        }
        pub inline fn flat(c: C, p: u8, _: u8, _: usize) Px {
            return if (c.drawn(p)) put(c.v) else skip;
        }
        pub inline fn offset(c: C, p: u8, _: u8, _: usize) Px {
            return if (c.drawn(p)) put(p +% c.v) else skip;
        }
        pub inline fn lut(c: C, p: u8, _: u8, _: usize) Px {
            return if (c.drawn(p)) put(c.v[p]) else skip;
        }
        pub inline fn pattern(c: C, p: u8, _: u8, i: usize) Px {
            return if (c.drawn(p)) put(c.v[i]) else skip;
        }
        pub inline fn select(c: C, p: u8, d: u8, _: usize) Px {
            return if (c.drawn(p) and c.v.set[d] == c.v.inside) put(p) else skip;
        }
    };
}
