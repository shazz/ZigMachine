// Native tests: `zig test balloid_test.zig -lc`. Optional PPM dumps for eyeballing go to
// $BALLOID_PPM_DIR when set (nothing is written otherwise).
const std = @import("std");
const B = @import("balloid.zig");

const W = 320;
const H = 200;
const SENT: u16 = 0x1234;

var fb: [W * H]u16 align(4) = undefined;

fn fresh() [*]align(4) u16 {
    @memset(&fb, SENT);
    return &fb;
}

fn outsideUntouched(x0: usize, y0: usize, x1: usize, y1: usize) bool {
    for (0..H) |y| for (0..W) |x| {
        const inside = x >= x0 and x < x1 and y >= y0 and y < y1;
        if (!inside and fb[y * W + x] != SENT) return false;
    };
    return true;
}

fn countNot(colour: u16) usize {
    var n: usize = 0;
    for (fb) |p| n += @intFromBool(p != colour and p != SENT);
    return n;
}

test "sine table quadrants" {
    B.init();
    try std.testing.expectEqual(@as(i16, 0), B.sin_tbl[0]);
    try std.testing.expectEqual(@as(i16, 32767), B.sin_tbl[512]);
    try std.testing.expectEqual(@as(i16, 0), B.sin_tbl[1024]);
    try std.testing.expectEqual(@as(i16, -32767), B.sin_tbl[1536]);
}

test "topology: 402 vertices, 410 faces, indices in range" {
    B.init();
    try std.testing.expectEqual(402, B.NVERT);
    try std.testing.expectEqual(410, B.NFACE);
    var tris: usize = 0;
    for (B.faces) |f| {
        for (f[0..3]) |i| try std.testing.expect(i < B.NVERT);
        tris += @intFromBool(f[3] == 0xFFFF);
    }
    try std.testing.expectEqual(20, tris);
}

test "orange at full zoom: box only, a filled ball" {
    B.init();
    var b = B.Balloid.start(.orange, null);
    b.advance(600); // z reaches 300
    try std.testing.expectEqual(300, b.z);
    b.draw(fresh(), W);
    try std.testing.expect(outsideUntouched(90, 30, 230, 170));
    try std.testing.expect(countNot(0) > 3000);
    try dump("orange_full");
}

test "orange zooms from far: small at the start" {
    B.init();
    var b = B.Balloid.start(.orange, null);
    b.draw(fresh(), W);
    const far = countNot(0);
    b.advance(600);
    b.draw(fresh(), W);
    try std.testing.expect(far * 4 < countNot(0));
}

test "grey: draws only in its right-half box" {
    B.init();
    var b = B.Balloid.start(.grey, null);
    b.advance(333);
    b.draw(fresh(), W);
    try std.testing.expect(outsideUntouched(160, 25, 320, 175));
    try std.testing.expect(countNot(0xFFFF) > 3000);
    try dump("grey");
}

test "morph changes the picture" {
    B.init();
    var b = B.Balloid.start(.orange, null);
    b.advance(900);
    b.drawMorph(0, fresh(), W);
    const smooth = fb;
    try dump("orange_m0");
    b.drawMorph(511, fresh(), W);
    try dump("orange_m511");
    try std.testing.expect(!std.mem.eql(u16, &smooth, &fb));
    b.drawMorph(256, fresh(), W);
    try dump("orange_m256");
}

test "culling keeps the faces turned to the camera (t = 0: identity matrix)" {
    B.init();
    const b = B.Balloid.start(.grey, null);
    b.drawMorph(0, fresh(), W);
    const ring = 1 + 20 * B.LONS; // equator; lon 7..8 spans phi ~1433..1638 (z < 0, near)
    try std.testing.expect(B.front(ring + 7, ring + B.LONS + 7, ring + B.LONS + 8));
    try std.testing.expect(!B.front(ring + 2, ring + B.LONS + 2, ring + B.LONS + 3));
}

test "a run of frames, one a second (dumped only when BALLOID_PPM_DIR is set)" {
    B.init();
    var b = B.Balloid.start(.orange, null);
    var name_buf: [16]u8 = undefined;
    for (0..8) |s| {
        b.draw(fresh(), W);
        try std.testing.expect(outsideUntouched(90, 30, 230, 170));
        try dump(try std.fmt.bufPrint(&name_buf, "seq{d}", .{s}));
        b.advance(200);
    }
}

test "sweep: every pose and morph stays in its box, no overflow trap (safety-checked build)" {
    B.init();
    for ([_]B.Kind{ .orange, .grey }) |k| {
        var b = B.Balloid.start(k, null);
        var i: u32 = 0;
        while (i < 160) : (i += 1) {
            b.advance(53); // odd step: walks every angle combination over ~42 s
            b.draw(fresh(), W);
            if (k == .orange) {
                try std.testing.expect(outsideUntouched(90, 30, 230, 170));
            } else try std.testing.expect(outsideUntouched(160, 25, 320, 175));
        }
    }
}

test "about half the faces are visible (cost: triangle setups per frame)" {
    B.init();
    var b = B.Balloid.start(.orange, null);
    b.advance(777);
    b.draw(fresh(), W);
    var tris: usize = 0;
    for (B.faces) |f| {
        tris += @intFromBool(B.front(f[0], f[1], f[2]));
        tris += @intFromBool(f[3] != 0xFFFF and B.front(f[0], f[2], f[3]));
    }
    std.debug.print("front triangles {d} of 800, pixels {d}\n", .{ tris, countNot(0) });
    try std.testing.expect(tris > 300 and tris < 500);
}

test "a ripped env map is used when given" {
    B.init();
    const red = [_]u16{0xF800} ** 4096;
    var b = B.Balloid.start(.orange, &red);
    b.advance(600);
    b.draw(fresh(), W);
    try std.testing.expect(countNot(0) > 3000);
    try dump("red");
    for (fb) |p| try std.testing.expect(p == 0 or p == 0xF800 or p == SENT);
}

fn dump(name: []const u8) !void {
    const dir = std.c.getenv("BALLOID_PPM_DIR") orelse return;
    var path_buf: [512]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&path_buf, "{s}/balloid_{s}.ppm", .{ std.mem.span(dir), name });
    const f = std.c.fopen(path, "wb") orelse return error.Open;
    defer _ = std.c.fclose(f);
    var hdr_buf: [32]u8 = undefined;
    const hdr = try std.fmt.bufPrint(&hdr_buf, "P6\n{d} {d}\n255\n", .{ W, H });
    _ = std.c.fwrite(hdr.ptr, 1, hdr.len, f);
    for (fb) |p| {
        const rgb = [3]u8{ @intCast((p >> 11) << 3), @intCast(((p >> 5) & 63) << 2), @intCast((p & 31) << 3) };
        _ = std.c.fwrite(&rgb, 1, 3, f);
    }
}
