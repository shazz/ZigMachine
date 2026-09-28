// --------------------------------------------------------------------------
// The camera and the parallax, as melonJS 0.9.2 runs them for this remake.
//
// me.game.init(768, 480) makes a 768x480 viewport whose dead zone is
// setDeadzone(w / 6, h / 6): x 320..448, y ~~((480 - 80) / 2 - 80 * 0.25) = 180
// ..300, measured from the view's edge against the griffin's pos (top-left:
// viewport.follow(this.pos) follows the vector, not the sprite's centre). The
// view is kept within the map (setBounds(realwidth, realheight)) and lands on
// ~~ integers. It updates every frame: the CODEF overlay object returns true
// from update(), so the draw manager is always dirty.
//
// parallax_background is a ParallaxBackgroundEntity with ONE layer, back.png at
// scrollspeed 1: each DRAW in which the view moved right its offset steps +1,
// left -1 (mod the image width), whatever the distance; the view's y is ignored
// (the image is drawn at canvas row 0 every frame). It starts with lastx at the
// view's x when the level loaded, 0.
//
// No ZigOS import: tests natively.
// --------------------------------------------------------------------------

pub const VIEW_W: f64 = 768; // me.game.init(768, 480) (main.js:37)
pub const VIEW_H: f64 = 480;
const DEAD_X = [2]f64{ 320, 448 };
const DEAD_Y = [2]f64{ 180, 300 };
pub const BACK_W: i32 = 32; // back.png

pub const View = struct {
    x: f64,
    y: f64,
    limit_x: f64,
    limit_y: f64,

    /// viewport.reset() then setBounds(map_w, map_h): the view at 0, 0.
    pub fn init(self: *View, map_w: f64, map_h: f64) void {
        self.x = 0;
        self.y = 0;
        self.limit_x = map_w - VIEW_W;
        self.limit_y = map_h - VIEW_H;
    }

    /// Viewport.update(true): _followH then _followV on the target's pos.
    pub fn follow(self: *View, tx: f64, ty: f64) void {
        self.x = axis(self.x, tx, DEAD_X, self.limit_x);
        self.y = axis(self.y, ty, DEAD_Y, self.limit_y);
    }
};

fn axis(view: f64, target: f64, dead: [2]f64, limit: f64) f64 {
    if (target - view > dead[1]) return @trunc(@min(target - dead[1], limit));
    if (target - view < dead[0]) return @trunc(@max(target - dead[0], 0));
    return view;
}

pub const Parallax = struct {
    offset: i32, // ~~baseOffset: back.png's column at the canvas's left edge
    last_x: f64,

    pub fn init(self: *Parallax, view_x: f64) void {
        self.offset = 0;
        self.last_x = view_x;
    }

    /// ParallaxBackgroundEntity.draw's bookkeeping, once per drawn frame.
    pub fn step(self: *Parallax, view_x: f64) void {
        if (view_x > self.last_x) self.offset = @mod(self.offset + 1, BACK_W);
        if (view_x < self.last_x) self.offset = @mod(BACK_W + self.offset - 1, BACK_W);
        self.last_x = view_x;
    }
};

test "the view follows the griffin out of its dead zone, clamped to the map" {
    const std = @import("std");
    var v: View = undefined;
    v.init(700 * 32, 40 * 32);
    v.follow(1152, 800); // MainEntity.init's forced update, measured in Chrome
    try std.testing.expectEqual(@as(f64, 704), v.x);
    try std.testing.expectEqual(@as(f64, 500), v.y);
    v.follow(1157.5, 800);
    try std.testing.expectEqual(@as(f64, 709), v.x);
    v.follow(0, 5000);
    try std.testing.expectEqual(@as(f64, 0), v.x);
    try std.testing.expectEqual(@as(f64, 800), v.y);
}
