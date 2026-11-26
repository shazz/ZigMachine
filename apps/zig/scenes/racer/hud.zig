// --------------------------------------------------------------------------
// RACER: two text lines in the viewport's bands (top rows 1..8, bottom rows 191..198), no plane
// of their own. Each page of the flip remembers what it shows and a line is redrawn only when its
// text changed for that page. The bench band (key O) is the OSD of PORT_PLAN 2.5: stage
// microseconds, the counts, fps, and the cart-only rate (1e6 / avg_us: the frame rate if only the cart's own work counted: it
// leaves out FRESCO's ~0.7 Mc, which the board frame waits for; a cart cannot skip the VBL wait today).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

const COLS = 40; // a multiple of 4: the lines stay word-aligned
const Line = [COLS]u8;
pub const HELP = "3-8 R  F FILL  M MUL  G F32  D DECAL  O OSD";

pub const Info = struct {
    track: []const u8,
    shade: []const u8 = "", // the debug shading's tag (key i), empty by default
    shadow: []const u8 = "", // the shadow's tag (key y): "/DITHER" for the checkerboard, empty for the default real shadow
    r: u32,
    cpu: bool,
    mul: []const u8,
    decals: bool,
    pov: []const u8,
    polys: u32,
    spans: u32,
    osd: bool,
    uncapped: bool,
    avg_us: u32,
    fps10: u32,
    stage_us: [6]u32,
    line0: ?[]const u8 = null, // the race's lines (racehud.zig) replace the benchmark's two
    line1: ?[]const u8 = null,
};

pub const Hud = struct {
    shown: [2][2]Line align(4) = .{ .{ [_]u8{0} ** COLS, [_]u8{0} ** COLS }, .{ [_]u8{0} ** COLS, [_]u8{0} ** COLS } },
    ink: u8 = 3,
    paper: u8 = 2,

    pub fn draw(self: *Hud, os: *zg.ZigOS, fb: *zg.LogicalFB, plane: usize, i: Info) void {
        var l: [2]Line align(4) = undefined;
        var b0: [64]u8 = undefined;
        pad(&l[0], i.line0 orelse std.fmt.bufPrint(&b0, "{s}{s}{s} R{} {s} {s}{s} {s} P{} S{}", .{
            i.track, i.shade, i.shadow, i.r, if (i.cpu) "CPU" else "AFFINE", i.mul, if (i.decals) "" else " NODECAL", i.pov, i.polys, i.spans,
        }) catch "");
        var b1: [96]u8 = undefined;
        pad(&l[1], if (i.osd) (if (i.uncapped) bufUncapped(&b1, i) else bufStages(&b1, i)) else i.line1 orelse HELP);
        const ys = [2]i16{ 2, 191 };
        for (0..2) |k| {
            if (std.mem.eql(u8, &l[k], &self.shown[plane][k])) continue;
            self.shown[plane][k] = l[k];
            os.printText(fb, &l[k], 0, ys[k], self.ink, self.paper);
        }
    }
};

fn bufStages(b: []u8, i: Info) []const u8 {
    const s = i.stage_us;
    return std.fmt.bufPrint(b, "V{} C{} S{} K{} F{} H{} = {}US {}.{}FPS", .{ s[0], s[1], s[2], s[3], s[4], s[5], i.avg_us, i.fps10 / 10, i.fps10 % 10 }) catch "";
}

fn bufUncapped(b: []u8, i: Info) []const u8 {
    const eq: u32 = if (i.avg_us == 0) 0 else 1_000_000 / i.avg_us;
    return std.fmt.bufPrint(b, "CART-ONLY {} FPS  ({}US A FRAME)", .{ eq, i.avg_us }) catch "";
}

fn pad(dst: *Line, text: []const u8) void {
    const n = @min(text.len, COLS);
    @memcpy(dst[0..n], text[0..n]);
    @memset(dst[n..], ' ');
}
