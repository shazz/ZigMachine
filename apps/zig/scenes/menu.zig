// --------------------------------------------------------------------------
// Effects menu — a runtime scene selector. Lists every Zig scene (see
// catalog.zig) in two columns; on launch it resets the machine and hands plane 0
// to the chosen child; ESC returns here. A `var demo` holds one menu whose child
// union costs the largest scene's state (heap-free). Dispatch is an `inline else`
// switch so optional child methods are found via @hasDecl.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;
const catalog = @import("catalog.zig");
const Child = catalog.Child;
const ENTRIES = catalog.ENTRIES;

// Palette indices for the menu screen.
const BG: u8 = 0;
const INK: u8 = 1;
const HILITE: u8 = 2;

const COLS: usize = 2;
const ROWS: usize = (ENTRIES.len + COLS - 1) / COLS; // rows per column

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
        self.os.printText(fb, "ZIGMACHINE -- SELECT A DEMO", 8, 6, INK, BG);
        for (ENTRIES, 0..) |e, i| {
            const on = (i == self.sel);
            const col = i / ROWS;
            const row = i % ROWS;
            const x: u16 = @intCast(16 + col * 152);
            const y: u16 = @intCast(22 + row * 11);
            const fg: u8 = if (on) HILITE else INK;
            self.os.printText(fb, if (on) ">" else " ", x, y, fg, BG);
            self.os.printText(fb, e.name, x + 12, y, fg, BG);
        }
        self.os.printText(fb, "ARROWS  FIRE:RUN  ESC:BACK", 8, 190, INK, BG);
    }

    // Grid move by (dcol, drow) with wrap; clamp into a ragged final column.
    fn move(self: *Demo, dcol: i32, drow: i32) void {
        const col: i32 = @intCast(self.sel / ROWS);
        const row: i32 = @intCast(self.sel % ROWS);
        const nc: i32 = @mod(col + dcol, @as(i32, COLS));
        const nr: i32 = @mod(row + drow, @as(i32, ROWS));
        var idx: usize = @intCast(nc * @as(i32, ROWS) + nr);
        if (idx >= ENTRIES.len) idx = ENTRIES.len - 1;
        self.sel = idx;
    }

    // Host input ids from demo_main: 0 up, 1 down, 2 left, 3 right, 5 fire, 6 back.
    pub fn input(self: *Demo, dir: u8) void {
        if (self.state == .running) {
            switch (self.child) {
                .none => {},
                inline else => |*c| {
                    const C = @TypeOf(c.*);
                    if (@hasField(C, "wants_quit")) {
                        if (@hasDecl(C, "input")) c.input(dir);
                        if (c.wants_quit) self.back();
                    } else if (dir == 6) {
                        self.back();
                    } else if (@hasDecl(C, "input")) c.input(dir);
                },
            }
            return;
        }
        switch (dir) {
            0 => self.move(0, -1),
            1 => self.move(0, 1),
            2 => self.move(-1, 0),
            3 => self.move(1, 0),
            5 => self.launch(),
            else => {},
        }
    }

    // Keys 1-7 while a child runs go to that child's shading/mode switch.
    // Returns whether the running child actually consumed it, so the host can
    // fall back to its audio shortcuts for scenes without a mode switch (e.g.
    // music_debug, whose 1/2/3 play MOD/YM/sample).
    pub fn setShadeMode(self: *Demo, mode: u32) bool {
        if (self.state != .running) return false;
        switch (self.child) {
            .none => return false,
            inline else => |*c| {
                if (@hasDecl(@TypeOf(c.*), "setShadeMode")) {
                    c.setShadeMode(mode);
                    return true;
                }
                return false;
            },
        }
    }

    // Song request from a running child (e.g. union main), forwarded to the host.
    pub fn pollSong(self: *Demo) u32 {
        if (self.state != .running) return 0;
        switch (self.child) {
            .none => return 0,
            inline else => |*c| return if (@hasDecl(@TypeOf(c.*), "pollSong")) c.pollSong() else 0,
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
