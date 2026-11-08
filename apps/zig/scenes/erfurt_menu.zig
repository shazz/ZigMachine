// --------------------------------------------------------------------------
// THE ERFURT MEGADEMO — the main menu (Atari Scene Collective, ST/STE, 31 Oct
// 2026; put together by 505, Slippy and Jade; menu and loader Slippy, music
// Doclands). Ported from the ORIGINAL (protected) disks: the menu was extracted
// and read as 68000. How it
// works, the protection included: prototypes/erfurt_re/ANALYSIS.md.
//
// On screen, top to bottom: Jade's ERFURT logo (4 planes, a glint sweeping it
// every 322 frames); a rainbow line, colour 0 rewritten 42 times along it,
// borders included; the DRUM, the 16 entries of both disks round a cylinder
// that you spin with Up/Down, its front face in plane 0, its back face seen
// through in plane 1, the marker band where the drum faces you; a wavy
// scroller in plane 2 that passes behind the front face and in front of the
// back; the drum's shadow on a moving chequered floor; a last rainbow line.
// The drum is a jelly: it squashes, hops and wobbles on its own every 350
// still frames.
//
// Space on an entry: the menu's own exit fade (7 steps, one every 3 frames),
// then where the loader would run the part the screen stays dark for a
// second, and the menu comes back settled on that entry with the scroller
// where it was (the real menu is reloaded after every part, told the same).
// Typing ERFURT26 opens the hidden part the same way. Escape leaves.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Console = zg.Console;

const A = @import("erfurt_menu/assets.zig");
const S = @import("erfurt_menu/screen.zig");
const P = @import("erfurt_menu/palette.zig");
const M = @import("erfurt_menu/motion.zig");
const D = @import("erfurt_menu/drum.zig");
const Sc = @import("erfurt_menu/scroller.zig");
const E = @import("erfurt_menu/effects.zig");

// "Low Signals" by Doclands (Rhyme Tracker pre-release, YMXR player): the
// SNDH the menu carries at $20B68 (init $20B68, exit $20B6C, play $20B70 from
// the VBL), ripped with the 33 KB work buffer that follows it. It is not in the
// SNDH archive (no title or composer match in prototypes/sndh_lf), so this is
// the menu's own copy. sndh_headless: PASS, peak 0.99.
const MUSIC = "erfurt_menu.sndh";
const K_ESC: u32 = 0xE012;
const SECRET = "ERFURT26"; // $11A9E: the scancodes of E R F U R T 2 6
const HIDDEN: i32 = 16;
const AWAY_FRAMES: u16 = 50; // the dark second where a part would run

const State = enum { running, fading, away };

pub const Demo = struct {
    motion: M.Motion,
    drum: D.Drum,
    scroller: Sc.Scroller,
    floor: E.Floor,
    glint: E.Glint,
    sparkle: E.Sparkle,
    phase: u16, // $4EB8E
    phase_t: u16, // $4EB96
    phase_acc: u16, // $4EB94
    rain: u16, // $843DC
    parity: u1, // which of the ST's two screens this frame is
    state: State,
    fade: u8, // steps done
    tick: u8, // $4EB92
    away: u16,
    chosen: i32,
    secret: usize, // $313B6
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("erfurt_menu: The Erfurt Megademo's menu (Atari Scene Collective 2026)", .{});
        const fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setOverscanScrollPlane(S.BUF_W, zg.PHYSICAL_HEIGHT);
        fb.setScroll(S.SCROLL_X, 0);
        fb.clearFrameBuffer(S.BG);
        S.alloc();
        self.wants_quit = false;
        self.secret = 0;
        self.rain = 0;
        self.start(firstOnDisk(), 0);
        zigos.setHBLHandler(S.borderHbl);
        fb.setFrameBufferHBLHandlerPure(zg.OVERSCAN_MAGIC_X, S.planeHbl); // pure: its own palette + flickerBorder only
        zg.requestSong(MUSIC);
    }

    /// $1091E onwards: the menu as the loader starts it, on `item`.
    fn start(self: *Demo, item: i32, text_pos: usize) void {
        S.clear();
        S.invalidate();
        for (0..2) |c| {
            for (0..S.LOGO_ROWS) |y| {
                for (0..S.WORDS) |w| S.logo[c][y][w] = A.be(A.logo, y * S.WORDS + w);
            }
        }
        self.motion.init(item);
        self.drum.init();
        self.scroller.init(text_pos);
        self.floor.init();
        self.glint.init();
        self.sparkle.init();
        self.phase = 0;
        self.phase_t = 0;
        self.phase_acc = 0;
        self.parity = 0;
        self.state = .running;
        self.fade = 0;
        self.tick = 0;
    }

    pub fn input(self: *Demo, dir: u8) void {
        switch (dir) {
            0 => self.motion.up = true,
            1 => self.motion.down = true,
            5 => self.select(),
            else => {},
        }
    }

    pub fn inputRelease(self: *Demo, dir: u8) void {
        switch (dir) {
            0 => self.motion.up = false,
            1 => self.motion.down = false,
            else => {},
        }
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) {
            self.wants_quit = true;
            return;
        }
        const up = if (cp >= 'a' and cp <= 'z') cp - 32 else cp;
        if (up == SECRET[self.secret]) {
            self.secret += 1;
            if (self.secret == SECRET.len) {
                self.secret = 0;
                if (self.state == .running) self.leave(HIDDEN, D.hidden_title);
            }
        } else {
            self.secret = @intFromBool(up == SECRET[0]);
        }
    }

    /// $11B12: Space starts what is under the marker, once the drum is still.
    fn select(self: *Demo) void {
        if (self.state != .running or !self.motion.settled()) return;
        const it = self.motion.item();
        if (!D.selectable(it)) return;
        self.leave(it, D.items[@intCast(it)].text);
    }

    fn leave(self: *Demo, item: i32, title: []const u8) void {
        Console.log("erfurt_menu: {s} chosen -- the loader would run that part now", .{title});
        self.chosen = item;
        self.state = .fading;
        self.fade = 0;
        self.tick = 0;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.rain = (self.rain + 1) % P.RAIN_PERIOD; // $13FEA, in the Timer-B handler: always
        switch (self.state) {
            .running => self.frame(),
            .fading => self.fadeOut(),
            .away => {
                self.away += 1;
                if (self.away >= AWAY_FRAMES) self.start(nextItem(self.chosen), self.scroller.textPos());
            },
        }
    }

    /// $1157A: a step every 3 VBLs; after 7 the screen is cleared and the menu quits.
    fn fadeOut(self: *Demo) void {
        self.tick += 1;
        if (self.tick < 3) return;
        self.tick = 0;
        self.fade += 1;
        if (self.fade < 7) return;
        S.clear();
        for (S.logo) |*c| for (c) |*r| @memset(r, 0);
        self.state = .away;
        self.away = 0;
    }

    /// One frame of $1135A, in its order, and the VBL's colour phase.
    fn frame(self: *Demo) void {
        self.parity ^= 1;
        const m = &self.motion;
        m.jelly(); // $12A5A
        const n: i32 = @as(i32, m.r_a) + m.r_b + 1;
        self.scroller.step(m.drum_top, n); // $13D0E
        self.scroller.draw(S.st);
        m.spin(&D.selectable); // $113A6
        self.drum.faces(m.line()); // $116DE
        self.drum.setShape(m.r_a, m.r_b);
        self.drum.draw(S.st, m.drum_top, m.line()); // $11D38
        self.floor.draw(S.st); // $11F66
        E.shadow(S.st, m.hop_h); // $1221A
        self.sparkle.draw(S.st, m.busy(), m.drum_top, m.drum_top + n - 1); // $12350
        self.glint.step(&S.logo[self.parity]); // $126E8
        // VBL $10FEE: the colour ramps' phase
        self.phase_t = (self.phase_t + 1) & 255;
        const d: u16 = @bitCast((A.sinAt(self.phase_t) >> 4) +% 0xC0 +% @as(i16, @bitCast(self.phase_acc)));
        self.phase_acc = d & 255;
        self.phase += d >> 8;
        if (self.phase >= 0x99) self.phase -= 0x99;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb: *LogicalFB = &zigos.lfbs[0];
        const m = &self.motion;
        const f = P.Frame{
            .phase = self.phase,
            .rain = self.rain,
            .drum_top = m.drum_top,
            .n = @as(i32, m.r_a) + m.r_b + 1,
            .r_a = m.r_a,
            .fade = self.fade,
        };
        P.build(&f);
        if (self.state == .fading) return; // the original freezes the picture while it fades
        S.compose(fb, self.parity); // only what changed
    }
};

/// $10F02: no part played yet, so the drum starts on the inserted disk's
/// separator and steps to the first entry it may land on.
fn firstOnDisk() i32 {
    return nextItem(0);
}

/// $10F14: the first selectable entry from `item` on (past the end: from 0).
fn nextItem(item: i32) i32 {
    var i = if (item >= M.ITEMS) 0 else item;
    while (!D.selectable(@mod(i, M.ITEMS))) i += 1;
    return @mod(i, M.ITEMS);
}
