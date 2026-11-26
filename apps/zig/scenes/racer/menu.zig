// --------------------------------------------------------------------------
// RACER: the front end's drawing kit (M5 step 4): solid panels, the logo's big letters (the 8x8
// system font scaled, with a drop shadow and a three-band gradient: our own art), and a line
// between two points (the track preview). All of it writes the plane's bytes directly, one
// @memset a row run (never a CHISEL op a rectangle: each costs ~800 cycles of fixed overhead on
// the board). The colours are palette entries 5..11 (palette.zig MENU). No ZigOS import: the
// pixel buffer is a parameter, so menu_test.zig draws into a plain array.
// --------------------------------------------------------------------------
pub const W = 320;
pub const H = 200;

// palette.zig installs these (entries 5..11 are free: 0-4 sky / HUD / far ground, 12-14 the backdrop, 16+ the ramps)
pub const LOGO = [3]u8{ 5, 6, 7 }; // the logo's gradient, top to bottom
pub const SHADE: u8 = 8; // the logo's drop shadow, the panels' border
pub const PANEL: u8 = 9;
pub const HILITE: u8 = 10; // the cursor row, the headings
pub const ALERT: u8 = 11; // a refused file

pub const Px = struct {
    px: []u8,
    stride: usize,

    /// A w x h rectangle at (x, y), clipped to the 320 x 200 screen.
    pub fn rect(self: Px, x: i32, y: i32, w: i32, h: i32, c: u8) void {
        const x0: usize = @intCast(@max(x, 0));
        const x1: usize = @intCast(@min(x + w, W));
        if (x1 <= x0) return;
        var r: i32 = @max(y, 0);
        while (r < @min(y + h, H)) : (r += 1) @memset(self.px[@as(usize, @intCast(r)) * self.stride + x0 ..][0 .. x1 - x0], c);
    }

    /// A panel: a filled box with a one-pixel border.
    pub fn panel(self: Px, x: i32, y: i32, w: i32, h: i32) void {
        self.rect(x, y, w, h, SHADE);
        self.rect(x + 1, y + 1, w - 2, h - 2, PANEL);
    }

    /// `text` in the 8x8 font (one byte a pixel, 1 = ink) scaled by `s`, transparent: shadow at +s/2, then the letters.
    pub fn big(self: Px, font: []const u8, text: []const u8, x: i32, y: i32, s: i32) void {
        const d = @max(1, @divTrunc(s, 2));
        self.glyphs(font, text, x + d, y + d, s, true);
        self.glyphs(font, text, x, y, s, false);
    }

    fn glyphs(self: Px, font: []const u8, text: []const u8, x: i32, y: i32, s: i32, shadow: bool) void {
        for (text, 0..) |ch, i| {
            const g = font[@as(usize, ch) * 64 ..][0..64];
            const gx = x + @as(i32, @intCast(i)) * 8 * s;
            for (0..8) |r| {
                const c = if (shadow) SHADE else LOGO[@min(r * 3 / 8, 2)];
                var col: usize = 0;
                while (col < 8) {
                    if (g[r * 8 + col] == 0) {
                        col += 1;
                        continue;
                    }
                    const a = col;
                    while (col < 8 and g[r * 8 + col] != 0) col += 1; // one run of ink: one rect
                    self.rect(gx + @as(i32, @intCast(a)) * s, y + @as(i32, @intCast(r)) * s, @as(i32, @intCast(col - a)) * s, s, c);
                }
            }
        }
    }

    /// A one-pixel line from a to b (Bresenham, integers), clipped per pixel.
    pub fn line(self: Px, a: [2]i32, b: [2]i32, c: u8) void {
        const dx: i32 = @intCast(@abs(b[0] - a[0]));
        const dy: i32 = -@as(i32, @intCast(@abs(b[1] - a[1])));
        const sx: i32 = if (a[0] < b[0]) 1 else -1;
        const sy: i32 = if (a[1] < b[1]) 1 else -1;
        var e = dx + dy;
        var p = a;
        while (true) {
            if (p[0] >= 0 and p[0] < W and p[1] >= 0 and p[1] < H) self.px[@as(usize, @intCast(p[1])) * self.stride + @as(usize, @intCast(p[0]))] = c;
            if (p[0] == b[0] and p[1] == b[1]) return;
            const e2 = 2 * e;
            if (e2 >= dy) {
                e += dy;
                p[0] += sx;
            }
            if (e2 <= dx) {
                e += dx;
                p[1] += sy;
            }
        }
    }
};
