// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const RenderTarget = @import("../zigos.zig").RenderTarget;
const Color = @import("../zigos.zig").Color;

const Sprite = @import("../effects/sprite.zig").Sprite;

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


pub fn Bobs(
    comptime nb_bobs: comptime_int,
) type {
    return struct {

        target: RenderTarget = undefined,
        sprite: Sprite = undefined,
        positions_x: [nb_bobs]i16 = undefined,
        positions_y: [nb_bobs]i16 = undefined,
        images: [nb_bobs][]const u8 = undefined,
        const Self = @This();

        pub fn init(target: RenderTarget, sprite_imgs: [nb_bobs][]const u8, sprite_width: u16, sprite_height: u16) Self {

            var bobs = Self{};
            bobs.images = sprite_imgs;
            bobs.target = target;
            bobs.sprite.init(target, sprite_imgs[0], sprite_width, sprite_height, 0, 0, null, null);

            return bobs;
        }

        pub fn update(self: *Self, idx: usize, x_pos: i16, y_pos: i16) void {
            
            self.positions_x[idx] = x_pos;
            self.positions_y[idx] = y_pos;
        }

        pub fn render(self: *Self) void {

            var i: u16 = 0;
            while(i < nb_bobs) : (i += 1) {
                self.sprite.data = self.images[i];
                self.sprite.update(self.positions_x[i], self.positions_y[i], null, null);
                self.sprite.render(null);
            }
        }
    };
}
