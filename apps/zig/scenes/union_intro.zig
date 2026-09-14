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
const UnionMain = @import("union/main.zig").Demo;
const trsi = @import("union/trsi.zig");
const DepackFx = @import("depackers").depack_fx.Runner(zg, null); // rasters: no tvnoise needed

const hw = @import("hardware");

// The TRSI animation arrives packed; it is depacked with its effect (the RASTERS
// flash, chosen at pack time in build.zig) before the first part starts. At 8
// bytes per physical line it takes about 1.5 s. The runner lives at module scope
// because its HBL handler needs a stable address.
const DEPACK_BYTES_PER_LINE = 8;
var depack: DepackFx = undefined;

/// `len` bytes of the cart's RAM window above its statics and stack, the part
/// the machine reports as free. Null when there is not that much left.
fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}

const Active = union(enum) {
    trsi: trsi.Part,
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
    depacking: bool = false,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.* = .{};
        trsi.turn_raw = &.{};
        const buf = freeRam(trsi.TURN_LEN) orelse return self.skipTrsi(zigos, "no free RAM to depack into");
        if (!depack.start(zigos, trsi.turn_packed, buf, DEPACK_BYTES_PER_LINE))
            return self.skipTrsi(zigos, "packed image unreadable");
        trsi.turn_raw = buf;
        self.depacking = true;
    }

    /// Skip the TRSI part rather than play it from a missing or half-written buffer.
    fn skipTrsi(self: *Demo, zigos: *ZigOS, why: []const u8) void {
        zg.Console.log("union_intro: TRSI animation: {s}, skipping the part", .{why});
        trsi.turn_raw = &.{};
        self.depacking = false;
        self.idx = 1;
        self.startPart(zigos);
    }

    /// While the TRSI animation depacks.
    fn updateDepack(self: *Demo, zigos: *ZigOS) void {
        switch (depack.frame(zigos)) {
            .more => {},
            .done => {
                self.depacking = false;
                self.startPart(zigos);
            },
            .failed => self.skipTrsi(zigos, "depack failed"),
        }
    }

    fn startPart(self: *Demo, zigos: *ZigOS) void {
        // The music starts with the TRSI logo, the first part (Matt). The Codef
        // remake (intro/index.html init()) starts Sharpness Buzztone together
        // with its sequencer, whose first effect is the TRSI logo. The RASTERS
        // depack before it is ZigMachine's stand-in for the remake's image
        // loader, so the request comes once it is done. requestTrack skips a
        // repeat, so later parts and the main screen keep the tune playing.
        UnionMain.requestTrack(UnionMain.TRACKS[0]);
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
        if (self.depacking) return self.updateDepack(zigos);
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
        if (self.depacking) return;
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

    // With pollCart declared, demo_main no longer turns Escape into "back to the
    // menu", so the cart owns keys: Escape still quits, anywhere.
    pub fn key(self: *Demo, cp: u32) void {
        if (self.in_main) self.main.key(cp);
        if (cp == 0xE012) self.wants_quit = true; // host KEY_CODES.Escape
    }

    /// Cartridge swap: -1 the menu, 1 the door's cart (union/doors.zig DOOR_CART).
    pub fn pollCart(self: *Demo) i32 {
        if (self.wants_quit) return -1;
        return if (self.in_main) self.main.pollCart() else 0;
    }

    pub fn cartTag(self: *Demo) []const u8 {
        return self.main.cartTag();
    }
};
