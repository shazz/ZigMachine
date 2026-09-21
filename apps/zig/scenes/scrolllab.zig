// --------------------------------------------------------------------------
// SCROLLTEXT LAB — not a demo screen, a comparison bench.
//
// One font, one scrolltext, one row, one speed. Keys 1..9 and 0 (or Space)
// switch the DISTORTION and nothing else, so the eight can be judged against
// each other rather than against eight different screens. LEFT and RIGHT dial
// the curve's TRAVEL — pixels a frame the whole curve slides, 0 meaning it is
// pinned in screen space and the letters ride through it, which is the
// rollercoaster question in one knob. The mode's number, name and the travel
// sit in the top-left corner at half the font's size, so a screenshot says
// which one it is.
//
// The band is rendered ONCE a frame into a strip and every mode is a filter over
// it (emlyn/../scrolllab/modes.zig) — screen 345's decoupling of "make the text"
// from "distort it", which is what a lab wants.
//
// No rasters, no logo, no music: they would all get in the way of looking at
// the text. It borrows the REPLICANTS font (emlyn.bin's second half) rather
// than shipping an asset of its own — the lab owns no art.
//
// The scroller itself is CODEF's scrolltext_horizontal ring, the same one
// screen 17 uses: ceil(320/32) + 1 = 11, and the loop runs `i <= wide`, so
// TWELVE letters, each starting at 352 + 32i and moving 2 ST pixels a frame.
// That is the original's speed 4 on its doubled canvas, and it does not change
// with the mode.
//
// Keys: 1..8 pick a mode, Space cycles, Left/Right dial travel, Escape leaves.
// Declaring key() takes
// Escape away from the host, so this scene sets wants_quit itself.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hw = @import("hardware");
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

        const buf = freeRam(A.TOTAL) orelse return fail("no free RAM for the font");
        if (zx0.depack(packed_assets.replicants_emlyn, buf) == null) return fail("depack failed");
        self.font = A.Images.split(buf).font;

        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setPalette(A.palette);
        fb.setPaletteEntry(A.TRANSPARENT, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
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
        @memset(dst.buf, A.BLACK);
        var glyphs: [LETTERS]modes.Glyph = undefined;
        var align_x: usize = 0;
        for (&glyphs, self.posx, self.ltr) |*g, x, c| {
            g.* = .{ .x = x, .cell = cellOf(c) };
            align_x = @intCast(@mod(x, TILE)); // every letter shares this phase
        }
        modes.fillStrip(self.font, &glyphs);
        modes.draw(self.mode, dst, ROW, align_x, TRAVEL_STEP * @as(f64, @floatFromInt(self.travel)), self.frame);
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

fn fail(why: []const u8) void {
    zg.Console.log("scrolllab: {s}", .{why});
}

/// `len` bytes of the cart's RAM window above its statics and stack.
fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}
