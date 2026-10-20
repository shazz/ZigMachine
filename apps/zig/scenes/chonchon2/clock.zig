// --------------------------------------------------------------------------
// The native motion -- internal/source/clock.go of go-chonchon2, transcribed
// statement for statement.
//
// NewClock loads the first 184-byte glyph, advances the scroll profile and
// both sprite paths once, and then sets Tick back to 0. The cart's boot frame
// is therefore the Go's pre-first-Update state (nothing drawn); the first
// 20 ms tick is Tick 1 here, exactly as the Go's first Update is its Tick 1.
//
// Every table is consumed by a straight u16/u32 read from the production's own
// files: the 7000-entry scroll profile, the 34-entry sliding-panel script, the
// 69-row panel pattern, both 7000-entry sprite paths, and the 2-plane glyph
// bank the ribbon appends to. The negative word in a path/profile is its
// loop marker; the message table's negative word means "skip a four-byte
// header, then read the glyph offset".
// --------------------------------------------------------------------------
const assets = @import("assets.zig");

pub const Pose = struct { x: i32, y: i32, half: bool };

pub const Clock = struct {
    tick: u32 = 0,
    profile_cursor: usize = 0,
    message_cursor: usize = 0,
    glyph_column: usize = 0,
    glyph_counter: i32 = 4,
    scroll_y: i32 = 70,
    old_y: i32 = 0,
    sprite_cursor: [2]usize = .{ 0, 0 },
    caption_cursor: usize = 0,
    caption_hold: i32 = 1,
    caption_wait: i32 = 100,
    caption_shift: usize = 0,
    screen: [32000]u8 = undefined,
    glyph: [184]u8 = undefined,
    ribbon: [23][320]u8 = undefined,
    poses: [2]Pose = .{ .{ .x = 0, .y = 0, .half = false }, .{ .x = 0, .y = 0, .half = false } },

    pub fn init() Clock {
        var c = Clock{};
        @memset(&c.screen, 0);
        @memset(&c.glyph, 0);
        for (&c.ribbon) |*line| @memset(line, 0);
        c.step(); // NewClock's one Step...
        c.tick = 0; // ...then Tick = 0
        return c;
    }

    pub fn step(self: *Clock) void {
        self.tick +%= 1;

        // One authored motion sample is consumed on every 50 Hz tick.
        @memcpy(&self.screen, assets.background);

        if (self.profile_cursor + 6 > assets.profile.len or
            assets.sWord(assets.profile, self.profile_cursor) < 0)
            self.profile_cursor = 0;
        self.old_y = self.scroll_y;
        self.scroll_y = @divTrunc(@as(i32, @intCast(assets.beWord(assets.profile, self.profile_cursor))), 160);
        self.profile_cursor += 6;

        if (self.glyph_counter == 4) {
            self.glyph_counter = 0;
            if (self.message_cursor + 4 > assets.message.len) self.message_cursor = 0;
            if (assets.sWord(assets.message, self.message_cursor) < 0) {
                self.glyph_counter = 2;
                self.message_cursor += 4;
            }
            const off: usize = assets.beLong(assets.message, self.message_cursor);
            self.message_cursor += 4;
            @memset(&self.glyph, 0);
            if (off + 184 <= assets.font.len)
                @memcpy(&self.glyph, assets.font[off .. off + 184]);
        }

        var row: usize = 0;
        while (row < 23) : (row += 1) {
            // copy(Ribbon[row][:312], Ribbon[row][8:]): overlapping, leftwards.
            var x: usize = 0;
            while (x < 312) : (x += 1) self.ribbon[row][x] = self.ribbon[row][x + 8];
            x = 0;
            while (x < 8) : (x += 1) {
                var index: u8 = 0;
                var plane: usize = 0;
                while (plane < 2) : (plane += 1) {
                    const at = row * 8 + self.glyph_column / 2 * 4 + plane * 2 + self.glyph_column % 2;
                    const bit: u8 = (self.glyph[at] >> @intCast(7 - x)) & 1;
                    index |= bit << @intCast(plane);
                }
                self.ribbon[row][312 + x] = index;
            }
            const y = self.scroll_y + @as(i32, @intCast(row));
            if (y >= 0 and y < 200) {
                x = 0;
                while (x < 320) : (x += 1)
                    self.pixel(x, @intCast(y), self.ribbon[row][x]);
            }
        }
        self.glyph_column = (self.glyph_column + 1) % 4;
        self.glyph_counter += 1;

        var i: usize = 0;
        while (i < 2) : (i += 1) {
            const path = if (i == 0) assets.path_a else assets.path_b;
            var p = self.sprite_cursor[i];
            if (p + 4 > path.len or assets.sWord(path, p) < 0) p = 0;
            const off: u32 = assets.beWord(path, p);
            self.poses[i] = .{
                .x = @intCast(off % 160 / 8 * 16 + off % 8 / 4 * 8),
                .y = @divTrunc(@as(i32, @intCast(off)), 160),
                .half = assets.sWord(path, p + 2) < 0,
            };
            self.sprite_cursor[i] = p + 4;
        }

        if (assets.panel_pattern.len >= 69 * 160 and
            self.caption_cursor + 4 < assets.panel.len)
        {
            const y = @as(i32, @intCast(assets.beWord(assets.panel, self.caption_cursor)));
            const rows = @as(i32, @intCast(assets.beWord(assets.panel, self.caption_cursor + 2)));
            var panel_row: i32 = 0;
            while (panel_row <= rows) : (panel_row += 1) {
                const yy = y + panel_row;
                if (yy < 0 or yy >= 69) continue;
                const src = @as(usize, @intCast(yy)) * 160 + self.caption_shift * 16;
                const dst = @as(usize, @intCast(yy)) * 160 + 0x200;
                var k: usize = 0;
                while (k < 16) : (k += 1) {
                    if (src + k < assets.panel_pattern.len and dst + k < self.screen.len)
                        self.screen[dst + k] = assets.panel_pattern[src + k];
                    if (src + k < assets.panel_pattern.len and dst + 80 + k < self.screen.len)
                        self.screen[dst + 80 + k] = assets.panel_pattern[src + k];
                }
            }
        }

        self.caption_wait -= 1;
        if (self.caption_wait <= 0) {
            self.caption_shift = (self.caption_shift + 1) % 10;
            if (self.caption_shift == 0) {
                self.caption_hold -= 1;
                if (self.caption_hold < 0) {
                    self.caption_cursor += 6;
                    if (self.caption_cursor + 6 > assets.panel.len or
                        assets.sWord(assets.panel, self.caption_cursor) < 0)
                        self.caption_cursor = 0;
                    self.caption_hold = @intCast(assets.beWord(assets.panel, self.caption_cursor + 4));
                }
            }
            self.caption_wait = 2;
        }
    }

    fn pixel(self: *Clock, x: usize, y: usize, v: u8) void {
        const at = y * 160 + x / 16 * 8;
        const mask: u16 = @as(u16, 1) << @intCast(15 - x % 16);
        var p: usize = 0;
        while (p < 4) : (p += 1) {
            const o = at + p * 2;
            var w = assets.beWord(&self.screen, o);
            w = w & ~mask;
            if (v >> @intCast(p) & 1 != 0) w |= mask;
            self.screen[o] = @truncate(w >> 8);
            self.screen[o + 1] = @truncate(w);
        }
    }
};
