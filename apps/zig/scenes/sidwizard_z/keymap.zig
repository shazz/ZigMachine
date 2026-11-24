// --------------------------------------------------------------------------
// The machine's keys as the C64 keyboard the editor expects (keys.zig takes matrix codes):
// the map of apps/ports/sidwizard (upstream's PC host) — "CONTROL is Tab, C= is Control, RUN-STOP is
// Esc, back-arrow is `", the piano keys by letter, a US keyboard's punctuation folded to the C64 key
// at the same place (upstream host/keyboard.c: '=' is C64 '+', '[' ':' ']' ';' '\' '='). The machine
// sends what was typed ('#' for Shift+3), so a shifted symbol is folded back to its key + Shift.
// F2/F4/F6/F8 are Shift+F1/F3/F5/F7 on a C64; host Shift+F1/F3/F5 is the same key with C= (upstream).
// The library's `repeatex` is a no-op: the host repeats a held key here.
// --------------------------------------------------------------------------
const kh = @import("keys.zig");

pub const F1: u32 = 0xE001;
pub const F8: u32 = 0xE008;
pub const ESC: u32 = 0xE012;
pub const CONTROL = [2]u32{ 0xE014, 0xE016 };
pub const SHIFT = [2]u32{ 0xE015, 0xE017 };
pub const REPEAT_DELAY: u8 = 18; // frames before a held key repeats
pub const REPEAT_EVERY: u8 = 3;

const Hit = struct { code: u6, shift: bool = false };

const LETTERS = [26]u6{ kh.a_, kh.b_, kh.c_, kh.d_, kh.e_, kh.f_, kh.g_, kh.h_, kh.i_, kh.j_, kh.k_, kh.l_, kh.m_, kh.n_, kh.o_, kh.p_, kh.q_, kh.r_, kh.s_, kh.t_, kh.u_, kh.v_, kh.w_, kh.x_, kh.y_, kh.z_ };
const DIGITS = [10]u6{ kh.k0, kh.k1, kh.k2, kh.k3, kh.k4, kh.k5, kh.k6, kh.k7, kh.k8, kh.k9 };
const SHIFTED = "!@#$%^&*()"; // Shift+1 .. Shift+0 on a US keyboard

/// A typed character's key, null when the C64 has none.
pub fn charKey(c: u32) ?Hit {
    if (c >= 'a' and c <= 'z') return .{ .code = LETTERS[c - 'a'] };
    if (c >= 'A' and c <= 'Z') return .{ .code = LETTERS[c - 'A'], .shift = true };
    if (c >= '0' and c <= '9') return .{ .code = DIGITS[c - '0'] };
    for (SHIFTED, 0..) |s, i| if (c == s) return .{ .code = DIGITS[(i + 1) % 10], .shift = true };
    return switch (c) {
        ' ' => .{ .code = kh.space },
        '+', '=' => .{ .code = kh.plus },
        '-' => .{ .code = kh.minus },
        '.' => .{ .code = kh.dot },
        ',' => .{ .code = kh.comma },
        ';', '[', ':' => .{ .code = kh.colon },
        ']' => .{ .code = kh.semic },
        '\\' => .{ .code = kh.equal_ },
        '/' => .{ .code = kh.slash },
        '`' => .{ .code = kh.backarrow },
        else => null,
    };
}

const Special = struct { cp: u32, key: Hit };
const SPECIALS = [_]Special{
    .{ .cp = 13, .key = .{ .code = kh.ret_ } },
    .{ .cp = 8, .key = .{ .code = kh.del } },
    .{ .cp = 0xE00C, .key = .{ .code = kh.del } }, // Delete
    .{ .cp = 0xE00B, .key = .{ .code = kh.pound } }, // Insert
    .{ .cp = ESC, .key = .{ .code = kh.stop } },
    .{ .cp = 0xE019, .key = .{ .code = kh.ctrl } }, // Tab
    .{ .cp = 0xE01A, .key = .{ .code = kh.home } },
    .{ .cp = 0xE01D, .key = .{ .code = kh.uparr } }, // PageDown
    .{ .cp = 0xE01C, .key = .{ .code = kh.uparr, .shift = true } }, // PageUp
    .{ .cp = 0xE002, .key = .{ .code = kh.f1, .shift = true } }, // F2
    .{ .cp = 0xE004, .key = .{ .code = kh.f3, .shift = true } }, // F4
    .{ .cp = 0xE006, .key = .{ .code = kh.f5, .shift = true } }, // F6
    .{ .cp = F8, .key = .{ .code = kh.f7, .shift = true } },
    .{ .cp = 0xE001, .key = .{ .code = kh.f1 } },
    .{ .cp = 0xE003, .key = .{ .code = kh.f3 } },
    .{ .cp = 0xE005, .key = .{ .code = kh.f5 } },
    .{ .cp = 0xE007, .key = .{ .code = kh.f7 } },
};
const ARROWS = [4]Hit{ .{ .code = kh.crsr_d, .shift = true }, .{ .code = kh.crsr_d }, .{ .code = kh.crsr_r, .shift = true }, .{ .code = kh.crsr_r } };

pub const Out = union(enum) { none, key: kh.Key, exit_dialog };

pub const Pad = struct {
    shift: bool = false,
    cbm: bool = false,
    held: ?kh.Key = null,
    held_cp: u32 = 0,
    age: u16 = 0,

    fn modifier(self: *Pad, cp: u32, down: bool) bool {
        for (SHIFT) |s| if (cp == s) {
            self.shift = down;
            return true;
        };
        for (CONTROL) |c| if (cp == c) {
            self.cbm = down;
            return true;
        };
        return false;
    }

    fn build(self: *const Pad, h: Hit, from_pc_fkey: bool) kh.Key {
        // a PC arrow/F-key with Shift down is the C64 key with C= (upstream's "Shift+Fx = Ctrl+Fx")
        const cbm = self.cbm or (from_pc_fkey and self.shift);
        return .{ .code = h.code, .shift = h.shift or (self.shift and !from_pc_fkey), .cbm = cbm };
    }

    /// A key went down: the key the editor gets (typed keys repeat, see `tick`).
    pub fn press(self: *Pad, cp: u32) Out {
        if (self.modifier(cp, true)) return .none;
        if (cp == F8 and self.shift) return .exit_dialog;
        const hit = lookup(cp) orelse return .none;
        const fkey = cp >= 0xE001 and cp <= 0xE008;
        const k = self.build(hit, fkey);
        self.held = k;
        self.held_cp = cp;
        self.age = 0;
        return .{ .key = k };
    }

    pub fn release(self: *Pad, cp: u32) void {
        if (self.modifier(cp, false)) return;
        if (cp == self.held_cp) self.held = null;
    }

    /// An arrow key (the machine's direction codes 0 up, 1 down, 2 left, 3 right).
    pub fn arrow(self: *Pad, dir: u32) Out {
        if (dir > 3) return .none;
        const k = self.build(ARROWS[dir], false);
        self.held = k;
        self.held_cp = 0x10000 + dir;
        self.age = 0;
        return .{ .key = k };
    }
    pub fn arrowUp(self: *Pad, dir: u32) void {
        if (self.held_cp == 0x10000 + dir) self.held = null;
    }

    /// One frame: a held key that repeats gives its key again, after the delay and then often.
    pub fn tick(self: *Pad) ?kh.Key {
        const k = self.held orelse return null;
        if (!repeats(k.code)) return null;
        self.age +|= 1;
        if (self.age < REPEAT_DELAY or (self.age - REPEAT_DELAY) % REPEAT_EVERY != 0) return null;
        return k;
    }
};

fn lookup(cp: u32) ?Hit {
    for (SPECIALS) |s| if (s.cp == cp) return s.key;
    if (cp >= 32 and cp < 127) return charKey(cp);
    return null;
}

fn repeats(code: u6) bool {
    return switch (code) {
        kh.crsr_d, kh.crsr_r, kh.del, kh.plus, kh.minus, kh.dot, kh.comma, kh.uparr, kh.slash => true,
        else => false,
    };
}

const std = @import("std");

test "letters and digits are their C64 keys; capitals add Shift" {
    try std.testing.expectEqual(@as(u6, kh.z_), charKey('z').?.code);
    try std.testing.expect(charKey('Z').?.shift);
    try std.testing.expectEqual(@as(u6, kh.k3), charKey('#').?.code);
    try std.testing.expect(charKey('#').?.shift);
    try std.testing.expectEqual(@as(?Hit, null), charKey('~'));
}

test "Tab is C64 CONTROL, Escape RUN/STOP, F8 Shift+F7, Control the C= key" {
    var p: Pad = .{};
    try std.testing.expectEqual(@as(u6, kh.ctrl), p.press(0xE019).key.code);
    try std.testing.expectEqual(@as(u6, kh.stop), p.press(ESC).key.code);
    const f8 = p.press(F8).key;
    try std.testing.expect(f8.code == kh.f7 and f8.shift);
    _ = p.press(CONTROL[0]);
    try std.testing.expect(p.press('a').key.cbm);
}

test "Shift+F8 asks to exit; Up is Shift+cursor-down; a held cursor repeats after the delay" {
    var p: Pad = .{};
    _ = p.press(SHIFT[0]);
    try std.testing.expect(p.press(F8) == .exit_dialog);
    p.release(SHIFT[0]);
    const up = p.arrow(0).key;
    try std.testing.expect(up.code == kh.crsr_d and up.shift);
    var n: u32 = 0;
    for (0..40) |_| if (p.tick() != null) {
        n += 1;
    };
    try std.testing.expect(n >= 6 and n <= 8); // from frame 18 every 3
    p.arrowUp(0);
    try std.testing.expect(p.tick() == null);
}

test "a note key does not repeat" {
    var p: Pad = .{};
    _ = p.press('z');
    for (0..60) |_| try std.testing.expect(p.tick() == null);
}
