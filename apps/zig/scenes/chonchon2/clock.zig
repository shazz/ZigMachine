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
//
// Two builds of the one motion: `Clock` (planar = true) is the Go's, drawing
// into a 32000-byte ST screen with a 320-byte ribbon line shifted every tick
// -- the REFERENCE the native test and the harness's screen checks read.
// `Live` (planar = false) draws nothing: its ribbon is a 640-byte ring per
// line (each new 8-pixel column stored twice, 320 apart, so the 320 pixels on
// screen are always one contiguous run) and compose.zig blits the picture
// from it, the panel record and the poses.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");
const planar_draw = @import("planar_draw.zig");

pub const Pose = struct { x: i32, y: i32, half: bool };

/// The panel rows this tick copied (y..y+rows of the 69-row pattern, at
/// pattern column `shift` * 16 bytes); `on` false when it copied none.
pub const Panel = struct { y: i32 = 0, rows: i32 = 0, shift: usize = 0, on: bool = false };

pub const RING_W: usize = 640;

pub const Clock = ClockOf(true);
pub const Live = ClockOf(false);

pub fn ClockOf(comptime planar: bool) type {
    return struct {
        const Self = @This();

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
        screen: if (planar) [32000]u8 else void = undefined,
        glyph: [184]u8 = undefined,
        ribbon: if (planar) [23][320]u8 else [23][RING_W]u8 align(4) = undefined,
        /// Live: ring x of the first pixel on screen (a multiple of 8).
        head: usize = 0,
        poses: [2]Pose = .{ .{ .x = 0, .y = 0, .half = false }, .{ .x = 0, .y = 0, .half = false } },
        panel: Panel = .{},

        pub fn init() Self {
            var c = Self{};
            if (planar) @memset(&c.screen, 0);
            @memset(&c.glyph, 0);
            for (&c.ribbon) |*line| @memset(line, 0);
            c.step(); // NewClock's one Step...
            c.tick = 0; // ...then Tick = 0
            return c;
        }

        /// The ribbon line's x-th pixel as the Go's Ribbon[row][x] holds it.
        pub fn ribbonByte(self: *const Self, row: usize, x: usize) u8 {
            return if (planar) self.ribbon[row][x] else self.ribbon[row][self.head + x];
        }

        pub fn step(self: *Self) void {
            self.tick +%= 1;

            // One authored motion sample is consumed on every 50 Hz tick.
            if (planar) @memcpy(&self.screen, assets.background);

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

            if (planar) self.ribbonPlanar() else self.ribbonRing();
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

            self.panel = .{};
            if (assets.panel_pattern.len >= 69 * 160 and
                self.caption_cursor + 4 < assets.panel.len)
            {
                const y = @as(i32, @intCast(assets.beWord(assets.panel, self.caption_cursor)));
                const rows = @as(i32, @intCast(assets.beWord(assets.panel, self.caption_cursor + 2)));
                self.panel = .{ .y = y, .rows = rows, .shift = self.caption_shift, .on = true };
                if (planar) planar_draw.panel(&self.screen, y, rows, self.caption_shift);
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

        /// Pixel x (0..7) of the glyph column the ribbon appends on `row`.
        fn glyphPixel(self: *const Self, row: usize, x: usize) u8 {
            var index: u8 = 0;
            var plane: usize = 0;
            while (plane < 2) : (plane += 1) {
                const at = row * 8 + self.glyph_column / 2 * 4 + plane * 2 + self.glyph_column % 2;
                const bit: u8 = (self.glyph[at] >> @intCast(7 - x)) & 1;
                index |= bit << @intCast(plane);
            }
            return index;
        }

        fn ribbonPlanar(self: *Self) void {
            var row: usize = 0;
            while (row < 23) : (row += 1) {
                // copy(Ribbon[row][:312], Ribbon[row][8:]): overlapping, leftwards.
                var x: usize = 0;
                while (x < 312) : (x += 1) self.ribbon[row][x] = self.ribbon[row][x + 8];
                x = 0;
                while (x < 8) : (x += 1) self.ribbon[row][312 + x] = self.glyphPixel(row, x);
                const y = self.scroll_y + @as(i32, @intCast(row));
                if (y >= 0 and y < 200) {
                    x = 0;
                    while (x < 320) : (x += 1)
                        planar_draw.pixel(&self.screen, x, @intCast(y), self.ribbon[row][x]);
                }
            }
        }

        /// The same shift as a moving head: the 8 new pixels land at ring x
        /// head+312 (mod 320) and again 320 further, as two u32 stores each.
        fn ribbonRing(self: *Self) void {
            self.head = (self.head + 8) % 320;
            const at = (self.head + 312) % 320;
            var row: usize = 0;
            while (row < 23) : (row += 1) {
                var v: [2]u32 = .{ 0, 0 };
                for (0..8) |x| v[x / 4] |= @as(u32, self.glyphPixel(row, x)) << @intCast(8 * (x % 4));
                const words: [*]u32 = @ptrCast(@alignCast(&self.ribbon[row]));
                words[at / 4] = v[0];
                words[at / 4 + 1] = v[1];
                words[(at + 320) / 4] = v[0];
                words[(at + 320) / 4 + 1] = v[1];
            }
        }
    };
}
