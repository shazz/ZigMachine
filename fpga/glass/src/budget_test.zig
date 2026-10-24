// The frame budget (budget.zig, page_budget.zig) from probe means as rno_natrium's on the board
// (2026-10-20 base run: frame 1,649,229, cart 686,334, seq 952,947, hbl 0, plan 0, passes 280,
// swap 546,827).
const std = @import("std");
const mc = @import("map_cart.zig");
const vstat = @import("vstat.zig");
const osd = @import("osd.zig");
const budget = @import("budget.zig");
const page = @import("page_budget.zig");

fn info(frame: u32, cart: u32, seq: u32, hbl: u32, plan: u32, passes: u32, swap: u32) vstat.Info {
    var i = vstat.Info{ .ok = true, .n = 16 };
    i.mean[mc.VS_FRAME - mc.VS_FRAME] = frame;
    i.mean[mc.VS_CART - mc.VS_FRAME] = cart;
    i.mean[mc.VS_SEQC - mc.VS_FRAME] = seq;
    i.mean[mc.VS_HBL - mc.VS_FRAME] = hbl;
    i.mean[mc.VS_PLAN - mc.VS_FRAME] = plan;
    i.mean[mc.VS_PASSES - mc.VS_FRAME] = passes;
    i.mean[mc.VS_SWAP - mc.VS_FRAME] = swap;
    return i;
}

const RNO = info(1_649_229, 686_334, 952_947, 0, 0, 280, 546_827);

test "a probe window splits into cart, FRESCO, handlers, other and the VBL wait" {
    const s = budget.sample(&RNO).?;
    try std.testing.expectEqual(@as(u32, 686_334), s.cart);
    try std.testing.expectEqual(@as(u32, 952_947 - 546_827), s.fresco);
    try std.testing.expectEqual(@as(u32, 546_827), s.idle);
    try std.testing.expectEqual(@as(u32, 1_649_229 - 686_334 - 952_947), s.other);
    try std.testing.expectEqual(@as(u32, 66), budget.percent(s)); // 1.10 Mc of the 1.67 Mc frame
    var b: [8]u8 = undefined;
    try std.testing.expectEqualStrings("1.0", budget.planesText(&b, s.passes));
    try std.testing.expectEqualStrings("0.69", budget.mcText(&b, s.cart));
}

test "no window yet: no sample, and the page says why" {
    try std.testing.expectEqual(@as(?budget.Sample, null), budget.sample(&vstat.Info{}));
    var o = osd.Osd{};
    page.draw(&o, &page.View{});
    var dump: [osd.ROWS * (osd.COLS + 1)]u8 = undefined;
    o.dump(&dump);
    try std.testing.expect(std.mem.indexOf(u8, &dump, "no video probe") != null);
}

test "a second of samples is averaged and the peak is the busiest of the last three" {
    var sm = budget.Smooth{};
    try std.testing.expectEqual(@as(?budget.Sample, null), sm.avg());
    for (0..budget.PEAK) |k| sm.push(.{ .cart = if (k == 3) 900_000 else 100_000 + @as(u32, @intCast(k % 2)) * 100_000 });
    try std.testing.expectEqual(@as(u32, 150_000), sm.avg().?.cart); // the newest 10 alternate 100 K / 200 K
    try std.testing.expectEqual(@as(u32, 900_000), sm.peak().cart);
    sm.reset();
    try std.testing.expectEqual(@as(?budget.Sample, null), sm.avg());
}

test "the bar is the frame in 1/16 cells: cart, FRESCO, other, then the VBL wait" {
    var bar: [osd.COLS]u8 = undefined;
    page.barText(&bar, budget.sample(&RNO).?);
    // 0.69 / 0.41 / 0.01 / 0.55 Mc, each boundary rounded to the nearest of 104 Kc: a whole 60 fps frame
    try std.testing.expectEqualStrings("CCCCCCCFFFo.....", bar[0..16]);
    try std.testing.expectEqual(@as(u8, ' '), bar[16]);
}

test "the page: numbers, planes, headroom at 60 fps, and an over-budget frame says by how much" {
    var o = osd.Osd{};
    const s = budget.sample(&RNO).?;
    page.draw(&o, &page.View{ .avg = s, .peak = s, .fps_x10 = 602, .frames = 60, .missed = 0 });
    var dump: [osd.ROWS * (osd.COLS + 1)]u8 = undefined;
    o.dump(&dump);
    for ([_][]const u8{ "cart   0.69 Mc", "FRESCO 0.41 Mc  1.0 planes", "fps    60.2  missed 0/60", "cart may spend ~1.25 Mc", "60fps^" }) |want| {
        if (std.mem.indexOf(u8, &dump, want) == null) {
            std.debug.print("missing \"{s}\" in:\n{s}", .{ want, dump });
            return error.TestExpectedEqual;
        }
    }
    const heavy = budget.Sample{ .cart = 3_000_000, .fresco = 1_200_000, .hbl = 300_000, .other = 300_000 };
    page.draw(&o, &page.View{ .avg = heavy, .peak = heavy });
    o.dump(&dump);
    try std.testing.expect(std.mem.indexOf(u8, &dump, "60 fps: over by 0.13 Mc") != null);
}
