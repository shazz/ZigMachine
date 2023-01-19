// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const RndGen = std.rand.DefaultPrng;

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;
const shapes = @import("shapes.zig");

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
pub fn Starfield(
    comptime nb_stars: comptime_int,
) type {
    return struct {
        const Star = struct {
            x: u16 = undefined,
            y: u16 = undefined,
            speed: u16 = undefined,
            direction: StarfieldDirection = undefined,
            color: u8 = undefined,
        };

        rnd: std.rand.DefaultPrng = undefined,
        starfield_table: [nb_stars]Star = undefined,
        fb: *LogicalFB = undefined,
        width: u16 = undefined,
        height: u16 = undefined,
        top: u16 = undefined,
        min_speed: u16 = undefined,
        max_speed: u16 = undefined,
        direction: StarfieldDirection = undefined,
        nb_colors: u8 = undefined,
        const Self = @This();

        pub fn init(fb: *LogicalFB, width: u16, height: u16, top: u16, min_speed: u16, max_speed: u16, direction: StarfieldDirection) Self {

            var sf = Self{};
            sf.fb = fb;
            sf.rnd = RndGen.init(0);
            sf.width = width;
            sf.height = height;
            sf.top = top;
            sf.direction = direction;
            sf.min_speed = min_speed;
            sf.max_speed = max_speed;

            // Add stars
            for (sf.starfield_table) |*star| {
                const x = sf.rnd.random().uintAtMost(u16, WIDTH);
                const y = sf.rnd.random().intRangeAtMost(u16, top, top+height);

                const rnd_speed = sf.rnd.random().intRangeAtMost(u16, min_speed, max_speed);
                star.* = Star{ .x = x, .y = y, .speed = rnd_speed, .direction = direction, .color = @intCast(u8, rnd_speed) };
            }

            return sf;
        }

        pub fn update(self: *Self) void {

            for (self.starfield_table) |*star| {
                if (self.direction == StarfieldDirection.RIGHT) {
                    const new_pos: u16 = star.x + star.speed;

                    if (new_pos > self.width) {
                        star.*.x = 0;
                    } else {
                        star.*.x = new_pos;
                    }
                }
                if (self.direction == StarfieldDirection.LEFT) {
                    const new_pos: i32 = @intCast(i32, star.x) - @intCast(i32, star.speed);

                    if (new_pos >= 0) {
                        star.*.x = star.x - star.speed;
                    } else {
                        star.*.x = self.width;
                    }
                }
            }
        }

        pub fn render(self: *Self) void {

            // plot pixel for each star with palette entry 1
            for (self.starfield_table) |*star| {
                self.fb.setPixelValue(@intCast(u16, star.x), @intCast(u16, star.y), star.color);
            }
        }
    };
}
