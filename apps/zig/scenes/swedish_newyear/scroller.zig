// CODEF's scrolltext_horizontal (lib/codef_scrolltext.js), the parts this
// screen uses: `wide+1` letters one font width apart, each moving `speed` a
// frame; a letter at or past -fontw rejoins the back of the ring with the next
// character, and the optional sine (type 0) gives each letter, in screen order,
// the phase sin(myvalue) with myvalue stepping `inc` per letter and `offset` a
// frame (plus `inc` per letter that wrapped, so the wave stays on its letters).
// Integers: the only user is the menu (font 95 wide, speed 10, no sine), where
// every position is a whole number, so i32 gives the f64 version's values exactly
// without soft-float on the board. (The sine mode was never used here and is gone.)
pub const MAX = 24; // the widest ring here: the TCB cylinder, ceil(704/32)+1 = 23 -> 24 letters

pub const Scroller = struct {
    text: []const u8,
    fontw: i32,
    speed: i32,
    wide: usize,
    posx: [MAX]i32,
    ltr: [MAX]u8,
    off: usize, // scroffset: the next character to load

    /// init(dst, font, speed): `canvas_w` is the destination canvas width.
    pub fn init(self: *Scroller, text: []const u8, fontw: i32, canvas_w: i32, speed: i32) void {
        self.text = text;
        self.fontw = fontw;
        self.speed = speed;
        // Clamped so a wider canvas can never run past the MAX-letter ring (no
        // ring here reaches it: the widest is exactly MAX).
        self.wide = @min(@as(usize, @intCast(@divFloor(canvas_w + fontw - 1, fontw) + 1)), MAX - 1);
        self.off = 0;
        for (0..self.wide + 1) |i| {
            self.posx[i] = @as(i32, @intCast(self.wide + i)) * fontw;
            self.ltr[i] = text[self.off];
            self.off += 1;
        }
    }

    /// The movement half of draw(): move, wrap, and fix this draw's phase.
    pub fn advance(self: *Scroller) void {
        const wide_w = @as(i32, @intCast(self.wide)) * self.fontw;
        for (0..self.wide + 1) |i| {
            self.posx[i] -= self.speed;
            if (self.posx[i] <= -self.fontw) {
                self.posx[i] = wide_w + (self.posx[i] + self.fontw);
                self.ltr[i] = self.text[self.off];
                self.off += 1;
                if (self.off > self.text.len - 1) self.off = 0;
            }
        }
    }

    /// Letter indices left to right (the draw order; positions never tie).
    pub fn order(self: *const Scroller, out: *[MAX]u8) []const u8 {
        const n = self.wide + 1;
        for (0..n) |i| out[i] = @intCast(i);
        var i: usize = 1;
        while (i < n) : (i += 1) {
            var j = i;
            while (j > 0 and self.posx[out[j - 1]] > self.posx[out[j]]) : (j -= 1) {
                const t = out[j];
                out[j] = out[j - 1];
                out[j - 1] = t;
            }
        }
        return out[0..n];
    }

    /// The character draw() just made current (CODEF reads scrtxt at scroffset).
    pub fn current(self: *const Scroller) u8 {
        return self.text[self.off];
    }
};
