// --------------------------------------------------------------------------
// KICK OFF 2 — the curated friendly: England vs Spain, one player vs the CPU,
// faithful to the olivierh59500 Go/Ebitengine remake's engine (the original's
// 16.16 physics, control and keeper code), on the ST's 320x200 plane with the
// ripped style-1 kit sheets and the curated digi bank.
//
// Phases: title (FIRE = kick off) -> the match (two 5-min halves at PAL 50 Hz,
// the clock running only while in play, exactly as the source's periods do) ->
// half time (FIRE to continue) -> full time (FIRE back to the title).
// Escape leaves the match for the title; Escape on the title leaves the cart.
//
// Sound is the original's sampled kicks/whistles/bounce set as one-shot digi
// through the scene's own audio ring — samples only (no MOD bed, no SNDH), as
// requested for this port.
//
// The graphics, sounds and game design are Dino Dini / Anco / Human's.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const g = @import("kickoff2/gs.zig");
const players = @import("kickoff2/players.zig");
const pitch = @import("kickoff2/pitch.zig");
const sfx = @import("kickoff2/sfx.zig");

// --- key codes (the host's codec: printables as the character, arrows/side
// keys as private-use words; the FPGA glass sends arrows on key() too) ---
const K_SPACE: u32 = 32;
const K_ENTER: u32 = 13;
const K_Z: u32 = 122;
const K_X: u32 = 120;
const K_ESC: u32 = 0xE012;
const K_UP: u32 = 0xE020;
const K_DOWN: u32 = 0xE021;
const K_LEFT: u32 = 0xE022;
const K_RIGHT: u32 = 0xE023;

var keysDown: u8 = 0; // bit0 up, 1 down, 2 left, 3 right
var fireDown = false;
var escapeDown = false;

pub var match: players.MatchP = .{};
var cam: pitch.Camera = .{};
pub var screenFB: [*]u8 = undefined; // published to the testapi (the plane's fb)

pub const Demo = struct {
    phase: enum { title, match, half_time, full_time } = .title,
    tickAccum: f32 = 0,
    firePrev: bool = false, // the previous tick's fire, for rising-edge detection
    needRepaint: bool = true, // the title frame is painted once (render clears it)

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        pitch.setup(zigos);
        screenFB = zigos.lfbs[0].fb;
        sfx.init();
        match = .{};
        players.init(&match);
        cam.reset();
        self.phase = .title;
        self.tickAccum = 0;
        self.firePrev = false;
        self.needRepaint = true;
    }

    pub fn update(self: *Demo, _: *ZigOS, dt_ms: f32) void {
        sfx.update(dt_ms); // the audio ring runs at the host's own pace
        if (std.math.isFinite(dt_ms) and dt_ms > 0) {
            // dt is HOST MILLISECONDS (sealed-loader passes the rAF delta in ms).
            // Keep it fractional: at 60 Hz that is 16.67 ms/frame, and flooring to
            // 16 would run the match at 48 Hz instead of the Go's 50 (SetTPS(50)).
            self.tickAccum += @min(dt_ms, 200.0);
        }
        while (self.tickAccum >= 20.0) {
            self.tickAccum -= 20.0;
            self.tick50();
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, _: f32) void {
        switch (self.phase) {
            .title => {
                if (self.needRepaint) {
                    self.needRepaint = false;
                    showTitle(zigos);
                }
            },
            .match => renderMatch(zigos),
            .half_time, .full_time => {
                renderMatch(zigos);
                renderPeriod(zigos, self.phase);
            },
        }
    }

    fn tick50(self: *Demo) void {
        const fireLatched = fireDown and !self.firePrev;
        const human = g.Control{ .dir = maskDir(), .fire = fireDown, .fireRising = fireLatched };
        const cpu = g.Control{};
        switch (self.phase) {
            .title => {
                if (fireLatched) {
                    players.init(&match);
                    self.phase = .match;
                }
            },
            .match => {
                if (escapeDown) {
                    self.phase = .title;
                    self.needRepaint = true;
                    escapeDown = false;
                    return;
                }
                players.tick(&match, human, cpu);
                cam.step(players.camTarget(&match), false);
                if (match.phase == .half_time) self.phase = .half_time;
                if (match.phase == .full_time) self.phase = .full_time;
            },
            .half_time => {
                if (fireLatched) {
                    // ContinueOriginalPeriod: swap ends, reset, other team's
                    // kickoff (both attackDown flags flip on the half).
                    match.half = 1;
                    match.clock = 0;
                    match.teams[0].attackDown = !match.teams[0].attackDown;
                    match.teams[1].attackDown = !match.teams[1].attackDown;
                    players.kickoff(&match, 1);
                    self.phase = .match;
                }
            },
            .full_time => {
                if (fireLatched) {
                    self.phase = .title;
                    self.needRepaint = true;
                }
            },
        }
        self.firePrev = fireDown;
    }

    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1; // a game owns every key; arrows arrive via input()
    }

    pub fn key(self: *Demo, cp: u32) void {
        _ = self;
        switch (cp) {
            K_SPACE, K_ENTER, K_Z, K_X => fireDown = true,
            K_UP => keysDown |= 1,
            K_DOWN => keysDown |= 2,
            K_LEFT => keysDown |= 4,
            K_RIGHT => keysDown |= 8,
            K_ESC => escapeDown = true,
            else => {},
        }
    }

    pub fn input(_: *Demo, dir: u8) void {
        switch (dir) {
            0 => keysDown |= 1,
            1 => keysDown |= 2,
            2 => keysDown |= 4,
            3 => keysDown |= 8,
            5 => fireDown = true,
            else => {},
        }
    }

    pub fn inputRelease(_: *Demo, dir: u8) void {
        switch (dir) {
            0 => keysDown &= ~@as(u8, 1),
            1 => keysDown &= ~@as(u8, 2),
            2 => keysDown &= ~@as(u8, 4),
            3 => keysDown &= ~@as(u8, 8),
            5 => fireDown = false,
            else => {},
        }
    }

    pub fn pollCart(self: *Demo) i32 {
        // Neither phase offers a place to "go back" but the viewer needs a
        // way out of the cart; Escape on the title is that way out.
        if (self.phase == .title and escapeDown) {
            escapeDown = false;
            return -1;
        }
        return 0;
    }
};

/// A key going up — the host calls the cart's own wasm export (held keys).
fn keyUp(cp: u32) callconv(.c) void {
    switch (cp) {
        K_SPACE, K_ENTER, K_Z, K_X => fireDown = false,
        K_UP => keysDown &= ~@as(u8, 1),
        K_DOWN => keysDown &= ~@as(u8, 2),
        K_LEFT => keysDown &= ~@as(u8, 4),
        K_RIGHT => keysDown &= ~@as(u8, 8),
        K_ESC => {},
        else => {},
    }
}

fn maskDir() u8 {
    const u = keysDown & 1 != 0;
    const d = keysDown & 2 != 0;
    const l = keysDown & 4 != 0;
    const r = keysDown & 8 != 0;
    if (u and r and !d and !l) return 1;
    if (r and !u and !d) return 2;
    if (d and r) return 3;
    if (d and !u and !l) return 4;
    if (d and l) return 5;
    if (l and !u and !d) return 6;
    if (u and l) return 7;
    if (u) return 0;
    return 8;
}

// --------------------------------------------------------------------------
// Screens.
// --------------------------------------------------------------------------
// The title raster's own 16-colour palette, exactly as tools/kickoff2/
// ko2_assets.py convert_title() derived it (popularity pick + nearest match);
// title.bin indices address THESE positions, entry 0 = the art's background.
pub const TITLE_PAL = [16]zg.Color{
    .{ .r = 153, .g = 170, .b = 153, .a = 255 },
    .{ .r = 119, .g = 153, .b = 102, .a = 255 },
    .{ .r = 170, .g = 187, .b = 170, .a = 255 },
    .{ .r = 187, .g = 204, .b = 187, .a = 255 },
    .{ .r = 153, .g = 187, .b = 136, .a = 255 },
    .{ .r = 170, .g = 204, .b = 153, .a = 255 },
    .{ .r = 0, .g = 0, .b = 0, .a = 255 },
    .{ .r = 204, .g = 221, .b = 204, .a = 255 },
    .{ .r = 221, .g = 238, .b = 221, .a = 255 },
    .{ .r = 17, .g = 119, .b = 34, .a = 255 },
    .{ .r = 255, .g = 187, .b = 34, .a = 255 },
    .{ .r = 136, .g = 153, .b = 136, .a = 255 },
    .{ .r = 102, .g = 119, .b = 119, .a = 255 },
    .{ .r = 102, .g = 136, .b = 85, .a = 255 },
    .{ .r = 68, .g = 85, .b = 85, .a = 255 },
    .{ .r = 221, .g = 170, .b = 136, .a = 255 },
};

fn showTitle(zigos: *ZigOS) void {
    const fb = &zigos.lfbs[0];
    fb.setPalette(pitch.pal256(TITLE_PAL));
    zigos.setBackgroundColor(TITLE_PAL[0]);
    @memcpy(fb.fb[0 .. 320 * 200], pitch.title_bin[0 .. 320 * 200]);
    drawFrontText(zigos);
}

fn drawFrontText(zigos: *ZigOS) void {
    pitch.fillRect(&zigos.lfbs[0], 88, 170, 144, 26, 7);
    zigos.printText(&zigos.lfbs[0], "FIRE = KICK OFF", 100, 176, 0, 0);
    zigos.printTextSmall(&zigos.lfbs[0], "ENGLAND v SPAIN - 1P v CPU", 78, 190, 0, 0);
}

fn renderMatch(zigos: *ZigOS) void {
    pitch.applyMatchPal(zigos);
    pitch.applyKitColours(zigos);
    pitch.drawPitch(zigos, &cam);
    // Players: y-sorted between the two teams, the source's team/shirt pass.
    for (0..g.squad_size) |i| {
        pitch.drawPlayer(zigos, &cam, &match.teams[1].players[i], 1);
        pitch.drawPlayer(zigos, &cam, &match.teams[0].players[i], 0);
    }
    if (match.ballVisible) pitch.drawBall(zigos, &cam, &match.ball);
    hud(zigos);
}

fn hud(zigos: *ZigOS) void {
    pitch.fillRect(&zigos.lfbs[0], 0, 0, 320, 22, 1);
    var buf: [40]u8 = undefined;
    const mins = match.clock / (g.TPS * 60);
    const secs = (match.clock / g.TPS) % 60;
    const text = std.fmt.bufPrint(&buf, "{d}-{d}   ENGLAND v SPAIN   {d:0>2}:{d:0>2}", .{
        match.teams[0].score, match.teams[1].score, mins, secs,
    }) catch buf[0..0];
    zigos.printText(&zigos.lfbs[0], text, 24, 6, 4, 0);
}

fn renderPeriod(zigos: *ZigOS, phase: anytype) void {
    pitch.fillRect(&zigos.lfbs[0], 40, 88, 240, 24, 1);
    if (phase == .half_time) {
        zigos.printText(&zigos.lfbs[0], "HALF TIME - FIRE", 88, 96, 4, 0);
    } else {
        zigos.printText(&zigos.lfbs[0], "FULL TIME - FIRE", 88, 96, 4, 0);
    }
}

// The cart wiring: testapi exports + the module-scope keyUp only exist when
// this scene IS the registered cart (idempotent: cart.zig resolves Cart from
// Demo right above).
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("kickoff2/testapi.zig");
        @export(&keyUp, .{ .name = "keyUp" });
    }
}
