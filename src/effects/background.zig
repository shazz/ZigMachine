// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const RenderTarget = @import("../zigos.zig").RenderTarget;
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
    target: RenderTarget = undefined,
    data: []const u8 = undefined,
    pos_y: u16 = 0,

    pub fn init(self: *Background, target: RenderTarget, data: []const u8, pos_y: u16) void {
        self.target = target;
        self.data = data;
        self.pos_y = pos_y;
    }

    pub fn update(self: *Background) void {
        _ = self;
    }

    pub fn render(self: *Background) void {

        switch (self.target) {
            .fb => |fb| {
                var buffer: *[64000]u8 = &fb.fb;
                
                // Copy bitmap data
                for (self.data) |value, index| {
                    buffer[index + (self.pos_y * WIDTH)] = value;
                }
            },
            .render_buffer => |rbuf| {
                for (self.data) |value, index| {
                    rbuf.buffer[index + (self.pos_y * rbuf.width)] = value;
                }   
            }
        }
    }
};
