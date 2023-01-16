// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;

const Sprite = @import("../effects/sprite.zig").Sprite;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: usize = @import("../zigos.zig").HEIGHT;
const WIDTH: usize = @import("../zigos.zig").WIDTH;
pub const NB_BOBS: usize = 312;
// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Bobs = struct {
    fb: *LogicalFB = undefined,
    sprite: Sprite = undefined,
    positions_x: [NB_BOBS]i16 = undefined,
    positions_y: [NB_BOBS]i16 = undefined,


    pub fn init(self: *Bobs, fb: *LogicalFB, sprite_img: []const u8, sprite_width: u16, sprite_height: u16) void {
        self.fb = fb;

        self.sprite.init(fb, sprite_img, sprite_width, sprite_height, 0, 0, false, null);

    }

    pub fn update(self: *Bobs, idx: usize, x_pos: i16, y_pos: i16) void {
        
        self.positions_x[idx] = x_pos;
        self.positions_y[idx] = y_pos;
    }

    pub fn render(self: *Bobs) void {

        var i: u16 = 0;
        while(i < NB_BOBS) : (i += 1) {
            self.sprite.update(self.positions_x[i], self.positions_y[i], null);
            self.sprite.render();
        }
    }
};