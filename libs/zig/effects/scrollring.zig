// --------------------------------------------------------------------------
// Scrollring: CODEF's `scrolltext_horizontal` letter ring.
//
// CODEF does not scroll a strip. It keeps `wide + 1` letters, each with its own
// x, moves every letter left by the speed each frame, and sends a letter that
// has left the screen (x <= -glyph_w) to the back of the ring as
// `start + (x + glyph_w)`, carrying the next character of the text. Three ports
// hand-wrote that loop; the ring lives here and the scene keeps the drawing
// (wave, mask ink, strip), which is what actually differs between them.
//
// Generic over the position type: f32 reproduces CODEF's accumulated float
// positions exactly (noextra: 4.5 px/frame), and an integer type in sub-pixel
// units gives the exact integer ring (replicants_garfield: quarter pixels,
// 7 per frame). Unlike `scrolltext2`, the speed can be fractional and the
// letters start off screen at `start`, as CODEF lays them out.
//
// No ZigOS import: it tests natively (scrollring_test.zig).
// --------------------------------------------------------------------------

pub fn Ring(comptime P: type, comptime n: usize) type {
    if (n == 0) @compileError("scrollring: a ring needs at least one letter");
    switch (@typeInfo(P)) {
        .float => {},
        .int => |info| if (info.signedness != .signed) @compileError("scrollring: integer positions must be signed (letters go negative)"),
        else => @compileError("scrollring: position type must be a float or a signed integer"),
    }
    return struct {
        const Self = @This();

        x: [n]P,
        c: [n]u8,
        /// Replace it through setText(), which keeps `next` inside it.
        text: []const u8,
        /// Index in `text` of the character the next wrapping letter takes.
        next: usize,
        start: P,
        glyph_w: P,

        /// Letter i at `start + i * glyph_w`, carrying `text[i]`: CODEF's layout.
        /// An empty text scrolls blanks rather than killing the cart.
        pub fn init(text: []const u8, start: P, glyph_w: P) Self {
            var self: Self = .{ .x = undefined, .c = undefined, .text = nonEmpty(text), .next = 0, .start = start, .glyph_w = glyph_w };
            for (0..n) |i| {
                self.x[i] = start + fromIndex(i) * glyph_w;
                self.c[i] = self.take();
            }
            return self;
        }

        /// Move every letter left by `speed`. Returns true when a letter wrapped
        /// to the back of the ring (it now carries a new character).
        pub fn step(self: *Self, speed: P) bool {
            return self.stepCount(speed) > 0;
        }

        /// step(), returning HOW MANY letters wrapped: CODEF advances each
        /// sinparam's phase by `inc` once per wrapping letter.
        pub fn stepCount(self: *Self, speed: P) usize {
            var wrapped: usize = 0;
            for (&self.x, &self.c) |*x, *c| {
                x.* -= speed;
                if (x.* <= -self.glyph_w) {
                    x.* = self.start + (x.* + self.glyph_w);
                    c.* = self.take();
                    wrapped += 1;
                }
            }
            return wrapped;
        }

        /// The character the next wrapping letter will carry (CODEF scenes
        /// test `scrtxt.charCodeAt(scroffset)` for control markers).
        pub fn upcoming(self: *const Self) u8 {
            return self.text[self.next];
        }

        /// Pass over the upcoming character without showing it: CODEF scenes
        /// consume their effect markers with `scroffset++`. Wraps like a take.
        pub fn skip(self: *Self) void {
            _ = self.take();
        }

        /// Carry on with another text: the next wrapping letter takes its first character.
        pub fn setText(self: *Self, text: []const u8) void {
            self.text = nonEmpty(text);
            self.next = 0;
        }

        fn nonEmpty(text: []const u8) []const u8 {
            return if (text.len == 0) " " else text;
        }

        fn take(self: *Self) u8 {
            const ch = self.text[self.next];
            self.next += 1;
            if (self.next >= self.text.len) self.next = 0;
            return ch;
        }

        fn fromIndex(i: usize) P {
            return switch (@typeInfo(P)) {
                .float => @floatFromInt(i),
                .int => @intCast(i),
                else => unreachable, // rejected when the type is built
            };
        }
    };
}
