// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: usize = @import("../zigos.zig").HEIGHT;
const WIDTH: usize = @import("../zigos.zig").WIDTH;

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Boot = struct {
    fb: *LogicalFB = undefined,
    counter: u16 = undefined,

    pub fn init(self: *Boot, fb: *LogicalFB) void {
        self.fb = fb;
        self.counter = 0;

        fb.setPaletteEntry(0, Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
        fb.setPaletteEntry(1, Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        fb.setPaletteEntry(2, Color{ .r = 255, .g = 0, .b = 0, .a = 255 });
    }

    pub fn update(self: *Boot) void {
        if (self.counter < 35) self.counter += 1;
    }

    pub fn render(self: *Boot, zigos: *ZigOS) void {
        const atari: [2]u8 = [2]u8{ 14, 15 };
        zigos.printText(self.fb, "[Z]ZigMachine 0.1", 8, 10, 1, 0);
        zigos.printText(self.fb, "Memory Test:", 8, 30, 1, 0);
        zigos.printText(self.fb, "WASM RAM:", 8, 40, 1, 0);
        zigos.printText(self.fb, " 2048 KB", 8 + 12 * 8, 40, 0, 1);
        zigos.printText(self.fb, "Memory Test Complete.", 8, 50, 1, 0);

        var i: u16 = 0;
        while (i < self.counter) : (i += 1) {
            zigos.printText(self.fb, " ", 8 + (i * 8), 60, 0, 1);
        }

        // footer
        zigos.printText(self.fb, &atari, 70, 180, 2, 0);
        zigos.printText(self.fb, "Stay Atari!", 100, 180, 1, 0);
        zigos.printText(self.fb, &atari, 200, 180, 2, 0);
    }
};
