// --------------------------------------------------------------------------
// ZigOS GUI — a small GEM-style windowing toolkit (open library).
//
// This file is the library's HUB: it re-exports the toolkit that now lives in
// zigos/gui/ so consumers keep using `gui.Gui`, `gui.Wm`, `gui.Dialog`, … and
// the palette/metric constants unchanged. See each sub-file for the detail:
//   types.zig  — Rect, palette + installPalette, GEM metrics, Window
//   core.zig   — Gui (pointer state + immediate-mode primitives + buttons)
//   window.zig — Wm (retained windows, drag/resize/z-order)
//   chrome.zig — window drawing (shadow, title bar, info line, scrollbars)
//   dialog.zig — modal Dialog (alert + file selector) + DlgResult
//   menu.zig   — Menu, MenuBar (GEM pull-down menus)
//
// Immediate-mode drawing over the blitter (fast fills) + ZigOS text, plus a
// tiny retained window manager. Pointer state comes from the host via
// demo.pointer() (see sealed-loader.js). Resolution-agnostic: everything is in
// the visible space; a medium-res mode widens it without changing this code.
// --------------------------------------------------------------------------
const types = @import("gui/types.zig");
const core = @import("gui/core.zig");
const window = @import("gui/window.zig");
const dialog = @import("gui/dialog.zig");
const menu = @import("gui/menu.zig");
const grid = @import("gui/grid.zig");

// --- palette ---
pub const BLACK = types.BLACK;
pub const WHITE = types.WHITE;
pub const LGRAY = types.LGRAY;
pub const MGRAY = types.MGRAY;
pub const DGRAY = types.DGRAY;
pub const DESK = types.DESK;
pub const ACCENT = types.ACCENT;
pub const WAVE = types.WAVE;
pub const installPalette = types.installPalette;

// --- geometry + metrics ---
pub const Rect = types.Rect;
pub const inRect = types.inRect;
// grid layout (8px character cells) for dialogs
pub const CELL = grid.CELL;
pub const Grid = grid.Grid;
pub const hspread = grid.hspread;
pub const gcenter = grid.center;
pub const MENU_H = types.MENU_H;
pub const ITEM_H = types.ITEM_H;
pub const TITLE_H = types.TITLE_H;
pub const INFO_H = types.INFO_H;
pub const SCROLL = types.SCROLL;
pub const MAX_WIN = types.MAX_WIN;

// --- widgets, windows, dialogs, menus ---
pub const Gui = core.Gui;
pub const Window = types.Window;
pub const Wm = window.Wm;
pub const DlgResult = dialog.DlgResult;
pub const Dialog = dialog.Dialog;
pub const Menu = menu.Menu;
pub const MenuItem = menu.MenuItem;
pub const MenuPick = menu.MenuPick;
pub const MenuBar = menu.MenuBar;
pub const isSeparator = menu.isSeparator;
