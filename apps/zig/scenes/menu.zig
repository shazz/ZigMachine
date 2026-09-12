// --------------------------------------------------------------------------
// Effects menu — a pure launcher. Lists every scene (catalog.zig) alphabetically
// across two columns and as many PAGES as it takes, and on Fire returns the
// selected cartridge tag; the host boots that scene's floppy (demo-<tag>.zmd) by
// swapping the demo module. It links NO scenes — each scene is its own
// cartridge, so the launcher stays tiny.
//
// Paged because the shelf outgrew the screen: rows-per-column used to be derived
// from the entry count, so every scene added squeezed the list until it ran off
// the bottom. Now the page geometry is fixed and the PAGE COUNT grows instead.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;
const catalog = @import("catalog.zig");

const BG: u8 = 0;
const INK: u8 = 1;
const HILITE: u8 = 2;

// Layout. ROWS is fixed by the space between the title and the footer (a row is
// 11px from y=22, so row 14 lands at y=176 and clears the footer at 190) — NOT
// derived from the entry count, which is what used to make the list overflow the
// screen as scenes were added.
const COLS: usize = 2;
const ROWS: usize = 15;
const PER_PAGE: usize = COLS * ROWS;
const PAGES: usize = (ENTRIES.len + PER_PAGE - 1) / PER_PAGE;

// catalog.zig is append-ordered — agents add a line at the end — so sort here
// rather than asking every contributor to insert in the right place.
const ENTRIES = blk: {
    @setEvalBranchQuota(100_000);
    var a = catalog.ENTRIES;
    for (1..a.len) |i| { // insertion sort: comptime, tiny, and stable
        const e = a[i];
        var j = i;
        while (j > 0 and std.mem.lessThan(u8, e.name, a[j - 1].name)) : (j -= 1) a[j] = a[j - 1];
        a[j] = e;
    }
    break :blk a;
};

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

        // Only this page's slice, so the list can never run past the footer.
        const page = self.sel / PER_PAGE;
        const first = page * PER_PAGE;
        const last = @min(first + PER_PAGE, ENTRIES.len);
        for (ENTRIES[first..last], first..) |e, i| {
            const on = (i == self.sel);
            const within = i - first;
            const x: i16 = @intCast(16 + (within / ROWS) * 152);
            const y: i16 = @intCast(22 + (within % ROWS) * 11);
            const fg: u8 = if (on) HILITE else INK;
            os.printText(fb, if (on) ">" else " ", x, y, fg, BG);
            os.printText(fb, e.name, x + 12, y, fg, BG);
        }

        os.printText(fb, "ARROWS  FIRE:BOOT  ESC:BACK", 8, 190, INK, BG);
        if (PAGES > 1) { // L/R past a column edge turns the page
            var buf: [16]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "PAGE {d}/{d}", .{ page + 1, PAGES }) catch "";
            os.printText(fb, s, 240, 190, HILITE, BG);
        }
    }

    // Grid move by (dcol, drow). Up/down wrap within the column; left/right past
    // a column edge turns the page, so every entry is reachable with the arrows
    // alone. The final page is ragged, so the result is clamped to what exists.
    fn move(self: *Demo, dcol: i32, drow: i32) void {
        const within = self.sel % PER_PAGE;
        var page: i32 = @intCast(self.sel / PER_PAGE);
        var col: i32 = @intCast(within / ROWS);
        const row: i32 = @intCast(within % ROWS);

        const nr = @mod(row + drow, @as(i32, ROWS));
        col += dcol;
        if (col < 0) {
            page = @mod(page - 1, @as(i32, PAGES));
            col = @as(i32, COLS) - 1;
        } else if (col >= @as(i32, COLS)) {
            page = @mod(page + 1, @as(i32, PAGES));
            col = 0;
        }

        var idx: usize = @intCast(page * @as(i32, PER_PAGE) + col * @as(i32, ROWS) + nr);
        if (idx >= ENTRIES.len) idx = ENTRIES.len - 1; // ragged last page
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
