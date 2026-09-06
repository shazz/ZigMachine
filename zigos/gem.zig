// --------------------------------------------------------------------------
// ZigGEM — the "ROM": a GEM-style desktop + the GUI libraries an application
// links against. Think of it as the system in ROM; an app in apps/ is the RAM
// cartridge that plugs into it. The desktop boots first, shows icons, and
// launches an app; the app draws over the whole screen and returns here on quit.
//
// This file is the ROM's HUB. The desktop shell now lives in zigos/gem/:
//   desktop.zig    — Desktop state + per-frame render loop + Action
//   desk_icons.zig — DeskIcon model, icon drawing + interaction
//   prefs.zig      — Options > Set Preferences dialog
// The GUI toolkit (windows, menus, dialogs, buttons) lives in gui.zig and is
// re-exported here as `gem.gui` — the ROM's library surface. Apps use it.
// --------------------------------------------------------------------------
pub const gui = @import("gui.zig"); // the ROM's GUI libraries (apps link this)
pub const icons = @import("gem_icons.zig"); // 1bpp icons ripped from a GEM icon sheet

const desktop = @import("gem/desktop.zig");
pub const Action = desktop.Action;
pub const Desktop = desktop.Desktop;
