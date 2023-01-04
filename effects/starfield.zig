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
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

pub const StarfieldDirection = enum {
    LEFT,
    RIGHT,
};

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Starfield = struct {
    const Star = struct {
        x: u16 = undefined,
        y: u16 = undefined,
        speed: u16 = undefined,
        direction: StarfieldDirection = undefined,
    };

    rnd: std.rand.DefaultPrng = undefined,
    starfield_table: [100]Star = undefined,
    fb: *LogicalFB = undefined,
    width: u16 = undefined,
    height: u16 = undefined,
    speed: u16 = undefined,
    direction: StarfieldDirection = undefined,
    

    pub fn init(fb: *LogicalFB, width: u16, height: u16, speed: u16, direction: StarfieldDirection, background_transparency: u8) Starfield {

        // Set palette
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = background_transparency });
        fb.setPaletteEntry(1, Color{ .r = 255, .g = 255, .b = 255, .a = 128 });

        // Clear
        fb.clearFrameBuffer(0);

        // Add stars
        var rnd = RndGen.init(0);
        var starfield_table: [100]Star = undefined;

        var counter: u8 = 0;

        while (counter < 100) : (counter += 1) {
            const x = rnd.random().uintAtMost(u16, WIDTH);
            const y = rnd.random().uintAtMost(u8, HEIGHT);

            starfield_table[counter] = Star{ .x = x, .y = y, .speed = rnd.random().intRangeAtMost(u16, 1, speed), .direction=direction };

            fb.setPixelValue(x, y, 1);
        }

        return .{ .fb = fb, .rnd = rnd, .starfield_table = starfield_table, .width = width, .height = height, .speed = speed, .direction = direction };
    }

    pub fn update(self: *Starfield) void {
        self.fb.clearFrameBuffer(0);

        var counter: u8 = 0;
        while (counter < 100) : (counter += 1) {
            var star: Star = self.starfield_table[counter];

            if (self.direction == StarfieldDirection.RIGHT) {
                const new_pos: u16 = star.x + star.speed;

                if (new_pos > self.width) {
                    star.x = 0;
                } else {
                    star.x = new_pos;
                }

            } 
            if (self.direction == StarfieldDirection.LEFT) { 
                const new_pos: i32 = @intCast(i32, star.x) - @intCast(i32, star.speed);

                if (new_pos >= 0) {
                    star.x = star.x - star.speed;
                } else {
                    star.x = self.width;
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
