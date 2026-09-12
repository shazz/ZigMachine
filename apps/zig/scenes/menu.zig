// --------------------------------------------------------------------------
// Effects menu — a pure launcher. Lists every scene (catalog.zig) in two columns
// and, on Fire, returns the selected cartridge tag; the host boots that scene's
// floppy (demo-<tag>.zmd) by swapping the demo module. It links NO scenes — each
// scene is its own cartridge, so the launcher stays tiny.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;
const catalog = @import("catalog.zig");
const ENTRIES = catalog.ENTRIES;

const BG: u8 = 0;
const INK: u8 = 1;
const HILITE: u8 = 2;

const COLS: usize = 2;
const ROWS: usize = (ENTRIES.len + COLS - 1) / COLS; // rows per column

pub const Demo = struct {
    os: *ZigOS = undefined,
    sel: usize = 0,
    request: bool = false, // Fire pressed — host should boot self.tag
    tag: []const u8 = "",

    pub fn init(self: *Demo, os: *ZigOS) void {
        self.* = .{ .os = os };
        const fb: *LogicalFB = &os.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(BG, Color{ .r = 0, .g = 0, .b = 40, .a = 255 });
        fb.setPaletteEntry(INK, Color{ .r = 220, .g = 220, .b = 255, .a = 255 });
        fb.setPaletteEntry(HILITE, Color{ .r = 220, .g = 60, .b = 60, .a = 255 });
    }

    pub fn update(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = self;
        _ = os;
        _ = dt;
    }

    pub fn render(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = dt;
        const fb: *LogicalFB = &os.lfbs[0];
        fb.clearFrameBuffer(BG);
        os.printText(fb, "ZIGMACHINE -- INSERT A DISK", 8, 6, INK, BG);
        for (ENTRIES, 0..) |e, i| {
            const on = (i == self.sel);
            const col = i / ROWS;
            const row = i % ROWS;
            const x: i16 = @intCast(16 + col * 152);
            const y: i16 = @intCast(22 + row * 11);
            const fg: u8 = if (on) HILITE else INK;
            os.printText(fb, if (on) ">" else " ", x, y, fg, BG);
            os.printText(fb, e.name, x + 12, y, fg, BG);
        }
        os.printText(fb, "ARROWS  FIRE:BOOT  ESC:BACK", 8, 190, INK, BG);
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

    // Host input ids: 0 up, 1 down, 2 left, 3 right, 5 fire, 6 back.
    pub fn input(self: *Demo, dir: u8) void {
        switch (dir) {
            0 => self.move(0, -1),
            1 => self.move(0, 1),
            2 => self.move(-1, 0),
            3 => self.move(1, 0),
            5 => {
                self.tag = ENTRIES[self.sel].tag;
                self.request = true;
            },
            else => {},
        }
    }

    // Cartridge-swap bridge (demo_main forwards these to the host).
    pub fn pollCart(self: *Demo) i32 {
        if (self.request) {
            self.request = false;
            return 1;
        }
        return 0;
    }
    pub fn cartTag(self: *Demo) []const u8 {
        return self.tag;
    }
};
