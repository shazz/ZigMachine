// --------------------------------------------------------------------------
// NOTEPAD's Find dialog. GEM 5's API has no editable text field and no form_do
// (an API finding, docs/NOTEPAD.md): this box is built from the ROM's panel,
// text and buttons, with the field and its caret kept here. Return fires Find
// (the default button, through guiKey), Escape cancels. Drawn every frame while
// it is up, as the ROM's own dialogs are; the window is repainted after it.
// --------------------------------------------------------------------------
const rom = @import("rom_sdk");
const aes = rom.aes;
const Rect = rom.Rect;

pub const MAX = 26;
const W: i16 = 36 * 8;
const H: i16 = 7 * 8;

pub const Result = enum { none, find, cancel };

pub const Find = struct {
    active: bool = false,
    buf: [MAX]u8 = undefined,
    len: u8 = 0,
    escape: bool = false,

    pub fn open(self: *Find) void {
        self.active = true; // the last search stays in the field, as a TOS editor kept it
        self.escape = false;
    }

    pub fn text(self: *const Find) []const u8 {
        return self.buf[0..self.len];
    }

    /// A key while the box is up: 8 rubs out, Escape cancels, printable characters type.
    pub fn key(self: *Find, cp: u32) void {
        if (cp == 8) self.len -|= 1 else if (cp == 0xE012) self.escape = true else if (cp >= 32 and cp < 127 and self.len < MAX) {
            self.buf[self.len] = @intCast(cp);
            self.len += 1;
        }
    }

    pub fn process(self: *Find, g: rom.Gui, sw: i16, sh: i16) Result {
        if (!self.active) return .none;
        const b = Rect{ .x = @divTrunc(sw - W, 2), .y = @divTrunc(sh - H, 2), .w = W, .h = H };
        g.box(b, 2);
        g.text("Find:", b.x + 16, b.y + 12, rom.BLACK, rom.WHITE);
        var rule: [MAX]u8 = [_]u8{'_'} ** MAX;
        @memcpy(rule[0..self.len], self.buf[0..self.len]);
        const fx = b.x + 64;
        g.text(rule[0..], fx, b.y + 12, rom.BLACK, rom.WHITE);
        g.fill(fx + @as(i16, self.len) * 8, b.y + 11, 2, 9, rom.BLACK);
        const by = b.y + H - 24;
        var r: Result = .none;
        if (g.button(.{ .x = b.x + W - 176, .y = by, .w = 72, .h = 14 }, "Find", false, 3)) r = .find;
        if (g.button(.{ .x = b.x + W - 88, .y = by, .w = 72, .h = 14 }, "Cancel", false, 2)) r = .cancel;
        if (self.escape) r = .cancel;
        if (r == .find and self.len == 0) r = .none; // nothing to look for: the box stays
        if (r != .none) self.active = false;
        self.escape = false;
        return r;
    }
};
