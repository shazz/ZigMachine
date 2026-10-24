// --------------------------------------------------------------------------
// st_show.zig's shifter: the part's screen rows into ram.buf.plane, a 16-pixel
// group at a time, reconverting only what changed since the row was last seen.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("st.zig");
const frame = @import("frame.zig");
const ram = @import("ram.zig");
const rows_ = @import("st_rows.zig");

const Row = rows_.Row;
const Rows = rows_.Rows;

// What each plane row was last converted from. A row whose descriptor is unchanged
// only reconverts the 16-pixel groups whose 8 source bytes changed (an ST screen
// changes in a few places a frame: 98% of OMEGA's pixels are the same as the frame
// before), and only the span of each row that changed is copied to the framebuffer.
// keys[py] is meaningful only while keyed[py]. Rows are read through pointers and keys
// copied field by field: copying a ?Row by value moved its tail as a 16-bit access at
// an odd offset, which traps on KESTREL (~700 cycles, once a row a frame).
var keys: [frame.PH]Row = undefined;
var keyed: [frame.PH]bool = [_]bool{false} ** frame.PH;
/// The pixels [lo, hi) of each plane row converted since the last present (lo >= hi: none).
pub var span_lo: [frame.PH]u16 = [_]u16{0} ** frame.PH;
pub var span_hi: [frame.PH]u16 = [_]u16{frame.PW} ** frame.PH;
var blank: [frame.PH]bool = [_]bool{false} ** frame.PH;

pub fn convertRows(r: *const st.Ram, rows: *const Rows) void {
    for (ram.buf.plane, 0..) |*out, py| {
        const row = &rows[py];
        if (row.* == null) {
            if (keyed[py]) keyed[py] = false;
            if (!blank[py]) {
                @memset(out, 0);
                blank[py] = true;
                mark(py, 0, frame.PW);
            }
            continue;
        }
        const ln = &row.*.?;
        const k = &keys[py];
        // not addr: where the bytes are read from may flip every frame (double buffering);
        // what the cached bytes say is compared group by group in lineAt
        if (!keyed[py] or k.x0 != ln.x0 or k.lo != ln.lo or k.hi != ln.hi) {
            @memset(out, 0);
            blank[py] = false;
            k.* = .{ .addr = ln.addr, .x0 = ln.x0, .lo = ln.lo, .hi = ln.hi };
            keyed[py] = true;
            mark(py, 0, frame.PW);
            _ = lineAt(r, ln.*, out, &ram.buf.src[py], false);
        } else {
            const g = lineAt(r, ln.*, out, &ram.buf.src[py], true);
            if (g.first > g.last) continue;
            const x0 = ln.x0 + 16 * @as(i32, g.first);
            const x1 = ln.x0 + 16 * (@as(i32, g.last) + 1);
            mark(py, @intCast(std.math.clamp(x0, 0, frame.PW)), @intCast(std.math.clamp(x1, 0, frame.PW)));
        }
    }
}

fn mark(py: usize, lo: u16, hi: u16) void {
    span_lo[py] = @min(span_lo[py], lo);
    span_hi[py] = @max(span_hi[py], hi);
}

/// The first and last group a lineAt() converted (first > last: none). Two u16, not an
/// optional pair: an optional aggregate copied by value made misaligned wide accesses.
const Changed = extern struct { first: u16 = 0xFFFF, last: u16 = 0 };

inline fn add(c: *Changed, g: usize) void {
    c.first = @min(c.first, @as(u16, @intCast(g)));
    c.last = @max(c.last, @as(u16, @intCast(g)));
}

/// Convert the groups of `ln` into `out`; with `only_changed`, just those whose source
/// bytes differ from `cache` (returns which did). Pixels outside [lo, hi) and left of
/// the row's first byte stay as they are (colour 0).
fn lineAt(r: *const st.Ram, ln: Row, out: *[frame.PW]u8, cache: *[ram.SRC_ROW]u8, only_changed: bool) Changed {
    const gs = rows_.groups(ln) orelse return .{};
    const g0 = gs.lo;
    const a = ln.addr + 8 * @as(u32, @intCast(g0));
    const n = 8 * (gs.hi + 1 - g0);
    if (only_changed and r.holds(a) and r.holds(a + @as(u32, @intCast(n)) - 1)) {
        const bytes = r.bytes(a, n);
        if ((@intFromPtr(bytes.ptr) | @intFromPtr(cache)) & 3 == 0) return changedAligned(ln, g0, bytes, cache, out);
    }
    var changed: Changed = .{};
    for (g0..gs.hi + 1) |g| {
        const src = r.bytes(ln.addr + 8 * @as(u32, @intCast(g)), 8)[0..8];
        const c = cache[(g - g0) * 8 ..][0..8];
        const a0 = st.le32(src[0..4]); // a 230-byte line's groups sit at 2 mod 4: no lw there
        const a1 = st.le32(src[4..8]);
        const c0 = std.mem.readInt(u32, c[0..4], .little);
        const c1 = std.mem.readInt(u32, c[4..8], .little);
        if (only_changed and a0 == c0 and a1 == c1) continue;
        std.mem.writeInt(u32, c[0..4], a0, .little);
        std.mem.writeInt(u32, c[4..8], a1, .little);
        add(&changed, g);
        putGroup(ln, g, src, out);
    }
    return changed;
}

/// lineAt's compare where the row's bytes sit at 0 mod 4 (160-byte lines): two word
/// loads a side, no alignment test a long; the groups whose 8 bytes changed reconvert.
fn changedAligned(ln: Row, g0: usize, bytes: []const u8, cache: *[ram.SRC_ROW]u8, out: *[frame.PW]u8) Changed {
    const s: [*]const u32 = @ptrCast(@alignCast(bytes.ptr));
    const c: [*]u32 = @ptrCast(@alignCast(cache));
    var changed: Changed = .{};
    for (0..bytes.len / 8) |k| {
        if (s[2 * k] == c[2 * k] and s[2 * k + 1] == c[2 * k + 1]) continue;
        c[2 * k] = s[2 * k];
        c[2 * k + 1] = s[2 * k + 1];
        add(&changed, g0 + k);
        putGroup(ln, g0 + k, bytes[8 * k ..][0..8], out);
    }
    return changed;
}

fn putGroup(ln: Row, g: usize, src: *const [8]u8, out: *[frame.PW]u8) void {
    const xb = ln.x0 + 16 * @as(i32, @intCast(g));
    if (xb >= ln.lo and xb + 16 <= ln.hi) {
        st.groupToChunky(src, out[@intCast(xb)..][0..16]);
        return;
    }
    var group: [16]u8 = undefined;
    st.groupToChunky(src, &group);
    for (0..16) |i| {
        const x = xb + @as(i32, @intCast(i));
        if (x >= ln.lo and x < ln.hi) out[@intCast(x)] = group[i];
    }
}
