// --------------------------------------------------------------------------
// TRI TEST: CHISEL's TRIANGLE against the machine model, by eye on the board.
// Every triangle is a raw TRIANGLE op (clip rect on, never above the label rows); after
// drawing, the CPU hashes the plane's drawing area (FNV-1a) and the label shows the hash next
// to the golden one the browser's model gives (apps/tri_test_check.mjs proves both against a
// rasteriser of its own): OK or BAD. Matt compares two bitstreams by reading OK on each.
//   1  set A: the edge cases (tri_test/cases.zig EDGES) + 160 seeded triangles, XORed
//   2  set B: the stress run: 48 seeded triangles a frame for 300 frames, every frame's hash
//      folded into one; it stops on the last frame with the verdict
// Keys come in through setShadeMode (digit - 1). The hwBlit is synchronous: on the board it
// invalidates the D-cache lines CHISEL wrote, so the CPU's hash reads CHISEL's pixels.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const hw = @import("hardware");
const cases = @import("tri_test/cases.zig");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

/// The model's hashes (apps/tri_test_check.mjs recomputes both from its own rasteriser).
pub const GOLDEN_A: u32 = 0x00000000;
pub const GOLDEN_B: u32 = 0x00000000;

const PLANE = 0;
const W = 320;
const INK: u8 = 15;
const BG: u8 = 0;

pub const Demo = struct {
    mode: u8, // 0 set A, 1 set B
    frame: u32, // set B's frame
    hash: u32, // set A's, or set B's running fold
    drawn: bool, // set A is drawn once

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.* = .{ .mode = 0, .frame = 0, .hash = 0, .drawn = false };
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        for (0..16) |i| { // a ramp of distinct hues, so XORed overlaps read
            const k: u8 = @intCast(i);
            fb.setPaletteEntry(k, Color{ .r = k *% 97 +% 40, .g = k *% 53 +% 20, .b = k *% 29 +% 60, .a = 255 });
        }
        fb.setPaletteEntry(BG, Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        fb.setPaletteEntry(INK, Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
    }

    pub fn setShadeMode(self: *Demo, mode: u32) void {
        if (mode > 1) return;
        self.* = .{ .mode = @intCast(mode), .frame = 0, .hash = 0, .drawn = false };
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        if (self.mode == 0) {
            if (self.drawn) return;
            self.drawn = true;
            clearArea(fb);
            for (cases.EDGES) |tri| draw(fb, tri, hw.MT_B);
            var r = cases.Rng{ .s = cases.SEED_A };
            for (0..cases.RANDOM_A) |_| draw(fb, cases.random(&r), hw.MT_XOR_BC);
            self.hash = hashArea(fb);
            label(zigos, fb, "SET A  EDGES", self.hash, GOLDEN_A, true);
            return;
        }
        if (self.frame >= cases.STRESS_FRAMES) return; // frozen on the last frame, verdict shown
        clearArea(fb);
        var r = cases.Rng{ .s = 0x5EED0000 +% self.frame };
        for (0..cases.STRESS_PER_FRAME) |_| draw(fb, cases.random(&r), hw.MT_XOR_BC);
        self.hash = fold(self.hash, hashArea(fb));
        self.frame += 1;
        var buf: [24]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "SET B  {d}/{d}", .{ self.frame, cases.STRESS_FRAMES }) catch "SET B";
        label(zigos, fb, name, self.hash, GOLDEN_B, self.frame == cases.STRESS_FRAMES);
    }
};

inline fn reg8(off: usize, v: u8) void {
    @as(*volatile u8, @ptrFromInt(@as(usize, @intCast(hw.hwVideoBase())) + off)).* = v;
}
inline fn reg16(off: usize, v: i16) void {
    @as(*volatile u16, @ptrFromInt(@as(usize, @intCast(hw.hwVideoBase())) + off)).* = @bitCast(v);
}
inline fn reg32(off: usize, v: u32) void {
    @as(*volatile u32, @ptrFromInt(@as(usize, @intCast(hw.hwVideoBase())) + off)).* = v;
}

fn dest(fb: *zg.LogicalFB) void {
    reg32(hw.BLIT_D_BASE, @intCast(@intFromPtr(fb.fb) - @as(usize, @intCast(hw.hwVideoBase()))));
    reg16(hw.BLIT_D_STRIDE, @bitCast(fb.stride));
    reg8(hw.BLIT_CON2, 0); // no halftone, no stale CHISEL v2 bits
}

fn draw(fb: *zg.LogicalFB, tri: cases.Tri, mt: u8) void {
    dest(fb);
    reg8(hw.BLIT_CON, hw.CON_CLIP_EN);
    for (tri.clip, [_]usize{ hw.BLIT_CLIP_X, hw.BLIT_CLIP_Y, hw.BLIT_CLIP_W, hw.BLIT_CLIP_H }) |v, off| reg16(off, v);
    reg8(hw.BLIT_MINTERM, mt);
    reg8(hw.BLIT_COLOR, tri.color);
    const offs = [_]usize{ hw.BLIT_X0, hw.BLIT_Y0, hw.BLIT_X1, hw.BLIT_Y1, hw.BLIT_X2, hw.BLIT_Y2 };
    for (tri.v, offs) |v, off| reg16(off, v);
    reg8(hw.BLIT_COMMAND, hw.BLIT_CMD_TRIANGLE);
    hw.hwBlit();
}

/// The drawing area to 0 with a FILL (CHISEL's own pixels: no CPU store to order against it).
fn clearArea(fb: *zg.LogicalFB) void {
    dest(fb);
    reg8(hw.BLIT_CON, 0);
    reg8(hw.BLIT_COLOR, BG);
    reg16(hw.BLIT_X0, 0);
    reg16(hw.BLIT_Y0, cases.LABEL_ROWS);
    reg16(hw.BLIT_W, W);
    reg16(hw.BLIT_H, 200 - cases.LABEL_ROWS);
    reg8(hw.BLIT_COMMAND, hw.BLIT_CMD_FILL);
    hw.hwBlit();
}

/// FNV-1a over rows LABEL_ROWS..199, a word at a time (4-aligned rows: no misaligned load).
fn hashArea(fb: *zg.LogicalFB) u32 {
    var h: u32 = 0x811C9DC5;
    const rows: [*]const u32 = @ptrCast(@alignCast(fb.fb + @as(usize, cases.LABEL_ROWS) * fb.stride));
    for (0..(200 - cases.LABEL_ROWS) * W / 4) |i| h = (h ^ rows[i]) *% 0x01000193;
    return h;
}

fn fold(h: u32, v: u32) u32 {
    return (h ^ v) *% 0x01000193;
}

fn label(zigos: *ZigOS, fb: *zg.LogicalFB, name: []const u8, hash: u32, golden: u32, final: bool) void {
    var buf: [40]u8 = undefined;
    const verdict = if (!final) "..." else if (hash == golden) "OK" else "BAD";
    const line = std.fmt.bufPrint(&buf, "{s}  {X:0>8}  {s}", .{ name, hash, verdict }) catch "?";
    for (0..cases.LABEL_ROWS) |y| @memset(fb.fb[y * fb.stride ..][0..W], BG);
    zigos.printText(fb, "TRI TEST  1 EDGES  2 STRESS", 4, 0, INK, BG);
    zigos.printText(fb, line, 4, 8, INK, BG);
}
