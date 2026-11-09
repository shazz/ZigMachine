// --------------------------------------------------------------------------
// NOTEPAD's menu bar and keyboard shortcuts: one table of commands, read both by
// the bar (titles, labels with the ^key TOS showed on the right) and by the keys.
// The bar is the ROM's (aes.MenuBar, menu_bar): the program only says what is in it.
// --------------------------------------------------------------------------
const rom = @import("rom_sdk");
const aes = rom.aes;

pub const Cmd = enum { about, new, open, save, save_as, quit, cut, copy, paste, select_all, find, none };

const Entry = struct { label: []const u8, cmd: Cmd, key: u8 = 0 };
const SEP = Entry{ .label = "-", .cmd = .none };

const DESK = [_]Entry{.{ .label = "About Notepad...", .cmd = .about }};
const FILE = [_]Entry{
    .{ .label = "New         ^N", .cmd = .new, .key = 'n' },
    .{ .label = "Open...     ^O", .cmd = .open, .key = 'o' },
    SEP,
    .{ .label = "Save        ^S", .cmd = .save, .key = 's' },
    .{ .label = "Save As...    ", .cmd = .save_as },
    SEP,
    .{ .label = "Quit        ^Q", .cmd = .quit, .key = 'q' },
};
const EDIT = [_]Entry{
    .{ .label = "Cut         ^X", .cmd = .cut, .key = 'x' },
    .{ .label = "Copy        ^C", .cmd = .copy, .key = 'c' },
    .{ .label = "Paste       ^V", .cmd = .paste, .key = 'v' },
    SEP,
    .{ .label = "Select All  ^A", .cmd = .select_all, .key = 'a' },
    .{ .label = "Find...     ^F", .cmd = .find, .key = 'f' },
};
const MENUS = [_]struct { title: []const u8, items: []const Entry }{
    .{ .title = "Desk", .items = &DESK },
    .{ .title = "File", .items = &FILE },
    .{ .title = "Edit", .items = &EDIT },
};
pub const EDIT_MENU = 2;
pub const CUT = 0;
pub const COPY = 1;
pub const PASTE = 2;

/// The bar, built once a run (menu_bar).
pub fn build(bar: aes.MenuBar) bool {
    bar.reset();
    for (MENUS) |m| {
        if (!bar.title(m.title)) return false;
        for (m.items) |it| if (!bar.item(it.label, if (it.cmd == .none) aes.MENU_DISABLED else 0)) return false;
    }
    return true;
}

/// A pick off the bar ({menu, item}) as a command.
pub fn ofPick(p: [2]u8) Cmd {
    if (p[0] >= MENUS.len) return .none;
    const items = MENUS[p[0]].items;
    return if (p[1] < items.len) items[p[1]].cmd else .none;
}

/// Control + letter (either case; or the control code 1..26 a keyboard may send) as a command.
pub fn ofKey(letter: u8) Cmd {
    const l = if (letter >= 1 and letter <= 26) letter + 'a' - 1 else letter | 0x20;
    for (MENUS) |m| for (m.items) |it| if (it.key != 0 and it.key == l) return it.cmd;
    return .none;
}

/// Edit's items as the document allows (menu_ienable): Cut / Copy need a selection, Paste a clip.
pub fn enable(bar: aes.MenuBar, has_sel: bool, has_clip: bool) void {
    const off = aes.MENU_DISABLED;
    bar.flags(EDIT_MENU, CUT, if (has_sel) 0 else off);
    bar.flags(EDIT_MENU, COPY, if (has_sel) 0 else off);
    bar.flags(EDIT_MENU, PASTE, if (has_clip) 0 else off);
}
