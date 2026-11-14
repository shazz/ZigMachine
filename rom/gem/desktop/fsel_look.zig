// --------------------------------------------------------------------------
// The ITEM SELECTOR's layout and font for the screen it opens on: the 8x8 font
// below 400 lines (low, medium: TOS's 8-pixel cells), the 8x16 one from 400 (the
// desk, ST high: TOS's 16-pixel cells). The 8x16 font is the asset set's when it
// has one (a local -Dgem_assets build), else ZigOS's 8x8 drawn with each row twice.
// The layout is the asset set's own selector geometry for that font height when
// the set has it (tools/gem_assets_fsel.py, never committed), else ours
// (fsel_geom.zig).
// --------------------------------------------------------------------------
const ga = @import("gem_assets");
const gui = @import("../gui.zig");
const L = @import("../engine/look.zig");
const G = @import("fsel_geom.zig");
const proglook = gui.proglook;

/// The layout for a screen `sh` lines tall.
pub fn geomFor(sh: i16) G.Geom {
    const ch = G.cellFor(sh);
    for (ga.selectors) |s| if (s.ch == ch) return fromSet(s);
    return G.ours(ch);
}

fn r(v: [4]i16) G.R {
    return .{ .x = v[0], .y = v[1], .w = v[2], .h = v[3] };
}

// The set's geometry: its indicator rects are the 3D cores (drawn L.ADJ3D larger), as TOS lays them out.
fn fromSet(s: ga.Selector) G.Geom {
    return .{
        .ch = s.ch,                 .w = s.w,                   .h = s.h,
        .title_y = s.title_y,       .dir_label = r(s.dir_label), .dir = r(s.dir),
        .sel_label = r(s.sel_label), .sel = r(s.sel),           .drive_label = r(s.drive_label),
        .closer = r(s.closer),      .mask = r(s.mask),          .list = r(s.list),
        .row = r(s.row),            .pitch = s.pitch,           .scroll = r(s.scroll),
        .up = r(s.up),              .track = r(s.track),        .down = r(s.down),
        .drives = r(s.drives),      .drive = r(s.drive),        .dx = s.dx,
        .dy = s.dy,                 .ok = r(s.ok),              .cancel = r(s.cancel),
        .core = true,
    };
}

var tall: L.Font = undefined;

/// The program look with the font the layout `geo` is for.
pub fn lookFor(g: *const gui.Gui, geo: *const G.Geom) L.Look {
    var lk = proglook.look(g);
    if (geo.ch != 16) return lk;
    const set = proglook.setOf(g);
    tall = set.tall orelse .{ .w = set.sys.w, .h = set.sys.h * 2, .data = set.sys.data, .packed_rows = set.sys.packed_rows, .tall = true };
    lk.font = &tall;
    return lk;
}
