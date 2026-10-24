// --------------------------------------------------------------------------
// TCB #1's picture without reconverting it every frame. Its frame is the
// noise buffer seen from one of 16 bases (tcb1.zig), so through st_show every
// row's source bytes differ from the frame before and the whole 400x229
// fullscreen went through the shifter again each VBL (~2 Mc a frame). But the
// BYTES barely change: a VBL erases and redraws one 64x18 logo box. So the
// shifter's output is kept for the whole region instead: `chunky`, 16 indices
// for each 8-byte group at R0 + 8q, reconverted only where `shadow` (the bytes
// it was converted from) differs from the part's memory. A frame is then the
// rows copied out of it, four pixels a store.
//
// A 230-byte line starts at 2, 4 or 6 mod 8 too, and the shifter reads a group
// of four plane words from wherever the line starts, so such a group is planes
// 1..3 of mirror group q and plane 0 of group q+1: for p = (address mod 8) / 2,
//     index = (chunky[i] >> p | chunky[i + 16] << (4 - p)) & 15,
// four pixels at a time in one u32. Bit k of the index is plane word p+k.
//
// Rows outside the region fall back to st_show (covers()); nothing does today.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const show = @import("st_rows.zig"); // not st_show.zig: the native test runs this

const PW = show.PW;
const PH = show.PH;
/// The mirrored ST bytes: below the lowest base's first line (base - 46) to
/// past the highest's last group, plus a group for the next-group reads.
pub const R0: u32 = 0x6FF00;
pub const R1: u32 = 0x7DD00;
pub const BYTES: usize = R1 - R0;
pub const GROUPS: usize = BYTES / 8;
/// What the mirror takes: the chunky (2 indices a byte) and the shadow.
pub const NEED: usize = 2 * BYTES + BYTES;

pub const Mirror = struct {
    chunky: *align(4) [2 * BYTES]u8,
    shadow: *align(4) [BYTES]u8,
    built: bool, // false: the next sync converts every group
    rows: show.Rows, // the frame to show: tcb1_show fills it, capture() syncs to it

    /// `mem` holds NEED bytes, 4-aligned (ram.zig lends it).
    pub fn init(self: *Mirror, mem: []align(4) u8) void {
        self.chunky = mem[0 .. 2 * BYTES];
        self.shadow = @alignCast(mem[2 * BYTES ..][0..BYTES]);
        self.built = false;
    }

    /// Whether every group the rows read (and the next group of each, for the
    /// shifted ones) lies inside the region.
    pub fn covers(rows: *const show.Rows) bool {
        for (rows) |*row| {
            if (row.* == null) continue;
            const ln = &row.*.?;
            const g = show.groups(ln.*) orelse continue;
            const first = ln.addr & ~@as(u32, 7);
            if (first < R0 or first + 8 * @as(u32, @intCast(g.hi + 2)) > R1) return false;
        }
        return true;
    }

    /// The first capture after a load converts the whole region; later ones find
    /// it current, as touchBox() follows every VBL's writes into it.
    pub fn sync(self: *Mirror, r: *const st.Ram) void {
        if (!self.built) self.update(r, R0, R1, true);
        self.built = true;
    }

    /// After a VBL: the logo box ending at `end`, 18 lines of 40 bytes 230 apart --
    /// what $D7D8 erases and $D80C draws, the only bytes of the region a TCB #1 VBL
    /// writes (tcb1_mirror_test.zig runs the part against a whole-region sync).
    pub fn touchBox(self: *Mirror, r: *const st.Ram, end: u32) void {
        if (!self.built) return;
        for (0..18) |i| {
            const hi = end -% 230 * @as(u32, @intCast(i));
            self.update(r, hi -% 40, hi, false);
        }
    }

    /// Reconvert the groups of [lo, hi) (clipped to the region) whose bytes are not
    /// the shadow's; every group with `all`.
    fn update(self: *Mirror, r: *const st.Ram, lo: u32, hi: u32, all: bool) void {
        if (hi <= R0 or lo >= R1 or hi <= lo) return;
        const q0 = (@max(lo, R0) - R0) / 8;
        const q1 = (@min(hi, R1) - R0 + 7) / 8;
        const src: *align(4) const [BYTES]u8 = @alignCast(r.bytes(R0, BYTES)[0..BYTES]);
        const s: *const [BYTES / 4]u32 = @ptrCast(src);
        const d: *[BYTES / 4]u32 = @ptrCast(self.shadow);
        const chunky = self.chunky;
        for (q0..q1) |q| {
            if (!all and s[2 * q] == d[2 * q] and s[2 * q + 1] == d[2 * q + 1]) continue;
            d[2 * q] = s[2 * q];
            d[2 * q + 1] = s[2 * q + 1];
            st.groupToChunky(src[8 * q ..][0..8], chunky[16 * q ..][0..16]);
        }
    }

    /// The captured frame into the plane `fb` (PW x PH indices, 4-aligned). With
    /// `all` false the plane holds the previous present(): rows with no line stay
    /// as they were if they had none then either.
    pub fn present(self: *const Mirror, fb: []align(4) u8, all: bool, had: *[PH]bool) void {
        for (&self.rows, 0..) |*row, py| {
            const out: *align(4) [PW]u8 = @alignCast(fb[py * PW ..][0..PW]);
            if (row.* != null) {
                self.line(&row.*.?, out);
                had[py] = true;
            } else if (all or had[py]) {
                @memset(out, 0);
                had[py] = false;
            }
        }
    }

    /// One row: what st_show.lineAt makes of `ln` from a blank row. Pixels
    /// [xa, xb) show chunky index s0 + x (rotated by p planes); the words wholly
    /// inside go four pixels a load, the ragged ends pixel by pixel.
    fn line(self: *const Mirror, ln: *const show.Row, out: *align(4) [PW]u8) void {
        const g = show.groups(ln.*) orelse return @memset(out, 0);
        const xa: i32 = @max(@as(i32, ln.lo), ln.x0 + 16 * @as(i32, @intCast(g.lo)));
        const xb: i32 = @min(@as(i32, ln.hi), ln.x0 + 16 * @as(i32, @intCast(g.hi + 1)));
        const p: u5 = @intCast((ln.addr & 7) / 2);
        const s0: i32 = 2 * @as(i32, @intCast((ln.addr & ~@as(u32, 7)) - R0)) - ln.x0;
        const w: *[PW / 4]u32 = @ptrCast(out);
        // whole words [ka, kb), when the source is word-aligned with the plane
        const ka: usize = if (s0 & 3 == 0) @intCast(@divFloor(xa + 3, 4)) else PW / 4;
        const kb: usize = if (s0 & 3 == 0) @max(ka, @as(usize, @intCast(@divFloor(xb, 4)))) else PW / 4;
        for (0..ka) |k| w[k] = self.ragged(k, xa, xb, s0, p);
        if (kb > ka) {
            const c: [*]const u32 = @ptrCast(self.chunky);
            const src = c + @as(usize, @intCast(s0 + 4 * @as(i32, @intCast(ka)))) / 4;
            switch (p) {
                inline 0...3 => |pp| for (w[ka..kb], 0..) |*o, j| {
                    o.* = if (pp == 0) src[j] else ((src[j] >> pp) | (src[j + 4] << (4 - pp))) & 0x0F0F_0F0F;
                },
                else => unreachable,
            }
        }
        for (kb..PW / 4) |k| w[k] = self.ragged(k, xa, xb, s0, p);
    }

    /// Plane word k pixel by pixel: 0 outside [xa, xb).
    fn ragged(self: *const Mirror, k: usize, xa: i32, xb: i32, s0: i32, p: u5) u32 {
        const x: i32 = @intCast(4 * k);
        if (x + 4 <= xa or x >= xb) return 0;
        var v: u32 = 0;
        for (0..4) |j| {
            const xj = x + @as(i32, @intCast(j));
            if (xj >= xa and xj < xb) v |= @as(u32, self.pixel(@intCast(s0 + xj), p)) << @intCast(8 * j);
        }
        return v;
    }

    fn pixel(self: *const Mirror, i: usize, p: u5) u8 {
        const a: u32 = self.chunky[i];
        if (p == 0) return @intCast(a);
        const b: u32 = self.chunky[i + 16];
        return @intCast(((a >> p) | (b << (4 - p))) & 15);
    }
};
