// --------------------------------------------------------------------------
// The menu's winged griffin: entities.js MainEntity, with the parts of melonJS
// 0.9.2's ObjectEntity it runs on ported as they run -- gravity, friction, the
// velocity caps, TiledLayer.checkCollision and updateMovement's reaction to it,
// and the AnimationSheet frame counter.
//
// Everything is in the ORIGINAL map pixels (768-wide canvas, 32x32 tiles), in
// f64 as JavaScript computes it, so a trace matches the remake's to the bit.
// me.timer.tick is always 1 (me.sys.interpolation is off), so a step is one
// 1/60 s update and the constants below are per step.
//
// No ZigOS import: `map` is anything with `cellAt(f64, f64) u8` (Level), so
// the physics tests natively.
// --------------------------------------------------------------------------

pub const SIZE: f64 = 64; // settings.spritewidth / spriteheight (entities.js:17-18)
const ACCEL = [2]f64{ 6, 2 }; // setVelocity(6, 2) (entities.js:24)
const MAX_VEL = [2]f64{ 6, 4 }; // setMaxVelocity(6, 4) (entities.js:25)
const FRICTION: f64 = 0.5; // setFriction(0.5): x only, y = 0 (entities.js:28)
const GRAVITY: f64 = 0.98; // ObjectEntity default
const BOX_Y: f64 = 20; // updateColRect(0, 64, 20, 44) (entities.js:55)
const ANIM_SPEED: u8 = 6; // me.sys.fps / 10 (entities.js:52)

/// Collision layer kinds (metatiles32x32: tile 0 "solid", tile 1 "platform").
pub const SOLID: u8 = 1;
pub const PLATFORM: u8 = 2;
/// A probe outside the map's width: checkCollision reports it with no
/// properties, which updateMovement treats as a wall.
const EDGE: u8 = 255;

/// addAnimation("walk", [4..7]) / ("fly", [8..11]): 4 frames each, from
/// sprite 4 and 8 of the 4-wide sheet.
pub const Anim = enum(u8) { walk = 4, fly = 8 };

pub const Input = struct { left: bool = false, right: bool = false, fly: bool = false };

/// The collision box (me.Rect with colPos) in map pixels.
pub const Box = struct { left: f64, right: f64, top: f64, bottom: f64 };

pub const Griffin = struct {
    x: f64,
    y: f64,
    vx: f64,
    vy: f64,
    falling: bool,
    flip: bool, // flipX(true): facing left
    anim: Anim,
    idx: [2]u8, // each animation keeps its own frame (walk, fly)
    fpscount: u8, // shared by both, as the AnimationSheet's

    /// ObjectEntity.init puts the sprite's bottom on the Tiled object's tile:
    /// pos.y = y + tileheight - height.
    pub fn init(self: *Griffin, x: f64, y: f64, tile: f64) void {
        self.x = x;
        self.y = y + tile - SIZE;
        self.vx = 0;
        self.vy = 0;
        self.falling = false;
        self.flip = false;
        self.anim = .walk;
        self.idx = .{ 0, 0 };
        self.fpscount = 0;
    }

    pub fn box(self: *const Griffin) Box {
        return .{ .left = self.x, .right = self.x + SIZE, .top = self.y + BOX_Y, .bottom = self.y + SIZE };
    }

    /// The sprite (0..15 on the sheet) the current frame shows.
    pub fn sprite(self: *const Griffin) u8 {
        return @intFromEnum(self.anim) + self.idx[@intFromBool(self.anim == .fly)];
    }

    /// One MainEntity.update, up to me.game.collide (the scene's door check).
    pub fn update(self: *Griffin, in: Input, map: anytype) void {
        if (in.left) {
            self.vx -= ACCEL[0];
            self.flip = true;
        } else if (in.right) {
            self.vx += ACCEL[0];
            self.flip = false;
        }
        if (in.fly) {
            self.vy -= ACCEL[1];
            // "no proper bounciness support yet": bounce off the map's top
            if (self.y + self.vy < 0) self.vy = MAX_VEL[1];
        }
        self.computeVelocity();
        self.collide(map);
        self.x += self.vx;
        self.y += self.vy;
        self.animate(in.fly);
    }

    fn computeVelocity(self: *Griffin) void {
        self.vy += GRAVITY;
        self.falling = self.vy > 0;
        self.vx = friction(self.vx);
        if (self.vy != 0) self.vy = clamp(self.vy, MAX_VEL[1]);
        if (self.vx != 0) self.vx = clamp(self.vx, MAX_VEL[0]);
    }

    // TiledLayer.checkCollision then updateMovement's response (0.9.2: no
    // slopes, ladders or breakables on this map).
    fn collide(self: *Griffin, map: anytype) void {
        const b = self.box();
        const left_way = self.vx < 0;
        const qx = if (left_way) b.left + self.vx else b.right + self.vx;
        const qy = if (self.vy < 0) b.top + self.vy else b.bottom + self.vy;
        const x_kind: u8 = if (qx <= 0 or qx >= map.width()) EDGE else first(map, qx, b.bottom - 1, qx, b.top);
        const y_kind = first(map, if (left_way) b.left else b.right, qy, if (left_way) b.right else b.left, qy);
        if (y_kind != 0) self.landOrBump(y_kind, @floor(qy / map.tile()) * map.tile());
        if (x_kind != 0 and x_kind != PLATFORM) self.vx = 0;
    }

    // `d.y = k.y || 1`: a zero velocity reads as downward.
    fn landOrBump(self: *Griffin, kind: u8, tile_top: f64) void {
        if (!(self.vy < 0)) {
            if (kind == SOLID or (kind == PLATFORM and @trunc(self.y) + SIZE <= tile_top)) {
                self.y = @trunc(self.y);
                self.vy = if (self.falling) tile_top - self.y - SIZE else 0;
                self.falling = false;
            }
        } else if (kind != PLATFORM) {
            self.falling = true;
            self.vy = 0;
        }
    }

    // The animation switch and AnimationSheet.update (entities.js:88-115):
    // a walk frame only advances while moving sideways.
    fn animate(self: *Griffin, fly: bool) void {
        self.anim = if (fly) .fly else .walk;
        if (self.vx == 0 and self.vy == 0) return;
        if (self.anim == .walk and self.vx == 0) return;
        const was = self.fpscount;
        self.fpscount += 1;
        if (was > ANIM_SPEED) {
            const i = &self.idx[@intFromBool(self.anim == .fly)];
            i.* = (i.* + 1) % 4;
            self.fpscount = 0;
        }
    }
};

/// The first collidable cell of two probe points, as checkCollision tries them.
fn first(map: anytype, ax: f64, ay: f64, bx: f64, by: f64) u8 {
    const a = map.cellAt(ax, ay);
    return if (a != 0) a else map.cellAt(bx, by);
}

// me.utils.applyFriction
fn friction(v: f64) f64 {
    if (v + FRICTION < 0) return v + FRICTION;
    if (v - FRICTION > 0) return v - FRICTION;
    return 0;
}

fn clamp(v: f64, max: f64) f64 {
    return @max(-max, @min(max, v));
}
