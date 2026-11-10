// --------------------------------------------------------------------------
// GEMTEST's menu bar: one table read by the bar (titles, items, the ^key shown
// at the right, as TOS did) and by the keyboard (Control + letter). The bar is
// the ROM's (aes.MenuBar); its titles are short enough for low res (320 px).
// The "Menus" title is the menu test itself: a disabled item, separators, two
// checked items that toggle, a working shortcut and a disabled one.
// --------------------------------------------------------------------------
const rom = @import("rom_sdk");
const aes = rom.aes;
const Area = @import("areas.zig").Area;

pub const Cmd = union(enum) {
    none,
    about,
    area: Area,
    close_all,
    quit,
    /// the Menus title's items: 0 plain, 1 checked, 2 second check, 3 the shortcut
    probe: u8,
    /// form_alert icon * 3 + buttons - 1 (0..11); 12 a malformed string
    alert: u8,
    /// 0 low, 1 medium, 2 the desk
    mode: u8,
};

const Entry = struct { label: []const u8, cmd: Cmd, key: u8 = 0, flags: u32 = 0 };
const SEP = Entry{ .label = "-", .cmd = .none, .flags = aes.MENU_DISABLED };

const DESK = [_]Entry{.{ .label = "  About GEMTEST...", .cmd = .about }};
const TEST = [_]Entry{
    .{ .label = "  Windows        ^W", .cmd = .{ .area = .windows }, .key = 'w' },
    .{ .label = "  Menus          ^E", .cmd = .{ .area = .menus }, .key = 'e' },
    .{ .label = "  Dialogs        ^D", .cmd = .{ .area = .dialogs }, .key = 'd' },
    .{ .label = "  Alerts         ^A", .cmd = .{ .area = .alerts }, .key = 'a' },
    .{ .label = "  File selector  ^F", .cmd = .{ .area = .files }, .key = 'f' },
    .{ .label = "  Text and fonts ^T", .cmd = .{ .area = .text }, .key = 't' },
    .{ .label = "  Icons          ^I", .cmd = .{ .area = .icons }, .key = 'i' },
    .{ .label = "  Screen modes   ^R", .cmd = .{ .area = .modes }, .key = 'r' },
    SEP,
    .{ .label = "  Close windows  ^K", .cmd = .close_all, .key = 'k' },
    SEP,
    .{ .label = "  Quit           ^Q", .cmd = .quit, .key = 'q' },
};
const PROBE = [_]Entry{
    .{ .label = "  Plain item", .cmd = .{ .probe = 0 } },
    .{ .label = "  Disabled item", .cmd = .none, .flags = aes.MENU_DISABLED },
    SEP,
    .{ .label = "  Checked item", .cmd = .{ .probe = 1 }, .flags = aes.MENU_CHECKED },
    .{ .label = "  Second check", .cmd = .{ .probe = 2 } },
    SEP,
    .{ .label = "  Shortcut       ^L", .cmd = .{ .probe = 3 }, .key = 'l' },
    .{ .label = "  Disabled short ^U", .cmd = .none, .key = 'u', .flags = aes.MENU_DISABLED },
};
const ALERTS = alertEntries();
const MODE = [_]Entry{
    .{ .label = "  Low    320x200  1", .cmd = .{ .mode = 0 } },
    .{ .label = "  Medium 640x200  2", .cmd = .{ .mode = 1 } },
    .{ .label = "  Desk   640x480  3", .cmd = .{ .mode = 2 } },
};
const MENUS = [_]struct { title: []const u8, items: []const Entry }{
    .{ .title = "Desk", .items = &DESK },
    .{ .title = "Test", .items = &TEST },
    .{ .title = "Menus", .items = &PROBE },
    .{ .title = "Alerts", .items = &ALERTS },
    .{ .title = "Mode", .items = &MODE },
};
pub const PROBE_MENU = 2;
pub const MODE_MENU = 4;
pub const CHECK_ITEM = 3; // PROBE's "Checked item"
pub const CHECK2_ITEM = 4;

const ICONS = [_][]const u8{ "None", "Note", "Wait", "Stop" };
fn alertEntries() [13]Entry {
    var out: [13]Entry = undefined;
    inline for (0..12) |k| {
        const nb = k % 3 + 1;
        out[k] = .{ .label = "  " ++ ICONS[k / 3] ++ ", " ++ [_]u8{'0' + nb} ++ (if (nb == 1) " button" else " buttons"), .cmd = .{ .alert = k } };
    }
    out[12] = .{ .label = "  Malformed string", .cmd = .{ .alert = 12 } };
    return out;
}

/// The bar, built once a run (menu_bar).
pub fn build(bar: aes.MenuBar) bool {
    bar.reset();
    for (MENUS) |m| {
        if (!bar.title(m.title)) return false;
        for (m.items) |it| if (!bar.item(it.label, it.flags)) return false;
    }
    return true;
}

/// A pick off the bar ({menu, item}) as a command.
pub fn ofPick(p: [2]u8) Cmd {
    if (p[0] >= MENUS.len) return .none;
    const items = MENUS[p[0]].items;
    return if (p[1] < items.len) items[p[1]].cmd else .none;
}

/// Control + letter (either case, or the control code 1..26) as a command; a disabled item's
/// shortcut does nothing, as on TOS.
pub fn ofKey(letter: u8) Cmd {
    const l = if (letter >= 1 and letter <= 26) letter + 'a' - 1 else letter | 0x20;
    for (MENUS) |m| for (m.items) |it| if (it.key != 0 and it.key == l) return it.cmd;
    return .none;
}

/// The checks the program keeps (menu_icheck): the two probes, the current mode; Desk greyed
/// where the machine has no desk mode (menu_ienable).
pub fn checks(bar: aes.MenuBar, c1: bool, c2: bool, mode: u8, desk_ok: bool) void {
    const on = aes.MENU_CHECKED;
    bar.flags(PROBE_MENU, CHECK_ITEM, if (c1) on else 0);
    bar.flags(PROBE_MENU, CHECK2_ITEM, if (c2) on else 0);
    for (0..3) |i| {
        var f: u32 = if (mode == i) on else 0;
        if (i == 2 and !desk_ok) f |= aes.MENU_DISABLED;
        bar.flags(MODE_MENU, @intCast(i), f);
    }
}
