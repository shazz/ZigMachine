// sprite_draw.plot against the original Sprite.render pixel loop, kept verbatim
// below (oldPlot): same bytes in the target for every combination of
// transparency, y table, x table and left/right clamp, from a noisy start.
const std = @import("std");
const draw = @import("sprite_draw.zig");

fn oldPlot(j: draw.Job) void {
    var offset = j.offset;
    var data_counter = j.data_counter;
    var row_counter: u16 = 0;
    const is_tranparent = j.skip != draw.NO_SKIP;
    const transparent_color: u8 = if (is_tranparent) @intCast(j.skip) else 0;
    while (row_counter < j.rows) : (row_counter += 1) {
        var col_counter: u16 = 0;
        while (col_counter < j.nb_cols) : (col_counter += 1) {
            var new_offset = offset;
            if (j.y_table) |y_table| {
                var counter: u16 = col_counter + j.left_x_position + j.y_index;
                if (counter >= y_table.len) counter -= @as(u16, @intCast(y_table.len));
                const off = y_table[counter];
                if (off < 0) {
                    new_offset -= (@as(u16, @intCast(-off)) * j.screen_width);
                } else {
                    new_offset += (@as(u16, @intCast(off)) * j.screen_width);
                }
            }
            const pal_entry = j.data[data_counter];
            if (!is_tranparent or pal_entry != transparent_color) {
                j.out[new_offset + col_counter] = j.data[data_counter];
            }
            data_counter += 1;
        }
        if (j.right_clamp == true) data_counter += (j.width - j.nb_cols - j.left_x_clamped);
        if (j.left_clamp == true) data_counter += j.left_x_clamped;
        if (j.x_table) |table| {
            const delta: i16 = table[(j.x_index + row_counter) % table.len];
            if (delta < 0) {
                offset = offset - @as(u16, @intCast(-delta)) + j.screen_width;
            } else {
                offset = offset + @as(u16, @intCast(delta)) + j.screen_width;
            }
        } else {
            offset += j.screen_width;
        }
    }
}

const SW = 40;
const SH = 30;

test "plot leaves the target as the original loop did" {
    var prng = std.Random.DefaultPrng.init(0x5eed);
    const rnd = prng.random();
    var data: [16 * 8]u8 = undefined;
    var y_tab: [64]i16 = undefined;
    var x_tab: [5]i16 = undefined;
    var a: [SW * SH]u8 = undefined;
    var b: [SW * SH]u8 = undefined;
    for (0..400) |round| {
        for (&data) |*d| d.* = if (rnd.boolean()) 0 else rnd.int(u8) | 1;
        for (&y_tab) |*t| t.* = rnd.intRangeAtMost(i16, -3, 4);
        for (&x_tab) |*t| t.* = rnd.intRangeAtMost(i16, -2, 2);
        for (&a) |*p| p.* = if (rnd.boolean()) rnd.int(u8) else 0;
        b = a;
        const width: u16 = rnd.intRangeAtMost(u16, 8, 16);
        const clamp = rnd.intRangeAtMost(u16, 0, 3); // columns lost on the left
        const rclamp = rnd.intRangeAtMost(u16, 0, 3); // ... and on the right
        const left_x: u16 = rnd.intRangeAtMost(u16, 0, 12);
        const nb: u16 = width - clamp - rclamp;
        const use_y = rnd.boolean();
        const use_x = rnd.boolean();
        const job = draw.Job{
            .out = &a,
            .data = &data,
            .data_counter = clamp,
            .offset = left_x + rnd.intRangeAtMost(u16, 4, 8) * SW,
            .rows = rnd.intRangeAtMost(u16, 1, 8),
            .nb_cols = nb,
            .width = width,
            .screen_width = SW,
            .left_x_position = left_x,
            .left_x_clamped = clamp,
            .left_clamp = clamp > 0,
            .right_clamp = rclamp > 0,
            .skip = draw.skipOf(if (round % 3 == 0) null else if (round % 3 == 1) 0 else 7),
            .y_table = if (use_y) &y_tab else null,
            .y_index = rnd.intRangeAtMost(u16, 0, 63),
            .x_table = if (use_x) &x_tab else null,
            .x_index = rnd.intRangeAtMost(u16, 0, 9),
        };
        draw.plot(job);
        var old = job;
        old.out = &b;
        oldPlot(old);
        try std.testing.expectEqualSlices(u8, &b, &a);
    }
}
