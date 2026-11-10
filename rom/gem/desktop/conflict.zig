// --------------------------------------------------------------------------
// NAME CONFLICT DURING COPY (TOS 1.00): an item being copied or moved has a name that already
// exists where it goes. The box shows the current name and an editable 8.3 field holding the
// copy's name: OK copies under that name (the same name replaces the old item, as on TOS), Skip
// leaves this item out, Quit stops the operation. The field edits as Show Info's (namefield.zig).
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");
const NameField = @import("namefield.zig").NameField;

pub const Conflict = struct {
    active: bool = false,
    move: bool = false, // the heading says MOVE
    current: NameField = .{}, // the name as it is (shown, not edited)
    name: NameField = .{}, // the copy's name (edited)
    enter: bool = false, // Return = OK

    const W: i16 = 248; // 31 cells: fits the 320-wide low-res screen
    const H: i16 = 96; // 12 cells
    pub const Result = enum { none, ok, skip, stop };

    pub fn open(self: *Conflict, name: []const u8, move: bool) void {
        self.* = .{ .active = true, .move = move };
        self.current.set(name);
        self.name.set(name);
    }

    pub fn key(self: *Conflict, cp: u32) void {
        if (cp == 8) self.name.deleteBack() else if (cp == 13) self.enter = true else if (cp >= 32 and cp < 127) self.name.insert(@intCast(cp));
    }
    pub fn moveCaret(self: *Conflict, delta: i8) void {
        self.name.moveCaret(delta);
    }

    pub fn process(self: *Conflict, g: *gui.Gui) Result {
        if (!self.active) return .none;
        if (self.enter) return self.close(.ok);
        const dx = g.screen.centreX(W);
        const dy = g.screen.centreY(H);
        const grid = gui.Grid{ .ox = dx, .oy = dy };
        g.rect(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.WHITE);
        g.frame(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.BLACK);
        g.frame(.{ .x = dx + 3, .y = dy + 3, .w = W - 6, .h = H - 6 }, gui.BLACK);
        const heading = if (self.move) "NAME CONFLICT DURING MOVE" else "NAME CONFLICT DURING COPY";
        g.text(heading, dx + @divTrunc(W - @as(i16, @intCast(heading.len)) * 8, 2), grid.y(1) + 2, gui.BLACK, gui.WHITE);
        var out: [12]u8 = undefined;
        g.text("Current name:", grid.x(2), grid.y(4), gui.BLACK, gui.WHITE);
        g.text(self.current.cells(&out), grid.x(16), grid.y(4), gui.BLACK, gui.WHITE);
        g.text("Copy's name:", grid.x(2) + 8, grid.y(6), gui.BLACK, gui.WHITE);
        g.text(self.name.cells(&out), grid.x(16), grid.y(6), gui.BLACK, gui.WHITE);
        g.fill(grid.x(16) + self.name.caretCol() * 8, grid.y(6) - 1, 2, 9, gui.BLACK);
        return self.buttons(g, grid);
    }

    fn buttons(self: *Conflict, g: *gui.Gui, grid: gui.Grid) Result {
        const bw: i16 = 56;
        const by = grid.y(9);
        const cw = W - grid.w(4);
        const labels = [3][]const u8{ "OK", "Skip", "Quit" };
        const results = [3]Result{ .ok, .skip, .stop };
        for (labels, results, 0..) |l, r, i| {
            const x = gui.hspread(grid.x(2), cw, 3, bw, @intCast(i));
            if (g.buttonThick(.{ .x = x, .y = by, .w = bw, .h = 14 }, l, false, if (i == 0) 3 else 2)) return self.close(r);
        }
        return .none;
    }

    fn close(self: *Conflict, r: Result) Result {
        self.active = false;
        self.enter = false;
        return r;
    }
};
