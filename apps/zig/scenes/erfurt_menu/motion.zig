// --------------------------------------------------------------------------
// How the drum moves: two independent things.
//
// SPIN ($113A6-$114D4): `pos` is the drum's angle in texture lines, 24.8 fixed
// point, wrapping at 4608 lines. Up/Down HELD ease the speed toward +-512 an
// eighth of the gap a frame; on release a target face is picked in the
// direction of travel (separators skipped), and a damped spring
// (vel = vel/2 + gap/16) brings the drum onto it, snapping within 16.
//
// JELLY ($12A5A): the drum's top, bottom and middle are three masses (24.8)
// under gravity $18, a spring holding top-to-bottom at 90 lines and the middle
// trailing the midpoint. The bottom sits on a floor at line 166. Every 350
// idle frames the top gets the 21-step "hop" impulse table ($1F91A): the drum
// squashes, jumps and wobbles. The top/middle/bottom gaps pick the radius of
// the upper and lower half-cylinders (30..50 lines each).
//
// Every operation keeps the original's widths: words wrap, `asr` rounds down.
// --------------------------------------------------------------------------
const A = @import("assets.zig");

pub const LINES: i32 = 4608; // $60C94: the drum's circumference in texture lines
pub const FACE: i32 = 24; // $40ECE
pub const ITEMS: i32 = 16; // $313BE
pub const MARK: i32 = 72; // $4CD0A: the marker's distance from the drum's angle
const REST: i32 = (2 * 45) << 8; // $64C7C: top-to-bottom rest length
const FLOOR_LINE: i32 = 167; // $4EBC8
const R_MIN: i16 = 30; // $41086: the first config's radius
const R_MAX: i16 = 50; // $40EF0
const HOP_WAIT: u16 = 0x15E;

pub const Motion = struct {
    // spin
    pos: i32,
    target: i32,
    vel: i16,
    moving: bool, // $5B2EE: a key was held, a target is still to pick
    up: bool,
    down: bool,
    // jelly
    top: i32,
    bot: i32,
    mid: i32,
    v_top: i16,
    v_bot: i16,
    v_mid: i16,
    floor: i32,
    on_floor: bool,
    hop_wait: u16,
    hop: u16, // $64C8C: index into the kick table, 0 = not hopping
    // what the drum looks like this frame
    r_a: i16, // upper half radius
    r_b: i16, // lower half radius
    hop_h: i16, // $64C86: how far the bottom is off the floor (24.8, word)
    drum_top: i16, // $4EBB8

    pub fn init(self: *Motion, start: i32) void {
        self.pos = faceOf(start);
        self.target = self.pos;
        self.vel = 0;
        self.moving = false;
        self.up = false;
        self.down = false;
        // $12A00
        self.floor = (FLOOR_LINE - 1) << 8;
        self.bot = self.floor;
        self.top = self.floor - REST + 0x300;
        self.mid = (self.top + self.bot) >> 1;
        self.v_top = 0;
        self.v_bot = 0;
        self.v_mid = 0;
        self.on_floor = true;
        self.hop_wait = HOP_WAIT;
        self.hop = 0;
        self.shape();
    }

    /// $11CF6: the angle that puts `item`'s face under the marker.
    pub fn faceOf(entry: i32) i32 {
        var d = entry * FACE + @divTrunc(FACE, 2) - MARK;
        if (d < 0) d += LINES;
        return d << 8;
    }

    /// $116C0: the angle in whole texture lines, 0..4607.
    pub fn line(self: *const Motion) i32 {
        var d = self.pos >> 8;
        if (d < 0) d += LINES;
        if (d >= LINES) d -= LINES;
        return d;
    }

    /// $11CCE: which item is under the marker.
    pub fn item(self: *const Motion) i32 {
        const q = @divTrunc(self.line() + MARK, FACE) & 0xFFFF;
        return @mod(q, ITEMS);
    }

    pub fn settled(self: *const Motion) bool {
        return !self.moving and self.pos == self.target;
    }

    /// $12C68: anything moving (the sparkle and the hop wait for a still drum).
    pub fn busy(self: *const Motion) bool {
        if (self.hop != 0 or self.hop_h != 0) return true;
        const v: u16 = @bitCast(self.v_top +% 16);
        if (v >= 0x20) return true;
        if (self.up or self.down) return true;
        return self.pos != self.target;
    }

    /// $113A6-$114D4, once a frame. `selectable` says whether an item may be landed on.
    pub fn spin(self: *Motion, selectable: *const fn (i32) bool) void {
        const keys: i16 = @as(i16, @intFromBool(self.down)) - @as(i16, @intFromBool(self.up));
        if (keys != 0) {
            const want: i16 = @truncate(@as(i32, keys) << 9);
            self.vel = toward(want -% self.vel) +% self.vel;
            self.moving = true;
            self.pos += self.vel;
            self.wrap();
            return;
        }
        if (self.moving) {
            self.moving = false;
            self.target = self.pickTarget(selectable);
        }
        const gap = self.target - self.pos;
        if (gap == 0 and self.vel == 0) return;
        if (@abs(gap) <= 16 and @abs(@as(i32, self.vel)) <= 16) {
            self.vel = 0;
            self.pos = self.target;
            self.wrap();
            self.target = self.pos;
            return;
        }
        self.vel = (self.vel >> 1) +% @as(i16, @truncate(gap >> 4));
        self.pos += self.vel;
    }

    fn pickTarget(self: *const Motion, selectable: *const fn (i32) bool) i32 {
        var d = self.line() + MARK - @divTrunc(FACE, 2);
        var face: i32 = undefined;
        var step: i32 = 1;
        if (self.vel >= 0) {
            face = @divTrunc(d, FACE) + 1;
        } else {
            d += FACE - 1;
            face = @divTrunc(d, FACE) - 1;
            step = -1;
        }
        while (!selectable(@mod(face, ITEMS))) face += step; // $12EAA
        face &= 0xFFFF;
        return (face * FACE + @divTrunc(FACE, 2) - MARK) << 8;
    }

    fn wrap(self: *Motion) void { // $1169E
        const span = LINES << 8;
        if (self.pos < 0) self.pos += span;
        if (self.pos >= span) self.pos -= span;
    }

    /// $12A5A: the jelly, once a frame.
    pub fn jelly(self: *Motion) void {
        var kick: i16 = 0;
        if (self.hop == 0 and self.on_floor and @abs(@as(i32, self.v_top)) < 16) {
            self.hop_wait -%= 1;
            if (self.hop_wait == 0) {
                if (self.up or self.down or self.pos != self.target) self.hop_wait = 1 else self.hop = 1;
            }
        }
        if (self.hop != 0) {
            kick = A.beSigned(A.kick, self.hop - 1);
            self.hop += 1;
            if (self.hop > 21) {
                self.hop = 0;
                self.hop_wait = HOP_WAIT;
            }
        }
        var f: i16 = @truncate((self.bot - self.top - REST) >> 5);
        f +%= (self.v_bot -% self.v_top) >> 4;
        self.v_top +%= kick +% 0x18 +% f;
        self.v_bot +%= 0x18 -% f;
        self.top += self.v_top;
        self.bot += self.v_bot;
        self.on_floor = false;
        if (self.floor <= self.bot) {
            self.bot = self.floor;
            self.v_bot = 0;
            self.on_floor = true;
        }
        var m: i16 = @truncate((((self.top + self.bot) >> 1) - self.mid) >> 4);
        m +%= self.v_mid;
        m -%= m >> 2;
        self.v_mid = m;
        self.mid += m;
        self.shape();
    }

    /// $12BB4: the two half radii and where the drum sits on screen.
    fn shape(self: *Motion) void {
        var h: i16 = @truncate((self.bot - self.top + 0x80) >> 8);
        h = @max(h, 2 * R_MIN);
        h = @min(h, 2 * R_MAX);
        var upper: i16 = @truncate((self.mid - self.top + 0x80) >> 8);
        const lo = @max(R_MIN, h - R_MAX);
        const hi = @min(R_MAX, h - R_MIN);
        upper = @max(upper, lo);
        upper = @min(upper, hi);
        self.r_a = upper;
        self.r_b = h - upper;
        self.hop_h = @truncate(self.floor - self.bot);
        const lift: i16 = @bitCast(@as(u16, @bitCast(self.hop_h +% 0x80)) >> 8);
        self.drum_top = @as(i16, FLOOR_LINE) - (self.r_a + self.r_b + 1) - lift;
    }
};

/// $11688: an eighth of the gap, never less than one step, sign kept.
/// The magnitude is taken as a word (`neg.w` of $8000 is $8000, read unsigned),
/// so d = -32768 gives -$1000 instead of overflowing the i16 negate.
fn toward(d: i16) i16 {
    if (d == 0) return 0;
    const mag: u16 = if (d < 0) @bitCast(0 -% d) else @bitCast(d);
    const e: i16 = @bitCast(@max(mag >> 3, 1));
    return if (d < 0) -e else e;
}
