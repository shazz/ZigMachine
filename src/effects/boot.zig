// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;

const Console = @import("../utils/debug.zig").Console;
const Sprite = @import("sprite.zig").Sprite;

const convertU8ArraytoColors = @import("../utils/loaders.zig").convertU8ArraytoColors;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: usize = @import("../zigos.zig").HEIGHT;
const WIDTH: usize = @import("../zigos.zig").WIDTH;

const ZIG_LOGO = @embedFile("../assets/logo/zig_logo.raw");
const ZIG_LOGO_PAL = convertU8ArraytoColors(@embedFile("../assets/logo/zig_logo.pal"));
const WHITE_ENTRY: u8 = 7;
const BLACK_ENTRY: u8 = 0;

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Boot = struct {
    fb: *LogicalFB = undefined,
    counter_ram: u16 = undefined,
    counter_boot: u16 = undefined,
    logo: Sprite = undefined,

    pub fn init(self: *Boot, fb: *LogicalFB) void {
        self.fb = fb;
        self.counter_ram = 0;
        self.counter_boot = 0;

        self.logo.init(fb, ZIG_LOGO, 65, 60, 20, 10, false, null);

        fb.setPalette(ZIG_LOGO_PAL);
        fb.setPaletteEntry(9, Color{ .r = 255, .g = 0, .b = 0, .a = 255 });
        fb.clearFrameBuffer(7);
    }

    pub fn update(self: *Boot) void {

        if (self.counter_ram < 16) self.counter_ram += 1;
        if (self.counter_ram == 16 and self.counter_boot < 35) self.counter_boot += 1;

        self.logo.update(null, null, null);
    }

    pub fn render(self: *Boot, zigos: *ZigOS) void {

        self.logo.render();

        const atari: [2]u8 = [2]u8{ 14, 15 };
        const top: u16 = 74;

        zigos.printText(self.fb, "Memory Test:", 8, top + 0, BLACK_ENTRY, WHITE_ENTRY);
        zigos.printText(self.fb, "WASM RAM:", 8, top + 10, BLACK_ENTRY, WHITE_ENTRY);
        zigos.printText(self.fb, "                ", 8 + 12 * 8, top + 10, WHITE_ENTRY, BLACK_ENTRY);

        var i: u16 = 0;
        while (i < self.counter_ram) : (i += 1) {
            zigos.printText(self.fb, "-", 8 + 12 * 8 + (i * 8), top + 10, WHITE_ENTRY, BLACK_ENTRY);
        }

        if (self.counter_ram == 16) {
            zigos.printText(self.fb, "  2048 KB", 8 + 19 * 8, top + 10, WHITE_ENTRY, BLACK_ENTRY);
            zigos.printText(self.fb, "Memory Test Complete.", 8, top + 20, BLACK_ENTRY, WHITE_ENTRY);

            i = 0;
            while (i < self.counter_boot) : (i += 1) {
                zigos.printText(self.fb, " ", 8 + (i * 8), 74 + 30, WHITE_ENTRY, BLACK_ENTRY);
            }
        }

        // footer
        zigos.printText(self.fb, &atari, 70, 180, 9, WHITE_ENTRY);
        zigos.printText(self.fb, "Stay Atari!", 100, 180, BLACK_ENTRY, WHITE_ENTRY);
        zigos.printText(self.fb, &atari, 200, 180, 9, WHITE_ENTRY);
    }
};
