// --------------------------------------------------------------------------
// Union main -- tile rows 3..7 (plane rows 83..163) out of a ring.
//
// world_draw.world() drew every map cell of the 25 visible columns each frame,
// keyed over rows erased to 0: about 62 of the ~64 cell blits a frame sit in
// these five rows (rows 6 and 7 are full), plus the 400 x 80 erase. Their
// background is plain 0 (the parallax and the floor are outside them), so an
// OPAQUE copy of a picture that holds the cells over 0 is the same pixels.
// That picture is a ring of 64 cell slots on plane 2 (never enabled: a blit
// writes video memory, FRESCO never composes it): the slot of virtual column
// v is v mod 64, and the ring keeps
//   slots V .. V+24  = map columns abs .. abs+24 (V is abs's slot),
//   every other slot = 0,
// so the 400-px window from ring pixel 16 V + sub - 8 is exactly the screen
// row: cell vc at x = 8 + 16 vc - sub, and 0 where world() drew nothing (left
// of 8 - sub, right of 408 - sub). One or two copies a frame (the window wraps
// the ring); when abs moves on, the slot that left is zeroed and the column
// that came in is drawn (empty cells are already 0): ~3.5 ops every 3.3 frames.
// The ring is another plane than P0: no copy within one plane.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;
const cells = @import("world_cells.zig");

pub const ROW0: usize = 3; // first map row held (plane row 35 + 3 * 16 = 83)
pub const ROW1: usize = 8; // one past the last (plane row 163)
pub const TOP: i16 = cells.TOP + @as(i16, ROW0) * 16;
const H: u16 = (ROW1 - ROW0) * 16;
const SLOTS: u32 = 64;
const RW: u16 = SLOTS * 16; // 1024 px
const VIS: usize = 25; // world_draw.VIS_COLS
const VIEW_W: u16 = 400; // the plane's width (PHYSICAL_WIDTH)
const DST_X: i32 = 8; // world_draw.DST_X
pub const WRAP: usize = 778; // main.zig SCROLL_WRAP: abs jumps from 777 to 0

var chisel: zg.Blitter = .{};

pub const Ring = struct {
    plane: ?*LogicalFB = null,
    v: u32 = 0, // virtual column (slot v mod 64) of map column `abs`
    abs: usize = 0,
    built: bool = false,
    zeroed: bool = false, // the ring reads 0 everywhere (setScrollPlane cleared it)

    /// `plane` must stay disabled; its buffer is taken from VRAM here (call from main.init).
    pub fn init(self: *Ring, plane: *LogicalFB) void {
        chisel.init();
        plane.setScrollPlane(RW, H); // cleared to 0
        self.* = .{ .plane = plane, .zeroed = true };
    }

    /// Rows 83..162 of `fb` as world_draw.world() left them after the erase, for scroll
    /// column `abs` (floor of the position) and sub-cell offset `sub` (0..15).
    pub fn draw(self: *Ring, fb: *LogicalFB, abs: usize, sub: u16) void {
        const ring = self.plane orelse return;
        if (!self.built) {
            self.rebuild(ring, abs);
        } else if (abs != self.abs) {
            // speed is at most 0.3 tiles a frame: abs moves on by one, 777 -> 0 at the wrap
            if (abs == (self.abs + 1) % WRAP) self.advance(ring, abs) else self.rebuild(ring, abs);
        }
        const s: u32 = (self.v * 16 + sub + RW - DST_X) % RW;
        const first: u16 = @intCast(@min(@as(u32, VIEW_W), RW - s));
        chisel.blitCopy(fb, 0, TOP, ring, @intCast(s), 0, first, H);
        if (first < VIEW_W) chisel.blitCopy(fb, @intCast(first), TOP, ring, 0, 0, VIEW_W - first, H);
    }

    fn rebuild(self: *Ring, ring: *LogicalFB, abs: usize) void {
        if (!self.zeroed) chisel.clear(ring, 0); // the first build finds it clear: no 82K-px fill
        self.zeroed = false;
        self.abs = abs;
        for (0..VIS) |vc| drawColumn(ring, self.v +% @as(u32, @intCast(vc)), abs + vc);
        self.built = true;
    }

    // abs + 24 comes in at slot V + 25; slot V leaves (and must read 0 from now on).
    fn advance(self: *Ring, ring: *LogicalFB, abs: usize) void {
        chisel.fill(ring, @intCast((self.v % SLOTS) * 16), 0, 16, H, 0);
        self.v +%= 1;
        self.abs = abs;
        drawColumn(ring, self.v +% (VIS - 1), abs + VIS - 1);
    }
};

// Map column `col`'s cells of rows ROW0..ROW1 into the ring slot of virtual column `v`,
// which reads 0 (an empty cell stays 0).
fn drawColumn(ring: *LogicalFB, v: u32, col: usize) void {
    const x: i16 = @intCast((v % SLOTS) * 16);
    for (ROW0..ROW1) |r| {
        const id = cells.idAt(r, col);
        if (id == cells.NONE) continue;
        const y: i16 = @intCast((r - ROW0) * 16);
        chisel.blitImage(ring, x, y, &cells.sheet, 16, 0, @as(u16, id) * 16, 16, 16, null);
    }
}

comptime {
    // At the wrap the ring keeps its slots: the columns it already holds, map columns
    // 778..801, must be the ones the new window shows, 0..23 (the map's tail repeats its head).
    @setEvalBranchQuota(100_000);
    for (ROW0..ROW1) |r| for (0..VIS - 1) |k| {
        if (cells.idAt(r, WRAP + k) != cells.idAt(r, k)) @compileError("world_ring: the map's tail does not repeat its head");
    };
    if (WRAP + VIS - 1 > cells.W) @compileError("world_ring: abs + 24 runs off the map");
    if (VIS + 2 > SLOTS or VIEW_W + 16 > RW) @compileError("world_ring: the ring is too small for the window and its two empty slots");
}
