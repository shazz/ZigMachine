// --------------------------------------------------------------------------
// A PROGRAM's object tree, as it lies in the program's memory (G20): the AES's
// OBJECT (24 bytes) and TEDINFO (28 bytes), exactly the public binding every GEM
// RSC and C binding shares, so a C or Rust cart lays them out as TOS programs
// did. ob_spec is the box word (G_BOX, G_IBOX, G_BOXCHAR), or the address of a
// NUL-terminated string (G_STRING, G_BUTTON, G_TITLE) or of a TEDINFO (G_TEXT,
// G_BOXTEXT, G_FTEXT, G_FBOXTEXT), in the program's window.
//
// load() turns it into the engine's objects (engine/obj.zig) to draw and find;
// every address is checked against the window (`Mem`) first, so a bad one is an
// empty string, never a read outside the program's memory. An editable text is
// shown as the AES shows it: its template with the text's characters in place of
// the template's underscores. Pure: native tests (rom/gem/gui_obj_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");
const obj = @import("../engine/obj.zig");
const wire_icon = @import("wire_icon.zig");

pub const Obj = extern struct { next: i16, head: i16, tail: i16, ty: u16, flags: u16, state: u16, spec: u32, x: i16, y: i16, w: i16, h: i16 };
pub const Ted = extern struct { text: u32, tmplt: u32, valid: u32, font: i16, fontid: i16, just: i16, color: i16, fontsize: i16, thickness: i16, txtlen: i16, tmplen: i16 };
comptime {
    std.debug.assert(@sizeOf(Obj) == 24 and @sizeOf(Ted) == 28);
}

pub const MAX_OBJ = 64;
pub const MAX_TED = 16;
pub const SHOWN = 48; // an editable text's shown width (template with the text merged in)
const STR_MAX = 80;

/// The program's window: address `base` is bytes[0].
pub const Mem = struct {
    base: u32,
    bytes: []u8,

    pub fn slice(self: Mem, addr: u32, len: usize) ?[]u8 {
        if (addr < self.base) return null;
        const off: usize = addr - self.base;
        if (off > self.bytes.len or len > self.bytes.len - off) return null;
        return self.bytes[off..][0..len];
    }
    /// The NUL-terminated string at `addr` (at most STR_MAX), empty when outside the window.
    pub fn str(self: Mem, addr: u32) []const u8 {
        const s = self.slice(addr, 0) orelse return "";
        const off = @intFromPtr(s.ptr) - @intFromPtr(self.bytes.ptr);
        const rest = self.bytes[off..][0..@min(STR_MAX, self.bytes.len - off)];
        return rest[0 .. std.mem.indexOfScalar(u8, rest, 0) orelse rest.len];
    }
    pub fn objs(self: Mem, addr: u32, n: u32) ?[]align(1) Obj {
        if (n == 0 or n > MAX_OBJ) return null;
        const b = self.slice(addr, @as(usize, n) * @sizeOf(Obj)) orelse return null;
        return std.mem.bytesAsSlice(Obj, b);
    }
    pub fn ted(self: Mem, addr: u32) ?*align(1) Ted {
        const b = self.slice(addr, @sizeOf(Ted)) orelse return null;
        return @ptrCast(b.ptr);
    }
};

/// Where a loaded tree lives (the ROM's: the trees are drawn in the call that loaded them).
pub const Store = struct {
    objs: [MAX_OBJ]obj.Object = undefined,
    teds: [MAX_TED]obj.Ted = undefined,
    shown: [MAX_TED][SHOWN]u8 = undefined,
    nted: usize = 0,
    icons: [wire_icon.MAX_ICON]obj.IconBlk = undefined,
    nicon: usize = 0,
    sys: []const wire_icon.Art = &.{}, // the ROM's own icons a G_ICON may name (wire_icon.zig)
};

/// The engine's copy of the `n` objects at `addr`, null for a tree outside the window.
pub fn load(m: Mem, addr: u32, n: u32, s: *Store) ?[]obj.Object {
    const w = m.objs(addr, n) orelse return null;
    s.nted = 0;
    s.nicon = 0;
    for (w, 0..) |o, i| s.objs[i] = .{ .next = o.next, .head = o.head, .tail = o.tail, .ty = @truncate(o.ty), .flags = o.flags, .state = o.state, .spec = spec(m, o, s), .x = o.x, .y = o.y, .w = o.w, .h = o.h };
    return s.objs[0..n];
}

fn spec(m: Mem, o: Obj, s: *Store) obj.Spec {
    return switch (@as(u8, @truncate(o.ty))) {
        obj.G_BOX, obj.G_IBOX, obj.G_BOXCHAR => .{ .box = o.spec },
        obj.G_STRING, obj.G_BUTTON, obj.G_TITLE => .{ .str = m.str(o.spec) },
        obj.G_TEXT, obj.G_BOXTEXT, obj.G_FTEXT, obj.G_FBOXTEXT => tedSpec(m, o, s),
        obj.G_ICON => iconSpec(m, o, s),
        else => .none,
    };
}

fn iconSpec(m: Mem, o: Obj, s: *Store) obj.Spec {
    if (s.nicon == wire_icon.MAX_ICON) return .none;
    if (!wire_icon.load(m, o.spec, s.sys, &s.icons[s.nicon])) return .none;
    s.nicon += 1;
    return .{ .icon = &s.icons[s.nicon - 1] };
}

fn tedSpec(m: Mem, o: Obj, s: *Store) obj.Spec {
    const t = m.ted(o.spec) orelse return .none;
    if (s.nted == MAX_TED) return .none;
    const k = s.nted;
    s.nted += 1;
    const edit = o.ty == obj.G_FTEXT or o.ty == obj.G_FBOXTEXT;
    const text = if (edit) merge(m.str(t.tmplt), m.str(t.text), &s.shown[k]) else m.str(t.text);
    s.teds[k] = .{ .text = text, .font = @truncate(@as(u16, @bitCast(t.font))), .just = @truncate(@as(u16, @bitCast(t.just))), .color = @bitCast(t.color), .thickness = @truncate(t.thickness) };
    return .{ .ted = &s.teds[k] };
}

/// The template with the text's characters in place of its underscores ('_' where it runs out).
pub fn merge(tmplt: []const u8, text: []const u8, out: *[SHOWN]u8) []const u8 {
    const t = if (text.len > 0 and text[0] == '@') "" else text; // "@": an empty field, as the AES
    var k: usize = 0;
    const n = @min(tmplt.len, SHOWN);
    for (tmplt[0..n], 0..) |c, i| {
        out[i] = c;
        if (c != '_') continue;
        if (k < t.len) out[i] = t[k];
        k += 1;
    }
    return out[0..n];
}

/// The template column the text's character `idx` sits in (its caret), the template's length past it.
pub fn caretCol(tmplt: []const u8, idx: usize) usize {
    var k: usize = 0;
    for (tmplt, 0..) |c, i| if (c == '_') {
        if (k == idx) return i;
        k += 1;
    };
    return tmplt.len;
}

// --- native tests -------------------------------------------------------------
const expect = std.testing.expect;

test "a wire tree loads with its strings and an editable field merged into its template" {
    var mem: [256]u8 align(4) = @splat(0);
    const m: Mem = .{ .base = 0x1000, .bytes = &mem };
    const o = std.mem.bytesAsSlice(Obj, mem[0..72]);
    o[0] = .{ .next = -1, .head = 1, .tail = 2, .ty = obj.G_BOX, .flags = 0, .state = 0, .spec = 0x11100, .x = 0, .y = 0, .w = 100, .h = 50 };
    o[1] = .{ .next = 2, .head = -1, .tail = -1, .ty = obj.G_BUTTON, .flags = obj.SELECTABLE, .state = 0, .spec = 0x1000 + 100, .x = 4, .y = 4, .w = 40, .h = 10 };
    o[2] = .{ .next = 0, .head = -1, .tail = -1, .ty = obj.G_FTEXT, .flags = obj.EDITABLE | obj.LASTOB, .state = 0, .spec = 0x1000 + 120, .x = 4, .y = 20, .w = 64, .h = 8 };
    @memcpy(mem[100..103], "OK\x00");
    const t: *align(1) Ted = @ptrCast(&mem[120]);
    t.* = .{ .text = 0x1000 + 160, .tmplt = 0x1000 + 170, .valid = 0x1000 + 190, .font = 3, .fontid = 0, .just = 0, .color = 0x1180, .fontsize = 0, .thickness = 0, .txtlen = 7, .tmplen = 9 };
    @memcpy(mem[160..164], "091\x00");
    @memcpy(mem[170..179], "__/__/__\x00");
    var s: Store = .{};
    const tree = load(m, 0x1000, 3, &s).?;
    try expect(std.mem.eql(u8, tree[1].spec.str, "OK"));
    try expect(std.mem.eql(u8, tree[2].spec.ted.text, "09/1_/__"));
    try expect(caretCol("__/__/__", 3) == 4 and caretCol("__/__/__", 6) == 8);
}

test "addresses outside the window are refused or read as empty" {
    var mem: [64]u8 = @splat(0);
    const m: Mem = .{ .base = 0x1000, .bytes = &mem };
    var s: Store = .{};
    try expect(load(m, 0x900, 1, &s) == null); // below the window
    try expect(load(m, 0x1000 + 48, 1, &s) == null); // runs past its end
    try expect(load(m, 0x1000, 0, &s) == null and load(m, 0x1000, MAX_OBJ + 1, &s) == null);
    try expect(m.str(0x5000).len == 0 and m.str(0x1000 + 64).len == 0);
}
