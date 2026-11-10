// --------------------------------------------------------------------------
// GEMTEST's areas: one window per part of GEM 5 (four for the windows), each
// labelled with what it exercises. What the program API has is shown working;
// what it lacks is a grey "not in the API yet: ..." line (docs/GEMTEST.md lists
// them): the program never reaches into the ROM to fake one.
// --------------------------------------------------------------------------
const Pen = @import("pen.zig").Pen;
const App = @import("../gemtest.zig").App;
const show = @import("area_show.zig");
const dialogs = @import("area_dialogs.zig");
const misc = @import("area_misc.zig");

pub const Area = enum(u8) { windows = 1, menus, dialogs, alerts, files, text, icons, modes };

pub fn windows(a: Area) usize {
    return if (a == .windows) 4 else 1;
}

pub fn title(a: Area, part: u8) []const u8 {
    return switch (a) {
        .windows => switch (part) {
            0 => " GADGETS ",
            1 => " OVERLAP A ",
            2 => " OVERLAP B ",
            else => " LARGER THAN THE SCREEN ",
        },
        .menus => " MENUS ",
        .dialogs => " DIALOGS (OBJECTS) ",
        .alerts => " ALERTS (FORM_ALERT) ",
        .files => " FILE SELECTOR (FSEL_INPUT) ",
        .text => " TEXT AND FONTS ",
        .icons => " ICONS ",
        .modes => " SCREEN MODES ",
    };
}

/// The info line (wind_set WF_INFO), under the title.
pub fn info(a: Area, part: u8) []const u8 {
    return switch (a) {
        .windows => if (part == 0) "Info line: move, size, full, scroll, close" else "Click to top, drag to move",
        .menus => "Open the Menus title; ^L is its shortcut",
        .dialogs => "Click the controls; type in the field",
        .alerts => "Each icon with 1, 2 and 3 buttons",
        .files => "A: and C:, the result below",
        .text => "Scroll both ways: long and wide text",
        .icons => "The desktop's icon set",
        .modes => "Getrez, and keys 1 2 3",
    };
}

/// The content of window `i` of the area on show.
pub fn draw(p: *Pen, app: *App, a: Area, i: u8) void {
    switch (a) {
        .windows => show.windows(p, app, i),
        .text => show.text(p),
        .dialogs => dialogs.draw(p, app),
        .menus => misc.menus(p, app),
        .alerts => misc.alerts(p, app),
        .files => misc.files(p, app),
        .icons => misc.icons(p),
        .modes => misc.modes(p, app),
    }
}

/// A press on control `id` of the top window.
pub fn press(app: *App, a: Area, id: u8) void {
    switch (a) {
        .dialogs => dialogs.press(app, id),
        .alerts, .files, .modes => misc.press(app, a, id),
        else => {},
    }
}

/// A key while the area is on top; true when the area took it.
pub fn key(app: *App, a: Area, cp: u32) bool {
    return a == .dialogs and dialogs.key(app, cp);
}
