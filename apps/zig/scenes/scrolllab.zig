// --------------------------------------------------------------------------
// SCROLLTEXT LAB — not a demo screen, a comparison bench.
//
// One font, one scrolltext, one row, one speed. Keys 1..9 and 0 (or Space)
// switch the DISTORTION and nothing else, so the eight can be judged against
// each other rather than against eight different screens. LEFT and RIGHT dial
// the curve's TRAVEL — pixels a frame the whole curve slides, 0 meaning it is
// pinned in screen space and the letters ride through it, which is the
// rollercoaster question in one knob. The mode, its name and the travel sit
// under the band at half the font's size, so a screenshot says which one it is.
//
// The band is rendered ONCE a frame into a strip and every mode is a filter over
// it (scrolllab/modes.zig): screen 345's "make the text, then distort it".
//
// No rasters, logo or music: they would get in the way of looking at the text.
// It borrows the REPLICANTS font (emlyn.bin's second half): the lab owns no art.
//
// The scroller itself is CODEF's scrolltext_horizontal ring, the same one
// screen 17 uses: ceil(320/32) + 1 = 11, and the loop runs `i <= wide`, so
// TWELVE letters, each starting at 352 + 32i and moving 2 ST pixels a frame.
// That is the original's speed 4 on its doubled canvas, whatever the mode.
//
// Keys: 1..9, 0 pick a mode, Space cycles, Left/Right dial travel, Escape
// leaves (declaring key() takes Escape from the host: wants_quit is ours).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;
const zx0 = @import("depackers").zx0;
const packed_assets = @import("packed_assets");

const A = @import("replicants_emlyn/assets.zig"); // the font and its palette
const modes = @import("scrolllab/modes.zig");
const Mode = modes.Mode;

const PLANE = 0;
const K_ESC: u32 = 0xE012;
const DIR_LEFT = 2;
const DIR_RIGHT = 3;
const DIR_FIRE = 5; // the host maps Space and Enter to input(5)
const TRAVEL_STEP = 0.25; // ST pixels a frame per key press
const TRAVEL_MAX = 12;

const TILE = modes.TILE;
const COLS = A.FONT_W / TILE; // 10 glyphs across the sheet
const FIRST_CHAR = 32;
const LETTERS = modes.W / TILE + 1; // 23: the strip is 704 wide for mode 9's track
const START = (LETTERS - 1) * TILE; // the ring laid end to end, filling the strip
const SPEED = 2; // ST pixels a frame = the original's 4 on a doubled canvas
const ROW = 84; // the band's top: room for +-60 of distortion on a 200-row screen
const LABEL_Y = 168; // out of the way: mode 9's loop reaches the top of the screen

const TEXT = "SCROLLTEXT LAB ... KEYS 1 TO 9 AND 0 PICK A DISTORTION, SPACE CYCLES, LEFT AND RIGHT DIAL THE TRAVEL ... SAME TEXT, SAME SPEED, SAME ROW: ONLY THE DISTORTION CHANGES ... ";

comptime {
    @setEvalBranchQuota(4 * TEXT.len + 1000);
    for (TEXT) |c| if (c < FIRST_CHAR or c >= FIRST_CHAR + COLS * (A.FONT_H / TILE)) @compileError("lab text outside the font sheet");
}

pub const Demo = struct {
    ok: bool,
    wants_quit: bool, // demo_main returns to the menu on this
    font: blit.Image,
    mode: Mode,
    posx: [LETTERS]i32,
    ltr: [LETTERS]u8,
    offset: usize,
    travel: i32, // in TRAVEL_STEP units; 0 = the curve stands still
    frame: u32,
    shown: ?struct { mode: Mode, travel: i32 }, // what the label rows hold

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.ok = false;
        self.wants_quit = false;
        self.mode = .flat;
        self.frame = 0;
        self.travel = 0;
        modes.init();
        self.offset = 0;
        // laid across the strip rather than parked off the right, so a lab
        // frame has text in it from the first frame
        for (&self.posx, &self.ltr, 0..) |*x, *c, i| {
            x.* = @intCast(i * TILE);
            c.* = TEXT[self.offset];
            self.offset += 1;
        }

        // On zg.mem, not borrowed above hwRamUsed(): modes.init() just took the
        // strip and the path from the arena, which would hand a borrow out again.
        const buf = zg.mem.alloc(u8, A.TOTAL) orelse return fail("no free RAM for the font");
        if (zx0.depack(packed_assets.replicants_emlyn, buf) == null) return fail("depack failed");
        self.font = A.Images.split(buf).font;

        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setPalette(A.palette);
        fb.setPaletteEntry(A.TRANSPARENT, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        self.shown = null;
        modes.prepare(band(blit.Dst.plane(fb)));
        self.ok = true;
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) self.wants_quit = true;
        if (cp >= '1' and cp <= '9') self.mode = @enumFromInt(@min(cp - '1', modes.NAMES.len - 1));
        if (cp == '0') self.mode = @enumFromInt(modes.NAMES.len - 1); // the tenth
    }

    pub fn input(self: *Demo, dir: u8) void {
        switch (dir) {
            DIR_FIRE => self.mode = @enumFromInt((@intFromEnum(self.mode) + 1) % modes.NAMES.len),
            DIR_LEFT => self.travel = @max(self.travel - 1, -TRAVEL_MAX),
            DIR_RIGHT => self.travel = @min(self.travel + 1, TRAVEL_MAX),
            else => {},
        }
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        if (!self.ok) return;
        self.frame +%= 1;
        for (&self.posx, &self.ltr) |*x, *c| {
            x.* -= SPEED;
            if (x.* > -TILE) continue;
            x.* += START + TILE;
            c.* = TEXT[self.offset];
            self.offset += 1;
            if (self.offset > TEXT.len - 1) self.offset = 0;
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (!self.ok) return;
        const dst = blit.Dst.plane(&zigos.lfbs[PLANE]);
        // Only the band is redrawn a frame, cleared by CHISEL (a CPU @memset of
        // the plane was ~1 Mc of DDR stores). The modes draw through band(),
        // which cannot reach the label rows: those change only with the label.
        const view = band(dst);
        view.fill(0, 0, view.w, view.h, A.BLACK);
        var glyphs: [LETTERS]modes.Glyph = undefined;
        var align_x: usize = 0;
        for (&glyphs, self.posx, self.ltr) |*g, x, c| {
            g.* = .{ .x = x, .cell = cellOf(c) };
            align_x = @intCast(@mod(x, TILE)); // every letter shares this phase
        }
        modes.fillStrip(self.font, &glyphs);
        modes.draw(self.mode, view, ROW, align_x, self.travel, self.frame);
        self.drawLabel(dst);
    }

    /// The mode's name and the travel, redrawn only when one of them changed.
    fn drawLabel(self: *Demo, dst: blit.Dst) void {
        if (self.shown) |s| if (s.mode == self.mode and s.travel == self.travel) return;
        self.shown = .{ .mode = self.mode, .travel = self.travel };
        if (dst.h > LABEL_Y) dst.fill(0, LABEL_Y, dst.w, dst.h - LABEL_Y, A.BLACK);
        label(dst, self.font, modes.NAMES[@intFromEnum(self.mode)], LABEL_Y);
        var line: [12]u8 = "TRAVEL     ".* ++ [_]u8{0};
        line[7] = if (self.travel < 0) '-' else ' '; // the font sheet has no '+'
        const n: u32 = @abs(self.travel);
        line[8] = '0' + @as(u8, @intCast(n / 10));
        line[9] = '0' + @as(u8, @intCast(n % 10));
        label(dst, self.font, line[0..10], LABEL_Y + TILE / 2);
    }

    fn cellOf(c: u8) blit.Rect {
        const g: usize = c - FIRST_CHAR;
        return .{ .x = g % COLS * TILE, .y = g / COLS * TILE, .w = TILE, .h = TILE };
    }
};

/// The mode's name in the corner at HALF the font's size — point-sampled, which
/// is rough but legible, and the only way 20 glyphs fit across 320 pixels.
fn label(dst: blit.Dst, font: blit.Image, text: []const u8, top: usize) void {
    const H = TILE / 2;
    for (text, 0..) |c, i| {
        const g: usize = c - FIRST_CHAR;
        const sx = g % COLS * TILE;
        const sy = g / COLS * TILE;
        for (0..H) |y| for (0..H) |x| {
            const p = font.data[(sy + 2 * y) * font.w + sx + 2 * x];
            if (p == 0) continue;
            const dx = 4 + i * H + x;
            const dy = top + y;
            if (dx < dst.w and dy < dst.h) dst.buf[dy * dst.stride + dx] = p;
        };
    }
}

/// The rows the distortions draw in: everything above the label.
fn band(dst: blit.Dst) blit.Dst {
    return dst.window(0, 0, dst.w, LABEL_Y);
}

fn fail(why: []const u8) void {
    zg.Console.log("scrolllab: {s}", .{why});
}
