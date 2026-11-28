// RACER: the course select's baked model (coursemesh.zig) and the garage's list (garage.zig), board batch items 9 and 7/10.
const std = @import("std");
const cm = @import("coursemesh.zig");
const data = @import("data.zig");
const garage = @import("garage.zig");
const trk = @import("trk.zig");

test "the oval's model: cells filled with its own ramps, the racing line inside the grid, every polygon on screen" {
    const t = try trk.parse(data.oval);
    const m = cm.bake(&t);
    var filled: usize = 0;
    for (m.cell) |c| if (c != cm.EMPTY) {
        filled += 1;
        try std.testing.expect(c >> 3 < m.nr);
    };
    try std.testing.expect(filled >= 2 * cm.N and m.nr >= 1 and m.nr <= cm.MAXR); // the oval is a ring of road: 36 of 144
    try std.testing.expectEqual(@as(u8, cm.PTS), m.n);
    for (m.line) |p| try std.testing.expect(p[0] <= cm.N * 16 and p[2] <= cm.N * 16);
    var out: [cm.MAXP]cm.Poly = undefined;
    for ([_]u32{ 0, 0x4000_0000, 0x9000_0000 }) |turn| {
        const ps = cm.polys(&m, turn, &out);
        try std.testing.expectEqual(filled, ps.len);
        for (ps) |p| for (0..4) |k| {
            try std.testing.expect(p.x[k] >= 0 and p.x[k] < 320 and p.y[k] >= 12 and p.y[k] < 188);
            try std.testing.expect(p.depth > 0);
            try std.testing.expect(p.colour >= 16 and p.colour < 16 + 8 * cm.MAXR);
        };
    }
}

test "the model turns: a quarter turn moves the cells, a whole turn brings them back" {
    const t = try trk.parse(data.oval);
    const m = cm.bake(&t);
    var a: [cm.MAXP]cm.Poly = undefined;
    var b: [cm.MAXP]cm.Poly = undefined;
    const p0 = cm.polys(&m, 0, &a);
    const p1 = cm.polys(&m, 0x4000_0000, &b);
    try std.testing.expect(!std.mem.eql(i16, &p0[0].x, &p1[0].x));
    const p2 = cm.polys(&m, 0, &b); // 2^32: the same as 0
    try std.testing.expectEqualSlices(i16, &p0[0].x, &p2[0].x);
}

test "a track with no racing line bakes an empty model (nothing drawn, no division by zero)" {
    var t = try trk.parse(data.oval);
    t.line = t.line[0..1];
    const m = cm.bake(&t);
    try std.testing.expectEqual(@as(u8, 0), m.nr);
    var out: [cm.MAXP]cm.Poly = undefined;
    try std.testing.expectEqual(@as(usize, 0), cm.polys(&m, 0, &out).len);
    try std.testing.expectEqual(@as(usize, 0), cm.ribbon(&m, 0, 10, &out).len);
}

test "the garage: files listed once (any case), the GT last, the step wraps both ways, a 9th file dropped and counted" {
    var g = garage.Garage{};
    g.add("CAR.KCR");
    g.add("STOCK.KCR");
    g.add("car.kcr"); // already listed (the disk's wins over C:'s)
    g.add("");
    try std.testing.expectEqual(@as(usize, 3), g.count());
    try std.testing.expect(g.isGt(2) and !g.isGt(1));
    try std.testing.expectEqualStrings("STOCK.KCR", g.file(1));
    try std.testing.expectEqualStrings("", g.file(2));
    try std.testing.expectEqual(@as(usize, 1), g.step(0, 1));
    try std.testing.expectEqual(@as(usize, 0), g.step(2, 1)); // the GT -> the first file
    try std.testing.expectEqual(@as(usize, 2), g.step(0, -1));
    try std.testing.expectEqual(@as(usize, 1), g.indexOf("stock.kcr"));
    try std.testing.expectEqual(@as(usize, 2), g.indexOf("")); // the GT
    for (0..garage.MAX + 1) |i| {
        var nb: [12]u8 = undefined;
        g.add(std.fmt.bufPrint(&nb, "C{}.KCR", .{i}) catch unreachable);
    }
    try std.testing.expectEqual(@as(usize, garage.MAX), g.n);
    try std.testing.expect(g.dropped >= 1);
}
