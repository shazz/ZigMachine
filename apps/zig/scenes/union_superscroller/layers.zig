// --------------------------------------------------------------------------
// TCB2 SUPERSCROLLER layers: what in the picture never changes.
//
// The back and the overlay ride together (screen.js: both at Y1, both at Y2),
// so a row Chrome draws from image rows r and r+1 (or r alone) with weight w
// colours its pixel x from (w, back[r][x], back[r+1][x], overlay[r][x],
// overlay[r+1][x]) only: a 10-bit KEY, with w the only thing the frame adds.
// A letter's ink shows (w, the raster colour, the two overlay taps). Which key
// each pixel has is fixed at load time, so this builds, for both tap modes and
// every image row, a palette ENTRY per key that is the same on every frame:
//
//   - a key present on row r-1 keeps its entry on row r, so the HBL writes only
//     the entries whose key is new on that line (rowpal.zig), ~7 a line;
//   - the row is written out twice as 320 entry bytes: L (no ink) and LI (ink),
//     and a frame is a CHISEL blit of L rows plus the letters copied from LI;
//   - F[w][key] holds every key's colour at every weight, from
//     compose.pairedColour, the per-pixel path's colour() in scalars.
//
// The entry order is NOT the first-appearance order the per-pixel path hands
// out. The picture is the RGBA each pixel composites to (scene_hash hashes
// hwRenderPlane; the harness compares colours), so any entry <-> colour pairing
// per line is the same picture. Keys are canonical: where both overlay taps are
// opaque the back does not show (srcOver at alpha 255 adds d >> 8 = 0), so such
// keys carry back = 0, and such ink pixels take the no-ink entry.
//
// Built while the picture loads: a row as soon as its overlay bytes are
// depacked (the back comes first, the overlay streams in over 46 frames), the
// colours once their bytes are in (assets.LAYER_BYTES): about 40 Mc in all,
// far too much for one frame.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const compose = @import("compose.zig");
const E = @import("entries.zig");

pub const Mode = enum(u1) { same = 0, pair = 1 };
pub const MAX_NI = 64; // canonical no-ink keys a row: 52 measured (pair mode)
pub const MAX_INK = 16; // raster-dependent ink keys a row: 9 measured
/// Entries 1..POOL; the most keys one row holds is 61 (python over the .bin).
pub const POOL = 96;
const WEIGHTS = 16;
/// step() units: a weight of F counts this many image rows.
const COLOUR_UNIT = 2;
pub const UNITS = WEIGHTS * COLOUR_UNIT + 2 * A.H;

pub const RowKeys = struct {
    n_new: u8, // ni[0..n_new]: keys not on the row above (same mode)
    n_all: u8,
    n_ink: u8,
    ni_entry: [MAX_NI]u8,
    ni_key: [MAX_NI]u16,
    ink_entry: [MAX_INK]u8,
    ink_key: [MAX_INK]u8,
};

pub const Tables = struct {
    f: [WEIGHTS][1024]u32,
    l: [2][A.H][A.W]u8 align(4),
    li: [2][A.H][A.W]u8 align(4),
    rows: [2][A.H]RowKeys,
    builder: Builder,

    pub fn image(self: *const Tables, which: *const [2][A.H][A.W]u8, mode: Mode) []const u8 {
        _ = self;
        return @as(*const [2 * A.H * A.W]u8, @ptrCast(which))[@intFromEnum(mode) * A.H * A.W ..][0 .. A.H * A.W];
    }
};

pub const Progress = enum { more, done, failed };

pub const Builder = struct {
    same: ModeState = .{},
    pair: ModeState = .{},
    w: usize = 0,

    const ModeState = struct { r: usize = 0, assign: E.Assign = .{} };

    /// Up to `budget` units of what the first `written` depacked bytes allow;
    /// .failed when a row holds more keys than the lists take.
    pub fn step(self: *Builder, t: *Tables, img: *const A.Images, written: usize, budget: usize) Progress {
        var n = budget;
        inline for (.{ Mode.same, Mode.pair }) |mode| {
            const ms = if (mode == .same) &self.same else &self.pair;
            while (n > 0 and ms.r < A.H and rowReady(mode, ms.r, written)) : (n -= 1) {
                if (!buildRow(t, img, &ms.assign, mode, ms.r)) return .failed;
                ms.r += 1;
            }
        }
        while (n >= COLOUR_UNIT and self.w < WEIGHTS and written >= A.LAYER_BYTES) : (n -= COLOUR_UNIT) {
            for (&t.f[self.w], 0..) |*c, key| c.* = compose.pairedColour(img, @intCast(self.w), @intCast(key));
            self.w += 1;
        }
        return if (self.same.r == A.H and self.pair.r == A.H and self.w == WEIGHTS) .done else .more;
    }

    fn rowReady(mode: Mode, r: usize, written: usize) bool {
        const last = if (mode == .pair) @min(r + 1, A.H - 1) else r;
        return written >= A.W * A.H + A.W * (last + 1);
    }
};

fn niKey(b0: u8, b1: u8, o0: u8, o1: u8) u16 {
    const back: u16 = if (o0 != 0 and o1 != 0) 0 else @as(u16, b0) | (@as(u16, b1) << 2);
    return back | (@as(u16, o0) << 4) | (@as(u16, o1) << 7);
}

fn buildRow(t: *Tables, img: *const A.Images, a: *E.Assign, mode: Mode, r: usize) bool {
    const m = @intFromEnum(mode);
    const r1 = if (mode == .pair) @min(r + 1, A.H - 1) else r;
    const back0 = img.back[r * A.W ..][0..A.W];
    const back1 = img.back[r1 * A.W ..][0..A.W];
    const over0 = img.overlay[r * A.W ..][0..A.W];
    const over1 = img.overlay[r1 * A.W ..][0..A.W];
    a.nextRow();
    var keys: [MAX_NI + MAX_INK]u16 = undefined;
    var nk: usize = 0;
    for (0..A.W) |x| {
        const k = niKey(back0[x], back1[x], over0[x], over1[x]);
        if (!E.note(a, &keys, &nk, k)) return false;
        if (over0[x] == 0 or over1[x] == 0)
            if (!E.note(a, &keys, &nk, E.INK_TAG | (k >> 4))) return false;
    }
    if (!E.assign(a, keys[0..nk], &t.rows[m][r])) return false;
    // Four entries to a word: on the board a store costs the same at any width.
    const lw: *[A.W / 4]u32 = @ptrCast(&t.l[m][r]);
    const liw: *[A.W / 4]u32 = @ptrCast(&t.li[m][r]);
    for (lw, liw, 0..) |*l4, *li4, wi| {
        var l: u32 = 0;
        var li: u32 = 0;
        inline for (0..4) |j| {
            const x = 4 * wi + j;
            const k = niKey(back0[x], back1[x], over0[x], over1[x]);
            const ink_e = if (over0[x] != 0 and over1[x] != 0) a.entry_of[k] else a.entry_of[E.INK_TAG | (k >> 4)];
            l |= @as(u32, a.entry_of[k]) << (8 * j);
            li |= @as(u32, ink_e) << (8 * j);
        }
        l4.* = l;
        li4.* = li;
    }
    return true;
}
