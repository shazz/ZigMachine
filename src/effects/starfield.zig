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

// starfield
const NB_STARS: u32 = 90;

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
    starfield_table: [NB_STARS]Star = undefined,
    fb: *LogicalFB = undefined,
    width: u16 = undefined,
    height: u16 = undefined,
    speed: u16 = undefined,
    direction: StarfieldDirection = undefined,

    pub fn init(self: *Starfield, fb: *LogicalFB, width: u16, height: u16, speed: u16, direction: StarfieldDirection, background_transparency: u8) void {
        self.fb = fb;
        self.rnd = RndGen.init(0);
        self.width = width;
        self.height = height;
        self.speed = speed;
        self.direction = direction;

        // Set palette
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = background_transparency });
        fb.setPaletteEntry(1, Color{ .r = 255, .g = 255, .b = 255, .a = 255 });

        // Clear
        fb.clearFrameBuffer(0);

        // Add stars
        for (self.starfield_table) |*star| {
            const x = self.rnd.random().uintAtMost(u16, WIDTH);
            const y = self.rnd.random().uintAtMost(u8, HEIGHT);

            star.* = Star{ .x = x, .y = y, .speed = self.rnd.random().intRangeAtMost(u16, 1, speed), .direction = direction };
            fb.setPixelValue(x, y, 1);
        }
    }

    pub fn update(self: *Starfield) void {

        // clear buffer
        self.fb.clearFrameBuffer(0);

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
            self.fb.setPixelValue(@intCast(u16, star.x), @intCast(u16, star.y), 1);
        }
    }

    pub fn render(self: *Starfield) void {

        // plot pixel for each star with palette entry 1
        for (self.starfield_table) |*star| {
            self.fb.setPixelValue(@intCast(u16, star.x), @intCast(u16, star.y), 1);
        }
    }
};
