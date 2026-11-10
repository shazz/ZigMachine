// --------------------------------------------------------------------------
// GEM 5's program API, object trees (G20, system table 1.23; the ROM half is
// rom/rom_app_obj.zig): a program lays out an AES OBJECT array (and its TEDINFOs
// and strings) in its OWN memory, as a TOS program's RSC tree was, and the ROM
// draws it (objc_draw) in the program look (flat TOS 1 or 3D TOS 4), finds the
// object under a point (objc_find), applies a click (form_button: radio groups,
// toggles, DISABLED), changes a state (objc_change) and edits a G_FTEXT
// (objc_edit). Reached as `rom.aes.obj`. Only numbers cross: the tree's address.
// --------------------------------------------------------------------------
const rom = @import("rom.zig");
const Rect = rom.Rect;

pub extern fn objcDraw(h: u32, tree: u32, n: u32, start: u32, depth: u32, cx: i32, cy: i32, cw: i32, ch: i32) void;
pub extern fn objcFind(h: u32, tree: u32, n: u32, start: u32, depth: u32, x: i32, y: i32) i32;
pub extern fn objcChange(h: u32, tree: u32, n: u32, obj: u32, state: u32, redraw: u32) void;
pub extern fn formButton(h: u32, tree: u32, n: u32, obj: u32) u32;
pub extern fn objcEdit(h: u32, tree: u32, n: u32, obj: u32, kind: u32, key: u32, idx: u32) i32;
pub extern fn winDesk(h: u32, tree: u32, n: u32) void; // WF_NEWDESK (1.24)
pub extern fn winDeskDraw(h: u32, cx: i32, cy: i32, cw: i32, ch: i32) u32;

/// An ICONBLK (the AES's 34 bytes; this struct pads to 36). `pmask` 0: `pdata` names one of the ROM's
/// own icons (SYS_*), the desktop's set; else both point at the program's 1 bpp images, rows
/// word-padded. `char`'s high byte: data colour (bits 15..12), mask colour (11..8).
pub const Iconblk = extern struct { pmask: u32 = 0, pdata: u32 = 0, ptext: u32 = 0, char: u16 = 0x1000, xchar: i16 = 0, ychar: i16 = 0, xicon: i16 = 0, yicon: i16 = 0, wicon: i16 = 32, hicon: i16 = 32, xtext: i16 = 0, ytext: i16 = 32, wtext: i16 = 72, htext: i16 = 8 };
pub const G_ICON: u16 = 31;
pub const SYS_FLOPPY: u32 = 0;
pub const SYS_HARD: u32 = 1;
pub const SYS_TRASH: u32 = 2;
pub const SYS_FOLDER: u32 = 3;
pub const SYS_PROGRAM: u32 = 4;
pub const SYS_DOCUMENT: u32 = 5;

/// WF_NEWDESK: `objs` is the program's desktop (root: the desk, children: its icons); empty: none.
pub fn setDesk(g: rom.Gui, objs: []Object) void {
    winDesk(g.h, addr(objs.ptr), @intCast(objs.len));
}
/// The program's desktop inside `r` (a desk WM_REDRAW rectangle); false: none registered.
pub fn drawDesk(g: rom.Gui, r: Rect) bool {
    return winDeskDraw(g.h, r.x, r.y, r.w, r.h) != 0;
}

/// The AES's OBJECT and TEDINFO, byte for byte (24 and 28 bytes).
pub const Object = extern struct { next: i16 = -1, head: i16 = -1, tail: i16 = -1, ty: u16 = G_IBOX, flags: u16 = 0, state: u16 = 0, spec: u32 = 0, x: i16 = 0, y: i16 = 0, w: i16 = 0, h: i16 = 0 };
pub const Ted = extern struct { text: u32, tmplt: u32, valid: u32, font: i16 = 3, fontid: i16 = 0, just: i16 = 0, color: i16 = 0x1180, fontsize: i16 = 0, thickness: i16 = 0, txtlen: i16, tmplen: i16 };

pub const G_BOX: u16 = 20;
pub const G_TEXT: u16 = 21;
pub const G_BOXTEXT: u16 = 22;
pub const G_IBOX: u16 = 25;
pub const G_BUTTON: u16 = 26;
pub const G_BOXCHAR: u16 = 27;
pub const G_STRING: u16 = 28;
pub const G_FTEXT: u16 = 29;
pub const G_FBOXTEXT: u16 = 30;

pub const SELECTABLE: u16 = 0x0001;
pub const DEFAULT: u16 = 0x0002;
pub const EXIT: u16 = 0x0004;
pub const EDITABLE: u16 = 0x0008;
pub const RBUTTON: u16 = 0x0010;
pub const LASTOB: u16 = 0x0020;
pub const TOUCHEXIT: u16 = 0x0040;
pub const FL3DIND: u16 = 0x0200;
pub const FL3DBAK: u16 = 0x0400;
pub const FL3DACT: u16 = 0x0600;

pub const SELECTED: u16 = 0x0001;
pub const DISABLED: u16 = 0x0008;
pub const OUTLINED: u16 = 0x0010;

pub const ED_INIT: u32 = 1; // objc_edit: show the caret at idx
pub const ED_CHAR: u32 = 2; // a key at the caret
pub const ED_END: u32 = 3; // hide the caret

/// A G_BOX spec word: border thickness, colours (border, text, replace, pattern, interior).
pub fn boxSpec(char: u8, thickness: i8, color: u16) u32 {
    return @as(u32, char) << 24 | @as(u32, @as(u8, @bitCast(thickness))) << 16 | color;
}
pub fn addr(p: anytype) u32 {
    return @intCast(@intFromPtr(p));
}

/// A tree in the program's memory, the calls on it.
pub const Tree = struct {
    g: rom.Gui,
    objs: []Object,

    fn a(self: Tree) u32 {
        return addr(self.objs.ptr);
    }
    fn n(self: Tree) u32 {
        return @intCast(self.objs.len);
    }
    /// objc_draw of `start` and `depth` levels under it, clipped to `clip`.
    pub fn draw(self: Tree, start: u32, depth: u32, clip: Rect) void {
        objcDraw(self.g.h, self.a(), self.n(), start, depth, clip.x, clip.y, clip.w, clip.h);
    }
    /// objc_find: the object under (x, y), null when outside `start`.
    pub fn find(self: Tree, start: u32, x: i32, y: i32) ?u16 {
        const r = objcFind(self.g.h, self.a(), self.n(), start, 8, x, y);
        return if (r < 0) null else @intCast(r);
    }
    pub fn change(self: Tree, o: u32, state: u16, redraw: bool) void {
        objcChange(self.g.h, self.a(), self.n(), o, state, @intFromBool(redraw));
    }
    /// form_button for a click on `o`: .exit (an EXIT / TOUCHEXIT object), .changed (redraw).
    pub fn button(self: Tree, o: u32) struct { exit: bool, changed: bool } {
        const r = formButton(self.g.h, self.a(), self.n(), o);
        return .{ .exit = r & 1 != 0, .changed = r & 2 != 0 };
    }
    /// objc_edit on the G_FTEXT `o`: the caret's new index.
    pub fn edit(self: Tree, o: u32, kind: u32, key: u32, idx: u32) u32 {
        const r = objcEdit(self.g.h, self.a(), self.n(), o, kind, key, idx);
        return if (r < 0) idx else @intCast(r);
    }
};
