// --------------------------------------------------------------------------
// Where the ITEM SELECTOR's pieces go (G21), for a font `ch` pixels tall: 8 in
// low and medium (the 8x8 font, as TOS draws it there), 16 on a 400+ line screen
// (the desk, ST high: the 8x16 font). The box keeps TOS 4's arrangement — the path
// as its title, Directory: over its field, Selection: with DRIVE: beside it, the
// list as a little window (closer, mask title, nine rows a font height apart, a
// scroll column), the drive buttons in two columns, OK and Cancel — but the
// numbers in `ours` are OUR layout, in cells of `ch` plus pixels, not TOS's tree.
//
// A ROM built with Matt's local assets (-Dgem_assets) replaces them with the
// geometry its converter read from the reconstruction (fsel_draw.zig: geomFor);
// that geometry is never committed (decisions.md 2026-11-09).
// Pure: no ZigOS, `zig test` covers it.
// --------------------------------------------------------------------------

/// A rectangle in the box (x, y from the box's top left).
pub const R = struct {
    x: i16,
    y: i16,
    w: i16,
    h: i16,
    pub fn bottom(r: R) i16 {
        return r.y + r.h;
    }
};

pub const Geom = struct {
    ch: i16, // the font height the layout is for
    w: i16,
    h: i16,
    title_y: i16, // the path, centred
    dir_label: R,
    dir: R, // the Directory: field (37 cells)
    sel_label: R,
    sel: R, // the Selection: field (12 cells)
    drive_label: R,
    closer: R,
    mask: R, // the list window's title
    list: R,
    row: R, // the first row; the others `pitch` below
    pitch: i16,
    scroll: R, // the scroll column: up, track, down
    up: R,
    track: R,
    down: R,
    drives: R, // the drive group
    drive: R, // A:; B: `dx` right of it, C: `dy` below
    dx: i16,
    dy: i16,
    ok: R,
    cancel: R,
    core: bool = false, // the indicators' rects are the 3D cores (drawn L.ADJ3D larger), not their drawn size
};

/// Our own layout for a `ch`-pixel font (8 or 16): compact, every row of text one font height.
pub fn ours(ch: i16) Geom {
    const c = ch;
    const pad = @divTrunc(c, 2) + 4; // 8 / 12: the margins round the list and the buttons
    const bar_y = 4 * c + 16; // the list window's title bar, the drive group's top
    const list: R = .{ .x = 24, .y = bar_y + c + 1, .w = 158, .h = 11 * c };
    const dy = c + 5; // a drive button is c + 2 tall: one pixel apart even drawn 3D
    const drives: R = .{ .x = 216, .y = bar_y, .w = 80, .h = 8 * dy };
    const by = @max(list.bottom(), drives.bottom()) + @divTrunc(pad, 2) + 2;
    const sy = 3 * c + 12; // the Selection: line
    const arrow = 2 * c;
    return .{
        .ch = c,
        .w = 312,
        .h = by + c + 2 + pad,
        .title_y = @divTrunc(c, 8) + 4,
        .dir_label = .{ .x = 8, .y = @divTrunc(c, 8) + c + 6, .w = 80, .h = c },
        .dir = .{ .x = 8, .y = 2 * c + 8, .w = 296, .h = c },
        .sel_label = .{ .x = 8, .y = sy, .w = 80, .h = c },
        .sel = .{ .x = 96, .y = sy, .w = 96, .h = c },
        .drive_label = .{ .x = 232, .y = sy, .w = 48, .h = c },
        .closer = .{ .x = 24, .y = bar_y, .w = 16, .h = c + 2 },
        .mask = .{ .x = 39, .y = bar_y, .w = 167, .h = c + 2 },
        .list = list,
        .row = .{ .x = list.x + 8, .y = list.y + c, .w = 15 * 8, .h = c },
        .pitch = c,
        .scroll = .{ .x = 181, .y = list.y, .w = 24, .h = list.h },
        .up = .{ .x = 181, .y = list.y, .w = 24, .h = arrow },
        .track = .{ .x = 181, .y = list.y + arrow - 1, .w = 24, .h = list.h - 2 * arrow + 2 },
        .down = .{ .x = 181, .y = list.bottom() - arrow, .w = 24, .h = arrow },
        .drives = drives,
        .drive = .{ .x = drives.x + 4, .y = drives.y, .w = 32, .h = c + 2 },
        .dx = 40,
        .dy = dy,
        .ok = .{ .x = 64, .y = by, .w = 72, .h = c + 2 },
        .cancel = .{ .x = 176, .y = by, .w = 72, .h = c + 2 },
    };
}

/// The font height a screen `sh` lines tall draws the selector in.
pub fn cellFor(sh: i16) i16 {
    return if (sh >= 400) 16 else 8;
}
