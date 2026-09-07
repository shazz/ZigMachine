// --------------------------------------------------------------------------
// Union intro — a ZigMachine port of shazz's Codef "UnionDemoCracktro" intro.
// This is the PART SEQUENCER (mirrors the Codef effectList): it runs the intro
// parts in order, then flows straight into the main door screen — the full
// Union experience end to end. Each part lives in apps/scenes/union/.
//
//   trsi       — TRSI logo: tile fly-in -> turning animation -> fade
//   wab        — WAB logo: rotating tile fly-in -> fade   (art -> ZigMachine later)
//   placement  — efmain_intro: 17 back_layer strips slide/fade in -> main screen
//   -> main    — hands off to the doors launcher (walk to a door + Fire to enter)
//
// ESC during the intro, or on the main screen, bubbles `wants_quit` to the
// menu host (same contract menu.zig uses for the standalone UNION MAIN entry).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Doors = @import("union/doors.zig").Doors;

const Active = union(enum) {
    trsi: @import("union/trsi.zig").Part,
    wab: @import("union/wab.zig").Part,
    placement: @import("union/placement.zig").Placement,
};
const Tag = std.meta.Tag(Active);
const SEQ = [_]Tag{ .trsi, .wab, .placement };

pub const Demo = struct {
    idx: usize = 0,
    active: Active = .{ .trsi = .{} },
    in_main: bool = false,
    main: Doors = .{},
    wants_quit: bool = false,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.* = .{};
        self.startPart(zigos);
    }

    fn startPart(self: *Demo, zigos: *ZigOS) void {
        switch (SEQ[self.idx]) {
            inline else => |t| {
                self.active = @unionInit(Active, @tagName(t), .{});
                @field(self.active, @tagName(t)).init(zigos);
            },
        }
    }

    fn enterMain(self: *Demo, zigos: *ZigOS) void {
        zigos.resetForScene();
        self.in_main = true;
        self.main.init(zigos);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        if (self.in_main) {
            self.main.update(zigos, dt);
            if (self.main.wants_quit) self.wants_quit = true;
            return;
        }
        const done = switch (self.active) {
            inline else => |*p| p.update(zigos, dt),
        };
        if (!done) return;
        self.idx += 1;
        if (self.idx < SEQ.len) self.startPart(zigos) else self.enterMain(zigos);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        if (self.in_main) return self.main.render(zigos, dt);
        switch (self.active) {
            inline else => |*p| p.render(zigos, dt),
        }
    }

    // Host input ids: 0 up, 1 down, 2 left, 3 right, 5 fire, 6 back.
    pub fn input(self: *Demo, dir: u8) void {
        if (self.in_main) {
            self.main.input(dir);
            if (self.main.wants_quit) self.wants_quit = true;
        } else if (dir == 6) {
            self.wants_quit = true; // ESC skips the intro straight to the menu
        }
    }

    pub fn setShadeMode(self: *Demo, mode: u32) void {
        if (self.in_main) self.main.setShadeMode(mode);
    }

    pub fn pollSong(self: *Demo) u32 {
        return if (self.in_main) self.main.pollSong() else 0;
    }
};
