// --------------------------------------------------------------------------
// The pixel loop of Sprite.render, without ZigOS so it can be tested natively
// (sprite_draw_test.zig keeps the original loop verbatim and compares).
//
// What changed from the original loop, with the bytes in the target the same:
//   - a pixel is stored only when the target does not already hold it. Every
//     store is a blocking DDR write on ZIGGY; a read hits the data cache. A
//     sprite redrawn over its own previous frame (a scroller letter, a logo)
//     rewrote mostly identical bytes;
//   - the y-offset table lookup (the same for every row of a column) is out of
//     the pixel loop: one u16 displacement per column, added with the same
//     wrap-around arithmetic.
// --------------------------------------------------------------------------
const MAX_COLS = 512;

pub const Job = struct {
    out: []u8, // the target's pixels, row stride `screen_width`
    data: []const u8, // the sprite's palette indices
    data_counter: u32, // first source pixel
    offset: u16, // first destination pixel
    rows: u16,
    nb_cols: u16,
    width: u16, // the sprite's row length in data
    screen_width: u16,
    left_x_position: u16,
    left_x_clamped: u16,
    left_clamp: bool,
    right_clamp: bool,
    /// source value that is not drawn; null draws every pixel
    skip: ?u8,
    y_table: ?[]const i16,
    y_index: u16,
    x_table: ?[]const i16,
    x_index: u16,
};

/// The u16 distance the y table moves column `col` (negative offsets wrap).
fn yShift(j: Job, table: []const i16, col: u16) u16 {
    var counter: u16 = col + j.left_x_position + j.y_index;
    if (counter >= table.len) counter -= @as(u16, @intCast(table.len));
    const off = table[counter];
    if (off < 0) return 0 -% (@as(u16, @intCast(-off)) *% j.screen_width);
    return @as(u16, @intCast(off)) *% j.screen_width;
}

pub fn plot(j: Job) void {
    var shifts: [MAX_COLS]u16 = undefined;
    const tabled = j.y_table != null and j.nb_cols <= MAX_COLS;
    if (tabled) {
        for (0..j.nb_cols) |c| shifts[c] = yShift(j, j.y_table.?, @intCast(c));
    }
    var offset = j.offset;
    var dc = j.data_counter;
    var row: u16 = 0;
    while (row < j.rows) : (row += 1) {
        for (0..j.nb_cols) |c| {
            const col: u16 = @intCast(c);
            const pal = j.data[dc];
            dc += 1;
            if (j.skip) |k| if (pal == k) continue;
            var base = offset;
            if (j.y_table) |t| base +%= if (tabled) shifts[c] else yShift(j, t, col);
            const at = base +% col;
            if (j.out[at] != pal) j.out[at] = pal;
        }
        if (j.right_clamp) dc += (j.width - j.nb_cols - j.left_x_clamped);
        if (j.left_clamp) dc += j.left_x_clamped;
        if (j.x_table) |table| {
            const delta: i16 = table[(j.x_index + row) % table.len];
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
