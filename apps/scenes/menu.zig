// --------------------------------------------------------------------------
// Effects menu — a runtime scene selector. Lists the built-in demos and, on
// launch, resets the machine and hands the plane to the chosen child scene;
// ESC returns here. Scene selection used to be compile-time (apps/floppy.zig);
// this makes it runtime, mirroring how gem_desktop hosts st_replay.
//
// Children are a tagged union (heap-free; the union costs the largest child's
// state, exactly what `var demo` already paid for one scene). Dispatch is an
// `inline else` switch so optional methods are still found via @hasDecl.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;

// Launchable child scenes (Tier A — these already build on the named module).
const Child = union(enum) {
    none,
    union_intro: @import("union_intro.zig").Demo,
    music: @import("music_debug.zig").Demo,
    blitter: @import("blitter_demo.zig").Demo,
    scroll: @import("scroll_demo.zig").Demo,
    obj: @import("obj_demo.zig").Demo,
    gem: @import("gem_desktop.zig").Demo,
};

const Tag = std.meta.Tag(Child);
const Entry = struct { name: []const u8, tag: Tag };
const ENTRIES = [_]Entry{
    .{ .name = "UNION INTRO", .tag = .union_intro },
    .{ .name = "MUSIC DEBUG", .tag = .music },
    .{ .name = "BLITTER DEMO", .tag = .blitter },
    .{ .name = "SCROLL DEMO", .tag = .scroll },
    .{ .name = "OBJ DEMO", .tag = .obj },
    .{ .name = "GEM DESKTOP", .tag = .gem },
};

// Palette indices for the menu screen.
const BG: u8 = 0;
const INK: u8 = 1;
const HILITE: u8 = 2;

const State = enum { menu, running };

pub const Demo = struct {
    os: *ZigOS = undefined,
    state: State = .menu,
    sel: usize = 0,
    child: Child = .none,

    pub fn init(self: *Demo, os: *ZigOS) void {
        self.* = .{ .os = os };
        self.initMenu();
    }

    fn initMenu(self: *Demo) void {
        const fb: *LogicalFB = &self.os.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(BG, Color{ .r = 0, .g = 0, .b = 40, .a = 255 });
        fb.setPaletteEntry(INK, Color{ .r = 220, .g = 220, .b = 255, .a = 255 });
        fb.setPaletteEntry(HILITE, Color{ .r = 220, .g = 60, .b = 60, .a = 255 });
    }

    pub fn update(self: *Demo, os: *ZigOS, dt: f32) void {
        switch (self.child) {
            .none => {},
            inline else => |*c| if (self.state == .running) c.update(os, dt),
        }
    }

    pub fn render(self: *Demo, os: *ZigOS, dt: f32) void {
        if (self.state == .menu) {
            self.drawMenu();
            return;
        }
        switch (self.child) {
            .none => {},
            inline else => |*c| c.render(os, dt),
        }
    }

    fn drawMenu(self: *Demo) void {
        const fb: *LogicalFB = &self.os.lfbs[0];
        fb.clearFrameBuffer(BG);
        self.os.printText(fb, "ZIGMACHINE  --  SELECT A DEMO", 8, 16, INK, BG);
        for (ENTRIES, 0..) |e, i| {
            const on = (i == self.sel);
            const y: u16 = @intCast(48 + i * 14);
            self.os.printText(fb, if (on) ">" else " ", 24, y, if (on) HILITE else INK, BG);
            self.os.printText(fb, e.name, 48, y, if (on) HILITE else INK, BG);
        }
        self.os.printText(fb, "UP/DOWN  ENTER:RUN  ESC:BACK", 8, 184, INK, BG);
    }

    // Host input ids from demo_main: 0 up, 1 down, 2 left, 3 right, 5 fire, 6 back.
    pub fn input(self: *Demo, dir: u8) void {
        if (self.state == .running) {
            if (dir == 6) {
                self.back();
            } else switch (self.child) {
                .none => {},
                inline else => |*c| if (@hasDecl(@TypeOf(c.*), "input")) c.input(dir),
            }
            return;
        }
        switch (dir) {
            0 => self.sel = if (self.sel == 0) ENTRIES.len - 1 else self.sel - 1,
            1 => self.sel = if (self.sel + 1 >= ENTRIES.len) 0 else self.sel + 1,
            5 => self.launch(),
            else => {},
        }
    }

    // Keys 1-7 while a child runs go to that child's shading/mode switch.
    pub fn setShadeMode(self: *Demo, mode: u32) void {
        if (self.state != .running) return;
        switch (self.child) {
            .none => {},
            inline else => |*c| if (@hasDecl(@TypeOf(c.*), "setShadeMode")) c.setShadeMode(mode),
        }
    }

    // Pointer goes to a running child that wants it (e.g. the GEM desktop).
    pub fn pointer(self: *Demo, x: i32, y: i32, buttons: u32) void {
        if (self.state != .running) return;
        switch (self.child) {
            .none => {},
            inline else => |*c| if (@hasDecl(@TypeOf(c.*), "pointer")) c.pointer(x, y, buttons),
        }
    }

    fn launch(self: *Demo) void {
        self.os.resetForScene();
        switch (ENTRIES[self.sel].tag) {
            .none => {},
            inline else => |t| {
                self.child = @unionInit(Child, @tagName(t), .{});
                @field(self.child, @tagName(t)).init(self.os);
            },
        }
        self.state = .running;
    }

    fn back(self: *Demo) void {
        self.os.resetForScene();
        self.child = .none;
        self.initMenu();
        self.state = .menu;
    }
};
