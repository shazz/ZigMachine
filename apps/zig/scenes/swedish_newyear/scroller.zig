// CODEF's scrolltext_horizontal (lib/codef_scrolltext.js), the parts this
// screen uses: `wide+1` letters one font width apart, each moving `speed` a
// frame; a letter at or past -fontw rejoins the back of the ring with the next
// character, and the optional sine (type 0) gives each letter, in screen order,
// the phase sin(myvalue) with myvalue stepping `inc` per letter and `offset` a
// frame (plus `inc` per letter that wrapped, so the wave stays on its letters).
// All in f64, as JS numbers are: omega's 30.7-wide font makes the positions
// fractional, and the positions and phases accumulate exactly as they do there.
pub const MAX = 24; // the widest ring here: the TCB cylinder, ceil(704/32)+1 = 23 -> 24 letters

pub const Sine = struct { value: f64, amp: f64, inc: f64, offset: f64 };

pub const Scroller = struct {
    text: []const u8,
    fontw: f64,
    speed: f64,
    wide: usize,
    posx: [MAX]f64,
    ltr: [MAX]u8,
    off: usize, // scroffset: the next character to load
    sine: ?Sine,
    phase: f64, // myvalue at the leftmost letter for the draw in progress

    /// init(dst, font, speed): `canvas_w` is the destination canvas width.
    pub fn init(self: *Scroller, text: []const u8, fontw: f64, canvas_w: f64, speed: f64, sine: ?Sine) void {
        self.text = text;
        self.fontw = fontw;
        self.speed = speed;
        self.wide = @intFromFloat(@ceil(canvas_w / fontw) + 1);
        self.off = 0;
        for (0..self.wide + 1) |i| {
            self.posx[i] = @ceil(@as(f64, @floatFromInt(self.wide)) * fontw + @as(f64, @floatFromInt(i)) * fontw);
            self.ltr[i] = text[self.off];
            self.off += 1;
        }
        self.sine = sine;
        self.phase = 0;
    }

    /// The movement half of draw(): move, wrap, and fix this draw's phase.
    pub fn advance(self: *Scroller) void {
        const wide_w = @as(f64, @floatFromInt(self.wide)) * self.fontw;
        var base: f64 = if (self.sine) |s| s.value else 0;
        for (0..self.wide + 1) |i| {
            self.posx[i] -= self.speed;
            if (self.posx[i] <= -self.fontw) {
                self.posx[i] = wide_w + (self.posx[i] + self.fontw);
                if (self.sine) |s| base += s.inc;
                self.ltr[i] = self.text[self.off];
                self.off += 1;
                if (self.off > self.text.len - 1) self.off = 0;
            }
        }
        self.phase = base;
        if (self.sine) |*s| s.value = base + s.offset;
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

/// The y offset of the k-th letter (screen order) of this draw.
pub fn sineAt(s: Sine, phase_k: f64) f64 {
    return @sin(phase_k) * s.amp;
}
