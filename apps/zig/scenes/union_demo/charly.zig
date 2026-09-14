// --------------------------------------------------------------------------
// Charly — the Union Demo menu's player (entities.js MainEntity), with the parts
// of melonJS 0.9.8's ObjectEntity it relies on ported as they run: velocity,
// friction, the TMX collision check, and the walk animation.
//
// Everything is in the ORIGINAL map pixels (640-wide world, 32x16 tiles); the
// scene halves only when it draws. The remake disables gravity (entities.js:34),
// so up/down walk Charly along the street rather than jump.
//
// One departure, asked for: the remake's street ENDS (TMXLayer.checkCollision
// stops x at 0 and the map width), this one WRAPS. Charly's x is kept in
// [0, MAP_W) and every collision probe wraps with him; the two ends of the
// Foreground join seamlessly (wall and pavement run straight across).
//
// No ZigOS import: `map` is anything with `cellAt(f32, f32) ?u8` (a
// tilemap.Grid in the scene), so the physics tests natively against the
// reference trace (apps/zig/scene_tests.zig).
// --------------------------------------------------------------------------

pub const SPRITE_W: f32 = 80; // settings.spritewidth (entities.js:19)
pub const SPRITE_H: f32 = 102; // settings.spriteheight (entities.js:20)
pub const FRAMES: u8 = 8; // addAnimation("walk", [0..7]) (entities.js:52)
const ANIM_SPEED: u8 = 2; // me.sys.fps / 30 (entities.js:52)
const BOX_Y: f32 = 82; // updateColRect(-1, -1, 82, 10) (entities.js:60)
const BOX_H: f32 = 10;
const FRICTION: f32 = 0.5; // setFriction(0.5, 0.5) (entities.js:37)
const WALK = [2]f32{ 5, 2 }; // setVelocity(5, 2) = setMaxVelocity(5, 2) (entities.js:30-31)
const FAST = [2]f32{ 8, 8 }; // F1 / S: setVelocity(8, 8) (entities.js:96-97)
pub const MAP_W: f32 = 175 * 32; // TMXLayer.width: where the street wraps

/// Collision layer cell kinds (metatiles32x16: tile 0 "solid", tile 1 "platform").
pub const SOLID: u8 = 1;
pub const PLATFORM: u8 = 2;

/// Keys 1..9, 0 and H teleport in front of a door (entities.js:99-152).
pub const TELEPORTS = [_][2]f32{
    .{ 686, 127 },  .{ 1333, 127 }, .{ 1610, 127 }, .{ 1824, 127 }, .{ 2629, 127 },
    .{ 3028, 127 }, .{ 3531, 127 }, .{ 3962, 127 }, .{ 4236, 127 }, .{ 5436, 127 },
    .{ 2234, 127 }, // H: the hidden TEX tracker door
};

pub const Input = struct {
    left: bool = false,
    right: bool = false,
    up: bool = false,
    down: bool = false,
    fast: bool = false,
    teleport: ?usize = null,
};

/// The collision box (me.Rect with colPos) in map pixels.
pub const Box = struct { left: f32, right: f32, top: f32, bottom: f32 };

pub const Charly = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    accel: [2]f32,
    max: [2]f32,
    falling: bool,
    flip: bool, // facing left (flipX(true))
    frame: u8,
    fpscount: u8,

    pub fn init(self: *Charly, x: f32, y: f32) void {
        self.x = x;
        self.y = y;
        self.vx = 0;
        self.vy = 0;
        self.accel = WALK;
        self.max = WALK;
        self.falling = false;
        self.flip = false;
        self.frame = 0;
        self.fpscount = 0;
    }

    pub fn box(self: *const Charly) Box {
        const top = self.y + BOX_Y;
        return .{ .left = self.x, .right = self.x + SPRITE_W, .top = top, .bottom = top + BOX_H };
    }

    /// One MainEntity.update: steer, updateMovement, animate while moving.
    /// Returns how far the wrap moved x (0, or +-MAP_W on crossing an end), so
    /// the scene can carry its view across the seam with him.
    pub fn update(self: *Charly, in: Input, map: anytype) f32 {
        if (in.left) {
            self.vx -= self.accel[0];
            self.flip = true;
        } else if (in.right) {
            self.vx += self.accel[0];
            self.flip = false;
        }
        if (in.up) {
            self.vy -= self.accel[1];
        } else if (in.down) {
            self.vy += self.accel[1];
        } else if (in.fast) {
            self.accel = FAST;
            self.max = FAST;
        } else if (in.teleport) |t| {
            self.x = TELEPORTS[t][0];
            self.y = TELEPORTS[t][1];
        }
        self.vx = limit(friction(self.vx), self.max[0]);
        self.vy = limit(friction(self.vy), self.max[1]);
        self.collide(map);
        const unwrapped = self.x + self.vx;
        self.x = @mod(unwrapped, MAP_W);
        self.y += self.vy;
        if (self.vx != 0 or self.vy != 0) self.animate();
        return self.x - unwrapped;
    }

    // updateMovement's reaction to TMXLayer.checkCollision (gravity is 0, so
    // `falling` only ever comes from bumping a ceiling). The map-width x limit
    // is gone: probes past either end read the other end instead.
    fn collide(self: *Charly, map: anytype) void {
        const b = self.box();
        const qx = wrapX(if (self.vx < 0) @trunc(b.left + self.vx) else @ceil(b.right - 1 + self.vx));
        const qy = if (self.vy < 0) @trunc(b.top + self.vy) else @ceil(b.bottom - 1 + self.vy);
        const x_kind = if (self.vx != 0) firstSolid(map, .{ qx, @ceil(b.bottom - 1) }, .{ qx, @trunc(b.top) }) else 0;
        const near = wrapX(if (self.vx < 0) @trunc(b.left) else @ceil(b.right - 1));
        const far = wrapX(if (self.vx < 0) @ceil(b.right - 1) else @trunc(b.left));
        const y_kind = firstSolid(map, .{ near, qy }, .{ far, qy });
        if (y_kind != 0) {
            const tile_top = @trunc(qy / 16) * 16;
            if (self.vy >= 0) { // `pv.y || 1`: a zero velocity reads as downward
                if (y_kind == SOLID or (y_kind == PLATFORM and b.bottom - 1 <= tile_top)) {
                    self.y = @trunc(self.y);
                    self.vy = if (self.falling) tile_top - (self.y + BOX_Y + BOX_H) else 0;
                    self.falling = false;
                }
            } else if (y_kind != PLATFORM) {
                self.falling = true;
                self.vy = 0;
            }
        }
        if (x_kind != 0 and x_kind != PLATFORM) self.vx = 0;
    }

    // AnimationSheet.update: `fpscount++ > animationspeed`.
    fn animate(self: *Charly) void {
        const was = self.fpscount;
        self.fpscount += 1;
        if (was > ANIM_SPEED) {
            self.frame = (self.frame + 1) % FRAMES;
            self.fpscount = 0;
        }
    }
};

fn wrapX(x: f32) f32 {
    return @mod(x, MAP_W);
}

// The first collidable cell of two probe points, as checkCollision tries its
// corners in order; 0 if neither is.
fn firstSolid(map: anytype, a: [2]f32, b: [2]f32) u8 {
    const ka = map.cellAt(a[0], a[1]) orelse 0;
    if (ka != 0) return ka;
    return map.cellAt(b[0], b[1]) orelse 0;
}

// me.utils.applyFriction
fn friction(v: f32) f32 {
    if (v + FRICTION < 0) return v + FRICTION;
    if (v - FRICTION > 0) return v - FRICTION;
    return 0;
}

// computeVelocity's cap, applied only to a non-zero velocity.
fn limit(v: f32, max: f32) f32 {
    if (v == 0) return v;
    return @max(-max, @min(max, v));
}
