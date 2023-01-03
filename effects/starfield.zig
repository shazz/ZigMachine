// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const RndGen = std.rand.DefaultPrng;

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Starfield = struct {
    const Star = struct {
        x: i16 = undefined,
        y: i16 = undefined,
        speed: i8 = undefined,
    };

    rnd: std.rand.DefaultPrng = undefined,
    starfield_table: [100]Star = undefined,
    fb: *LogicalFB = undefined,
    width: u16 = undefined,
    height: u16 = undefined,
    speed: i8 = undefined,

    pub fn init(fb: *LogicalFB, width: u16, height: u16, speed: i8, background_transparency: u8) Starfield {

        // Set palette
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = background_transparency });
        fb.setPaletteEntry(1, Color{ .r = 255, .g = 255, .b = 255, .a = 128 });

        // Clear
        fb.clearFrameBuffer(0);

        // Add stars
        var rnd = RndGen.init(0);
        var starfield_table: [100]Star = undefined;

        var counter: u8 = 0;

        var min: i8 = 0;
        var max: i8 = 0;
        if (speed > 0) {
            min = 1;
            max = speed;
        } else {
            min = speed;
            max = -1;
        }

        while (counter < 100) : (counter += 1) {
            const x = rnd.random().int(u8);
            const y = rnd.random().int(u8);

            if (speed > 0)
                starfield_table[counter] = Star{ .x = x, .y = y, .speed = rnd.random().intRangeAtMost(i8, min, max) };

            fb.setPixelValue(x, y, 1);
        }

        return .{ .fb = fb, .rnd = rnd, .starfield_table = starfield_table, .width = width, .height = height, .speed = speed };
    }

    pub fn update(self: *Starfield) void {
        self.fb.clearFrameBuffer(0);

        var counter: u8 = 0;
        while (counter < 100) : (counter += 1) {
            var star: Star = self.starfield_table[counter];
            if (star.speed > 0) {
                if (star.x > self.width) {
                    star.x = 0;
                } else {
                    star.x += @intCast(i16, star.speed);
                }
            } else {
                if (star.x > 0) {
                    star.x += @intCast(i16, star.speed);
                } else {
                    star.x = @intCast(i16, self.width);
                }
            }
            self.starfield_table[counter] = star;
            self.fb.setPixelValue(@intCast(u16, self.starfield_table[counter].x), @intCast(u16, self.starfield_table[counter].y), 1);
        }
    }

    pub fn render(self: *Starfield) void {
        var counter: u8 = 0;
        while (counter < 100) : (counter += 1) {
            var star: Star = self.starfield_table[counter];
            self.fb.setPixelValue(@intCast(u16, star.x), @intCast(u16, star.y), 1);
        }
    }
};
