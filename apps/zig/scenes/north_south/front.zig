// --------------------------------------------------------------------------
// The front page: a small ZigMachine menu that stands in for the strategic
// map (out of scope), which is what chose the field and the two armies and
// called do_battle. It is drawn over the chosen field's own picture, with a
// soldier of each side from the battle's sprite banks, in the machine's 8x8
// system font (the rip has no game font for this).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const gfx = @import("gfx.zig");
const setup = @import("setup.zig");

pub const ROWS = 10;
const START_ROW = 9;
const FIELD_NAMES = [3][]const u8{ "RIVER", "CANYON", "PLAIN" };
const PLAYER_NAMES = [4][]const u8{ "YOU: UNION  vs CPU", "YOU: CONFED vs CPU", "TWO PLAYERS", "CPU vs CPU (DEMO)" };
/// The most units a record may hold here (the field shows at most 6 / 3 / 3;
/// the rest are reserves). Cannons stop at 3: a record of 4 would spill into
/// the rider slots, as the original's spawn does not cap them.
const MAX = [3]u8{ 30, 15, 3 };
const TYPE_NAMES = [3][]const u8{ "INFANTRY", "CAVALRY ", "CANNONS " };

// Colours of the field palettes (all three share them).
const BLACK: u8 = 0;
const WHITE: u8 = 12;
const RED: u8 = 13;
const YELLOW: u8 = 14;

pub const Front = struct {
    row: u8,
    field: u8,
    players: u8, // index into PLAYER_NAMES
    level: u8, // the CPU's AI level, 0..2
    army: [2][3]u8, // [Union, Confederates][infantry, cavalry, cannons]

    pub fn reset(self: *Front) void {
        self.row = START_ROW;
        self.field = 0;
        self.players = 0;
        self.level = 1;
        self.army = .{ .{ 6, 3, 1 }, .{ 6, 3, 1 } };
    }

    pub fn move(self: *Front, dir: u8) void {
        switch (dir) {
            0 => self.row = if (self.row == 0) ROWS - 1 else self.row - 1,
            1 => self.row = if (self.row == ROWS - 1) 0 else self.row + 1,
            2 => self.change(-1),
            3 => self.change(1),
            else => {},
        }
    }

    fn change(self: *Front, d: i32) void {
        switch (self.row) {
            0 => self.field = wrap(self.field, d, 3),
            1 => self.players = wrap(self.players, d, 4),
            2 => self.level = wrap(self.level, d, 3),
            3...8 => {
                const side = (self.row - 3) / 3;
                const t = (self.row - 3) % 3;
                const v: i32 = @as(i32, self.army[side][t]) + d;
                self.army[side][t] = @intCast(@max(0, @min(v, MAX[t])));
            },
            else => {},
        }
    }

    pub fn onStart(self: *const Front) bool {
        return self.row == START_ROW;
    }

    pub fn options(self: *const Front, seed: u32) setup.Options {
        const mode: setup.Mode = switch (self.players) {
            0 => .union_human,
            1 => .confed_human,
            2 => .two_players,
            else => .demo,
        };
        var army = self.army;
        for (&army) |*a| if (a[0] == 0 and a[1] == 0 and a[2] == 0) {
            a[0] = 1; // an empty army would lose before the first frame
        };
        return .{
            .field = self.field,
            .union_army = army[0],
            .confed_army = army[1],
            .mode = mode,
            .level_a = self.level,
            .level_b = self.level,
            .seed = seed,
        };
    }

    pub fn draw(self: *const Front, zigos: *zg.ZigOS, fb: *zg.LogicalFB) void {
        const scr = &gfx.screens[0];
        gfx.planarToIndices(A.fieldPicture(self.field), scr);
        for (36..198) |y| @memset(scr[y * gfx.W + 12 ..][0..296], BLACK);
        _ = gfx.blit(scr, .union_, 0, 256, 106); // a soldier of each side
        _ = gfx.blit(scr, .confed, 0, 256, 133);
        present(scr, fb);
        for (0..16) |i| fb.palette[i] = stColor(A.fieldPalette(self.field, i));
        zigos.printText(fb, "NORTH & SOUTH  -  THE BATTLE", 48, 40, YELLOW, BLACK);
        zigos.printText(fb, "Infogrames 1989", 100, 50, WHITE, BLACK);
        var buf: [40]u8 = undefined;
        self.line(zigos, fb, 0, cat(&buf, "FIELD     ", FIELD_NAMES[self.field], ""));
        self.line(zigos, fb, 1, cat(&buf, "PLAYERS   ", PLAYER_NAMES[self.players], ""));
        self.line(zigos, fb, 2, cat(&buf, "CPU LEVEL ", &[1]u8{'0' + self.level}, " (0 slow, 2 fast)"));
        for (0..2) |side| for (0..3) |t| {
            var num: [2]u8 = undefined;
            const pre = if (side == 0) "UNION  " else "CONFED ";
            var b2: [40]u8 = undefined;
            const head = cat(&b2, pre, TYPE_NAMES[t], " ");
            self.line(zigos, fb, @intCast(3 + side * 3 + t), cat(&buf, head, two(&num, self.army[side][t]), ""));
        };
        self.line(zigos, fb, START_ROW, "START THE BATTLE");
        zigos.printText(fb, "        MOVE   FIRE  UNIT RETREAT", 20, 156, WHITE, BLACK);
        zigos.printText(fb, "UNION   WASD   F     Z    ESC", 20, 165, RED, BLACK);
        zigos.printText(fb, "CONFED  ARROWS SPACE /    BACKSPACE", 20, 174, RED, BLACK);
        zigos.printText(fb, "F10 LEAVES", 124, 186, WHITE, BLACK);
    }

    fn line(self: *const Front, zigos: *zg.ZigOS, fb: *zg.LogicalFB, row: u8, text: []const u8) void {
        const y: i16 = 62 + @as(i16, row) * 9;
        const sel = self.row == row;
        zigos.printText(fb, if (sel) ">" else " ", 24, y, YELLOW, BLACK);
        zigos.printText(fb, text, 36, y, if (sel) YELLOW else WHITE, BLACK);
    }
};

fn wrap(v: u8, d: i32, n: u8) u8 {
    return @intCast(@mod(@as(i32, v) + d, n));
}

fn two(buf: *[2]u8, v: u8) []const u8 {
    buf[0] = if (v >= 10) '0' + v / 10 else ' ';
    buf[1] = '0' + v % 10;
    return buf;
}

fn cat(buf: *[40]u8, a: []const u8, b: []const u8, c: []const u8) []const u8 {
    var n: usize = 0;
    for ([_][]const u8{ a, b, c }) |s| for (s) |ch| {
        if (n == buf.len) break;
        buf[n] = ch;
        n += 1;
    };
    return buf[0..n];
}

/// 320x200 colour indices into the plane.
pub fn present(scr: *const [gfx.PIXELS]u8, fb: *zg.LogicalFB) void {
    for (0..gfx.H) |y| @memcpy(fb.fb[y * fb.stride ..][0..gfx.W], scr[y * gfx.W ..][0..gfx.W]);
}

/// An ST colour register ($0RGB, three bits a gun) as the machine's RGBA.
pub fn stColor(word: u16) u32 {
    const r: u32 = gun(word >> 8);
    const g: u32 = gun(word >> 4);
    const b: u32 = gun(word);
    return (0xFF << 24) | (b << 16) | (g << 8) | r;
}

fn gun(nibble: u16) u32 {
    return @as(u32, nibble & 7) * 255 / 7;
}
