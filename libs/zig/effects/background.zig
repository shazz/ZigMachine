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

    // One @memcpy, not a byte loop: the loop stored one byte per pixel (64,000
    // bus writes for a full plane on the board, where the D-cache is
    // write-through) and reloaded the plane pointer around each store.
    pub fn render(self: *Background) void {
        switch (self.target) {
            .fb => |fb| {
                const off: usize = self.pos_y * WIDTH;
                @memcpy(fb.fb[off..][0..self.data.len], self.data);
            },
            .render_buffer => |rbuf| {
                const off: usize = self.pos_y * rbuf.width; // u16 product, as the loop computed it
                @memcpy(rbuf.buffer[off..][0..self.data.len], self.data);
            },
        }
    }
};
