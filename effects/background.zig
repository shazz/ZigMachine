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
pub const Background = struct {
    fb: *LogicalFB = undefined,
    data: *const [64000]u8 = undefined,

    pub fn init(fb: *LogicalFB, data: *const [64000]u8) Background {
        return .{ .fb = fb, .data = data };
    }

    pub fn update(self: *Background) void {
        _ = self;
    }

    pub fn render(self: *Background) void {
        var buffer: *[64000]u8 = &self.fb.fb;

        // Copy bitmap data
        for (self.data) |value, index| {
            buffer[index] = value;
        }
    }
};
