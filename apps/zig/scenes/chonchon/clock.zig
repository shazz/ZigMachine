// --------------------------------------------------------------------------
// The native motion -- internal/source/clock.go of go-chonchon, transcribed
// statement for statement. NewClock steps twice and resets Tick to 0 (matching
// the Go's boot, whose first drawn frame is empty), so `init` calls `step`
// twice. `logo_row` is the Go's LogoRow, and `ring` is the two 3432-byte
// scroll banks the headless harness pins against the Go tree's own native
// scroll-bank checkpoints.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");

const RING_LEN = 3432;

pub const Clock = struct {
    tick: u32 = 0,
    logo_phase: i32 = 0,
    logo_y_phase: i32 = 0,
    logo_y: i32 = 0,
    scroll_phase: i32 = 0,
    message_cursor: i32 = 0,
    counter: i32 = 0,
    ring: [2][RING_LEN]u8 = undefined,
    write: [2]i32 = .{ 2808, 2808 },
    read: [2]i32 = .{ 0, 0 },
    screen: [32000]u8 align(4) = undefined,
    star_base: [100]i32 = undefined,
    star_cursor: [100]i32 = undefined,

    pub fn init() Clock {
        var c = Clock{};
        @memset(&c.ring[0], 0);
        @memset(&c.ring[1], 0);
        @memset(&c.screen, 0);
        var i: usize = 0;
        while (i < 100) : (i += 1) {
            c.star_base[i] = @as(i32, @bitCast(assets.beLong(assets.star_index, i * 6))) - 0x1b018 - 0x1cc88;
            c.star_cursor[i] = assets.beWord(assets.star_index, i * 6 + 4);
        }
        c.step();
        c.step();
        c.tick = 0;
        return c;
    }

    /// The Go's LogoRow: (x, bank phase, y) for one of the 63 chrome rows.
    pub const LogoRow = struct { x: i32, phase: u32, y: i32 };

    pub fn logoRow(self: *const Clock, row: usize) LogoRow {
        const p: usize = @intCast(self.logo_phase + @as(i32, @intCast(row)) * 6);
        const offset = assets.beWord(assets.logo_path, p);
        const phase = assets.beLong(assets.logo_path, p + 2) / 72;
        return .{ .x = @as(i32, offset / 8) * 16, .phase = phase, .y = self.logo_y + @as(i32, @intCast(row)) };
    }

    /// The Go's Step: the background, then everything that moves over it.
    pub fn step(self: *Clock) void {
        @memcpy(&self.screen, assets.background);
        self.advance();
    }

    /// Step without the background copy: the live cart restores only the
    /// groups the last tick wrote (chonchon/dirty.zig) and then calls this.
    pub fn advance(self: *Clock) void {
        self.tick +%= 1;
        self.logo_phase += 12;
        if (assets.sWord(assets.logo_path, @intCast(self.logo_phase + 63 * 6)) < 0)
            self.logo_phase = 0;
        self.logo_y_phase += 1;
        if (self.logo_y_phase * 2 >= assets.logo_y.len or
            assets.sWord(assets.logo_y, @intCast(self.logo_y_phase * 2)) < 0)
            self.logo_y_phase = 0;
        self.logo_y = @divTrunc(@as(i32, assets.beWord(assets.logo_y, @intCast(self.logo_y_phase * 2))), 160);

        var i: usize = 0;
        while (i < 100) : (i += 1) {
            var p: i32 = self.star_base[i] + self.star_cursor[i] + 6;
            if (p + 6 > @as(i32, @intCast(assets.star_paths.len)) or
                assets.beWord(assets.star_paths, @intCast(p)) == 0)
            {
                self.star_cursor[i] = 0;
                p = self.star_base[i];
            } else {
                self.star_cursor[i] += 6;
            }
            const off: i32 = assets.beWord(assets.star_paths, @intCast(p));
            if (off + 4 <= @as(i32, @intCast(self.screen.len))) {
                const uo: usize = @intCast(off);
                // The Go's big-endian long OR, a byte at a time: `off` is odd
                // or 2 mod 4 for most stars, where a u32 load would trap.
                const src: usize = @intCast(p + 2);
                for (0..4) |k| self.screen[uo + k] |= assets.star_paths[src + k];
            }
        }

        const bank: usize = @intCast((self.tick - 1) % 2);
        if (bank == 0 and self.counter == 0) {
            if (self.message_cursor + 2 > @as(i32, @intCast(assets.message.len)) or
                assets.sWord(assets.message, @intCast(self.message_cursor)) < 0)
                self.message_cursor = 0;
            const off: usize = assets.beWord(assets.message, @intCast(self.message_cursor));
            self.write[0] = @mod(self.write[0] + 312, RING_LEN);
            const w0: usize = @intCast(self.write[0]);
            if (off + 312 <= assets.font.len) {
                @memcpy(self.ring[0][w0 .. w0 + 312], assets.font[off .. off + 312]);
            }
        }
        if (bank == 1) {
            self.counter -= 1;
            if (self.counter < 0) {
                self.counter = 1;
                if (self.message_cursor + 2 > @as(i32, @intCast(assets.message.len)) or
                    assets.sWord(assets.message, @intCast(self.message_cursor)) < 0)
                    self.message_cursor = 0;
                const off: i32 = assets.sWord(assets.message, @intCast(self.message_cursor));
                self.message_cursor += 2;
                self.write[1] = @mod(self.write[1] + 312, RING_LEN);
                const packed_off: i32 = 0x18369 - 0xce2a + off;
                if (packed_off >= 0 and packed_off + 312 <= @as(i32, @intCast(assets.font.len))) {
                    var row: usize = 0;
                    while (row < 26) : (row += 1) {
                        const src: usize = @intCast(packed_off + @as(i32, @intCast(row)) * 12);
                        const dst: i32 = self.write[1] + @as(i32, @intCast(row)) * 6;
                        var plane: usize = 0;
                        while (plane < 3) : (plane += 1) {
                            const a: usize = @intCast(@mod(dst - 155 + @as(i32, @intCast(plane)) * 2 + RING_LEN, RING_LEN));
                            self.ring[1][a] = assets.font[src + plane];
                        }
                        var j: usize = 0;
                        while (j < 6) : (j += 1)
                            self.ring[1][@intCast(@mod(dst + @as(i32, @intCast(j)), RING_LEN))] = assets.font[src + 3 + j];
                        plane = 0;
                        while (plane < 3) : (plane += 1)
                            self.ring[1][@intCast(@mod(dst + 156 + @as(i32, @intCast(plane)) * 2, RING_LEN))] = assets.font[src + 9 + plane];
                    }
                }
            }
        }

        self.scroll_phase += 2;
        if (self.scroll_phase * 2 >= @as(i32, @intCast(assets.scroll_y.len)) or
            assets.sWord(assets.scroll_y, @intCast(self.scroll_phase * 2)) < 0)
            self.scroll_phase = 0;
        self.read[bank] = @mod(self.read[bank] + 156, RING_LEN);
        var col: usize = 0;
        while (col < 18) : (col += 1) {
            const ys = self.columnYs(col);
            const y1 = ys[0];
            const y2 = ys[1];
            var row: usize = 0;
            while (row < 26) : (row += 1) {
                const r: usize = @intCast(@mod(self.read[bank] + @as(i32, @intCast(col)) * 156 + @as(i32, @intCast(row)) * 6, RING_LEN));
                var plane: usize = 0;
                while (plane < 3) : (plane += 1) {
                    const a: i32 = (y1 + @as(i32, @intCast(row))) * 160 + (@as(i32, @intCast(col)) + 1) * 8 + @as(i32, @intCast(plane)) * 2;
                    const b: i32 = (y2 + @as(i32, @intCast(row))) * 160 + (@as(i32, @intCast(col)) + 1) * 8 + @as(i32, @intCast(plane)) * 2 + 1;
                    if (a >= 0 and a < @as(i32, @intCast(self.screen.len)))
                        self.screen[@intCast(a)] = self.ring[bank][r + plane * 2];
                    if (b >= 0 and b < @as(i32, @intCast(self.screen.len)))
                        self.screen[@intCast(b)] = self.ring[bank][r + plane * 2 + 1];
                }
            }
        }
    }

    /// The two wave rows (hi bytes, lo bytes) scroller column `col` lands on.
    pub fn columnYs(self: *const Clock, col: usize) [2]i32 {
        const nwave: usize = assets.scroll_y.len / 2;
        var p: usize = @intCast(self.scroll_phase + @as(i32, @intCast(col)) * 2);
        var tries: u8 = 0;
        while ((p >= nwave or assets.sWord(assets.scroll_y, p * 2) < 0) and tries < 8) : (tries += 1) p = 0;
        var p2: usize = p + 1;
        tries = 0;
        while ((p2 >= nwave or assets.sWord(assets.scroll_y, p2 * 2) < 0) and tries < 8) : (tries += 1) p2 = 0;
        const y1: i32 = @divTrunc(@as(i32, assets.beWord(assets.scroll_y, p * 2)), 160);
        const y2: i32 = @divTrunc(@as(i32, assets.beWord(assets.scroll_y, p2 * 2)), 160);
        return .{ y1, y2 };
    }

    /// Where star `i`'s last long went (its path entry after the step), or
    /// null when the step wrote nothing for it.
    pub fn starOffset(self: *const Clock, i: usize) ?usize {
        const off: usize = assets.beWord(assets.star_paths, @intCast(self.star_base[i] + self.star_cursor[i]));
        return if (off + 4 <= self.screen.len) off else null;
    }
};
