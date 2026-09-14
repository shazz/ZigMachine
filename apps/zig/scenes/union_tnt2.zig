// --------------------------------------------------------------------------
// The Union Demo (1989), TNT2: the TNT-Crew's "Superscroller", ported from
// shazz's melonJS "Union Demo HTML5 Remake" 0.9.8 (screens/tnt2/screen.js,
// loader.js). Program by Hexogen, graphics by ES, Jeroen Tel's Cybernoid
// converted by Mad Max: all The Union's.
//
// On screen, in draw order (screen.js:170-187), one plane, one palette:
//   black, then the logo's shadow (overlay2.png)
//   three parallax bands: blue at -2, brown at -4, green at -6 canvas px a frame
//   the main scrolltext (jsApp.scrolltext) at canvas y 180, 2 px a frame
//   the TNT logo (overlay.png) over everything
//
// The keys play with it (screen.js:94-154): 1..4 or A..D choose blue, brown,
// green or the scroller; Left/Right then set blue to -2/+2, step brown or green
// by 1 a frame, or change the scroller's speed within 0..9 (controls.zig).
//
// Geometry: a 640x400 canvas, every PNG pixel-doubled on the (0,0) grid and
// drawn inside it, so everything halves onto one normal 320x200 plane.
//
// Loading: tnt2.bin depacks for real behind loader.js's TEX panel (fx tex_loader,
// build.zig); its "PRESS SPACE" wait is dropped. Escape or Space leave for the hub.
// The scroller starts at, and hands back, the hub's text offset (mainscrollerPos)
// through the hub's ROM return note (union_demo/hub_note.zig). Adapted: the remake
// also keeps the band speeds across visits; carts share no other state, so they
// start fresh.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hw = @import("hardware");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;
const DepackFx = @import("depackers").depack_fx.Runner(zg, null);
const packed_assets = @import("packed_assets");

const A = @import("union_tnt2/assets.zig");
const motion = @import("union_tnt2/motion.zig");
const controls = @import("union_tnt2/controls.zig");
const hub_note = @import("union_demo/hub_note.zig").HubNote("union_tnt2");

// The remake plays data/music/Cybernoid.ym; this is Mad Max's Cybernoid from
// the same Union Demo folder of the SNDH archive (one subtune, FLAG ~y).
const MUSIC = "union/cybernoid.sndh";
const HUB = "union_demo";
// 221,199 bytes at 8 a line (2,240 a frame) depack in 99 frames, the 99 frames
// (13,820 ms at 140 ms a frame) the remake's panel takes.
const DEPACK_BYTES_PER_LINE = 8;
const K_ESC: u32 = 0xE012;
const SCROLL_SPEED_MAX = 9; // screen.js:129

// Module scope: the runner needs a stable address.
var depack: DepackFx = undefined;

const Phase = enum { loading, running, failed };

pub const Demo = struct {
    phase: Phase,
    images: A.Images,
    blue: motion.Layer,
    brown: motion.Layer,
    green: motion.Layer,
    scroller: motion.Scroller,
    scroll_speed: i32, // this.scrollSpeed
    select: u8, // this.controlsSelect
    keys: controls.Controls,
    leave: bool,
    note: ?hub_note.Note, // the hub's return note, when it was left for this door

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.phase = .failed;
        self.leave = false;
        self.blue.init(-2); // screen.js:39-41
        self.brown.init(-4);
        self.green.init(-6);
        self.note = hub_note.accepted(motion.TEXT.len);
        self.scroller.initAt(if (self.note) |n| n.scroll else 0); // screen.js:33
        self.scroll_speed = 2; // screen.js:30
        self.select = 1;
        self.keys.init();
        const buf = freeRam(A.TOTAL) orelse return fail("no free RAM to depack into");
        if (!depack.start(zigos, packed_assets.union_tnt2, buf, DEPACK_BYTES_PER_LINE))
            return fail("packed image unreadable");
        self.images = A.Images.split(buf);
        self.phase = .loading;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase == .loading) switch (depack.frame(zigos)) {
            .more => return,
            .done => self.start(zigos), // and this frame is the screen's first
            .failed => {
                self.phase = .failed;
                return fail("depack failed");
            },
        };
        if (self.phase != .running) return;
        self.blue.update();
        self.brown.update();
        self.green.update();
        // scrolltext.speed = scrollSpeed is read before the keys change it, and
        // draw() moves the letters by it (screen.js:88, codef_scrolltext.js:105).
        const speed = self.scroll_speed;
        self.applyKeys();
        self.keys.tick();
        self.scroller.step(speed);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase != .running) return;
        const dst = blit.Dst.plane(&zigos.lfbs[0]);
        @memset(dst.buf, A.BLACK); // maincanvas.fill('#000000')
        drawPiece(dst, self.images.overlay2, A.OVERLAY2);
        self.blue.draw(dst, self.images.blue, A.BLUE.y);
        self.brown.draw(dst, self.images.brown, A.BROWN.y);
        self.green.draw(dst, self.images.green, A.GREEN.y);
        self.scroller.draw(dst, self.images.font);
        drawPiece(dst, self.images.overlay, A.OVERLAY);
    }

    /// Letters and Escape are the screen's (A..D must not also steer).
    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    /// Host input ids: 2 left, 3 right, 5 fire, 6 back.
    pub fn input(self: *Demo, dir: u8) void {
        switch (dir) {
            2 => self.press(.left),
            3 => self.press(.right),
            5 => if (self.phase == .running) {
                self.leave = true;
            },
            6 => self.leave = true,
            else => {},
        }
    }

    pub fn key(self: *Demo, cp: u32) void {
        switch (cp) {
            K_ESC => self.leave = true,
            ' ' => if (self.phase == .running) {
                self.leave = true;
            },
            '1'...'4' => self.press(@enumFromInt(cp - '1')),
            'A'...'D' => self.press(@enumFromInt(cp - 'A')),
            'a'...'d' => self.press(@enumFromInt(cp - 'a')),
            else => {},
        }
    }

    pub fn pollCart(self: *Demo) i32 {
        if (!self.leave) return 0;
        self.leave = false;
        // screen.js:91 keeps mainscrollerPos current on every update; leaving
        // from the loader, the screen never ran and the hub's position stands.
        if (self.phase == .running) if (self.note) |n| hub_note.handBack(n, self.scroller.next());
        return 1;
    }

    pub fn cartTag(self: *Demo) []const u8 {
        _ = self;
        return HUB;
    }

    fn press(self: *Demo, a: controls.Action) void {
        if (self.phase == .running) self.keys.press(a);
    }

    /// screen.js:99-154, the else-if chain on this frame's keys.
    fn applyKeys(self: *Demo) void {
        const a = self.keys.active() orelse return;
        const step: i32 = switch (a) {
            .one, .two, .three, .four => {
                self.select = @intFromEnum(a) + 1;
                return;
            },
            .left => -1,
            .right => 1,
        };
        switch (self.select) {
            1 => self.blue.speed = 2 * step,
            2 => self.brown.speed +|= step,
            3 => self.green.speed +|= step,
            // left speeds the scroller up, right slows it down
            4 => self.scroll_speed = @max(0, @min(SCROLL_SPEED_MAX, self.scroll_speed - step)),
            else => {},
        }
    }

    fn start(self: *Demo, zigos: *ZigOS) void {
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(A.palette);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        zg.requestSong(MUSIC); // onResetEvent
        self.phase = .running;
    }
};

fn drawPiece(dst: blit.Dst, img: blit.Image, p: A.Piece) void {
    blit.blit(dst, img, null, p.x, p.y, 0, .copy);
}

fn fail(why: []const u8) void {
    zg.Console.log("union_tnt2: {s}", .{why});
}

/// `len` bytes of the cart's RAM window above its statics and stack.
fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}
