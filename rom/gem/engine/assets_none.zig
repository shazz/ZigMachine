// --------------------------------------------------------------------------
// The GEM asset set compiled in when the build names none (no -Dgem_assets): the
// gate, the browser and Pages build. Nothing here: the desktop keeps the TOS 1.0
// set that is in the repo (gem_icons.zig, gem_glyphs.zig, ZigOS's fonts).
//
// tools/gem_assets_conv.py writes a module with these same declarations, filled
// from a LOCAL asset directory, into the build cache (never the source tree).
// --------------------------------------------------------------------------
pub const present = false;
pub const name: []const u8 = "TOS 1.0 (built in)";

pub const Font = struct { w: u8, h: u8, data: []const u8 };
pub const Mouse = struct { mask: [16]u16, data: [16]u16, hx: i8, hy: i8 };
pub const Icon = struct { id: []const u8, w: i16, h: i16, mask: []const u8, data: []const u8, col: ?[]const u8 = null };
pub const Obj = struct {
    next: i16,
    head: i16,
    tail: i16,
    ty: u8,
    flags: u16,
    state: u16,
    x: i16,
    y: i16,
    w: i16,
    h: i16,
    kind: u8 = 0, // 0 none, 1 box, 2 string, 3 ted, 4 icon (by its label), 5 image
    box: u32 = 0,
    str: []const u8 = "",
    font: u8 = 3,
    just: u8 = 0,
    color: u16 = 0,
    thick: i8 = 0,
};
/// The ITEM SELECTOR's geometry for a `ch`-pixel font, read by the converter from the set's own
/// selector tree (desktop/fsel_geom.zig's Geom: each rect x, y, w, h in the box; the indicators'
/// rects are 3D cores).
pub const R4 = [4]i16;
pub const Selector = struct { ch: u8, w: i16, h: i16, title_y: i16, dir_label: R4, dir: R4, sel_label: R4, sel: R4, drive_label: R4, closer: R4, mask: R4, list: R4, row: R4, pitch: i16, scroll: R4, up: R4, track: R4, down: R4, drives: R4, drive: R4, dx: i16, dy: i16, ok: R4, cancel: R4 };
pub const Tree = struct { group: []const u8, name: []const u8, objs: []const Obj };

pub const font_8x16: ?Font = null;
pub const font_8x8: ?Font = null;
pub const font_6x6: ?Font = null;
pub const arrow: ?Mouse = null;
pub const busy: ?Mouse = null;
pub const icons: []const Icon = &.{};
pub const cicons: []const Icon = &.{};
pub const images: []const Icon = &.{}; // form_alert's NOTE / QUES / STOP (TOS 4's BITBLKs)
pub const patterns: []const [16]u16 = &.{};
pub const palette: ?[16][3]u8 = null;
pub const trees: []const Tree = &.{};
pub const selectors: []const Selector = &.{};
