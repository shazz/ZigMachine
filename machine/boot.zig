// --------------------------------------------------------------------------
// machine/boot.zig — the ZigMachine boot ROM (power-on / POST screen).
//
// Machine firmware: it depends ONLY on the HW ABI (@import("hardware")), never on
// the open libs — so it COULD one day render from inside machine-video.wasm,
// leaving a cart with no boot screen to link at all. That is still open, and it is
// NOT the ROM-chip work (docs/PHASE2_ROM_CHIP.md), which cut GEM out into
// rom.wasm and is done. For now the boot ROM is statically linked into every cart
// and driven by the app's boot phase (apps/zig/demo_main.zig). It carries its OWN system font +
// logo (machine/assets/), the way a real machine's ROM does.
//
// A faithful port of the old ZigOS `Boot` effect, but drawing via raw writes into
// the shared video region (plane-0 framebuffer + palette) instead of LogicalFB /
// printText helpers.
// --------------------------------------------------------------------------
const hw = @import("hardware");

const FONT = @embedFile("assets/fonts/system_font_atari_1bit.raw"); // 256 x 8x8, 1 byte/pixel
const LOGO = @embedFile("assets/logo/zig_logo.raw"); // 65x60, 8-bit indexed
const LOGO_PAL = @embedFile("assets/logo/zig_logo.pal"); // 256 x [r,g,b,a]

const W: usize = hw.WIDTH; // 320
const H: usize = hw.HEIGHT; // 200
const GLYPH = 8; // font cell (8x8)
const WHITE: u8 = 7;
const BLACK: u8 = 0;
const RAM_STEP: u16 = 3; // advance the fake mem-test every N frames

pub const Boot = struct {
    base: usize = 0,
    counter_ram: u16 = 0,
    counter_boot: u16 = 0,
    tick: u16 = 0,

    inline fn fb(self: *Boot) [*]u8 {
        return @ptrFromInt(self.base + hw.OFF_VRAM);
    }
    inline fn pal(self: *Boot) [*]u8 {
        return @ptrFromInt(self.base + hw.OFF_PAL);
    }

    pub fn init(self: *Boot) void {
        self.base = @intCast(hw.hwVideoBase());
        self.counter_ram = 0;
        self.counter_boot = 0;
        self.tick = 0;

        // White border/background (REG_BACKGROUND is RGBA, offset from region base).
        const bg: [*]u8 = @ptrFromInt(self.base + hw.REG_BACKGROUND);
        bg[0] = 255;
        bg[1] = 255;
        bg[2] = 255;
        bg[3] = 255;

        // Palette from the logo's .pal (byte-identical to the machine's RGBA layout),
        // plus a red entry 9 for the Atari footer glyphs.
        const p = self.pal();
        for (LOGO_PAL, 0..) |b, i| p[i] = b;
        p[9 * 4 + 0] = 255;
        p[9 * 4 + 1] = 0;
        p[9 * 4 + 2] = 0;
        p[9 * 4 + 3] = 255;

        // Clear plane 0 to white (index 7).
        const f = self.fb();
        var i: usize = 0;
        while (i < W * H) : (i += 1) f[i] = WHITE;
    }

    // Copy an indexed image into plane 0 at (x,y). Opaque: the logo's palette
    // entry 0 has alpha 255, so — like the original Sprite — every pixel is drawn
    // (index 0 is a real colour here, not transparency).
    fn blit(self: *Boot, data: []const u8, w: usize, h: usize, x: usize, y: usize) void {
        const f = self.fb();
        var yy: usize = 0;
        while (yy < h) : (yy += 1) {
            var xx: usize = 0;
            while (xx < w) : (xx += 1) {
                f[(y + yy) * W + (x + xx)] = data[yy * w + xx];
            }
        }
    }

    // Clean 8x8 glyph blit: 1 byte/pixel, one exact square cell per character.
    // (ZigOS printText had a char*64-1 slice + a per-row over-advance that bled a
    // 9th column, leaving the first inverse-video cell non-square — fixed here.)
    fn text(self: *Boot, s: []const u8, x: u16, y: u16, fg: u8, bg: u8) void {
        const f = self.fb();
        for (s, 0..) |char, nb| {
            if (char == 0) continue;
            const glyph = @as(usize, char) * (GLYPH * GLYPH);
            const cx: usize = @as(usize, x) + nb * GLYPH;
            var row: usize = 0;
            while (row < GLYPH) : (row += 1) {
                const dst = (@as(usize, y) + row) * W + cx;
                var col: usize = 0;
                while (col < GLYPH) : (col += 1) {
                    f[dst + col] = if (FONT[glyph + row * GLYPH + col] == 1) fg else bg;
                }
            }
        }
    }

    pub fn update(self: *Boot) void {
        self.tick +%= 1;
        if (self.tick % RAM_STEP == 0) {
            if (self.counter_ram < 16) self.counter_ram += 1;
            if (self.counter_ram == 16 and self.counter_boot < 35) self.counter_boot += 1;
        }
    }

    pub fn render(self: *Boot) void {
        self.blit(LOGO, 65, 60, 20, 10);

        const atari = [2]u8{ 14, 15 };
        const top: u16 = 74;

        self.text("Memory Test:", 8, top + 0, BLACK, WHITE);
        self.text("WASM RAM:", 8, top + 10, BLACK, WHITE);
        self.text("                ", 8 + 12 * 8, top + 10, WHITE, BLACK);

        var i: u16 = 0;
        while (i < self.counter_ram) : (i += 1) {
            self.text("-", 8 + 12 * 8 + (i * 8), top + 10, WHITE, BLACK);
        }

        if (self.counter_ram == 16) {
            self.text("  2048 KB", 8 + 19 * 8, top + 10, WHITE, BLACK);
            self.text("Memory Test Complete.", 8, top + 20, BLACK, WHITE);

            i = 0;
            while (i < self.counter_boot) : (i += 1) {
                self.text(" ", 8 + (i * 8), 74 + 30, WHITE, BLACK);
            }
        }

        // Footer: red Atari glyphs framing "Stay Atari!"
        self.text(&atari, 70, 180, 9, WHITE);
        self.text("Stay Atari!", 100, 180, BLACK, WHITE);
        self.text(&atari, 200, 180, 9, WHITE);
    }
};
