// --------------------------------------------------------------------------
// Union intro — a ZigMachine port of shazz's Codef "UnionDemoCracktro" intro.
// This is the PART SEQUENCER (mirrors the Codef effectList): it runs the intro
// parts in order, advancing to the next when a part reports it is finished.
// Each part lives in apps/scenes/union/ and shares plane 0.
//
//   trsi       — TRSI logo: tile fly-in -> turning animation -> fade
//   wab        — WAB logo: rotating tile fly-in -> fade   (art -> ZigMachine later)
//   placement  — efmain_intro: 17 back_layer strips slide/fade in -> main screen
//   (next: the main running-character screen)
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;

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
    finished: bool = false,

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

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        if (self.finished) return;
        const done = switch (self.active) {
            inline else => |*p| p.update(zigos, dt),
        };
        if (done) {
            self.idx += 1;
            if (self.idx < SEQ.len) self.startPart(zigos) else self.finished = true;
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        switch (self.active) {
            inline else => |*p| p.render(zigos, dt),
        }
    }
};
