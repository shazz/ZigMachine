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

const desktop = @import("desktop/desktop.zig");
pub const Action = desktop.Action;
pub const Desktop = desktop.Desktop;
pub const setDrive = @import("desktop/desk_icons.zig").setDrive;
pub const setDriveC = @import("desktop/desk_icons.zig").setDriveC; // KOS's C: (docs/KOS_FAT.md F5)
pub const driveOfUnit = @import("desktop/deskdrive.zig").ofUnit;
pub const loadInf = @import("desktop/deskmode.zig").loadInf; // DESKTOP.INF off the boot disk
pub const INF_MAX = @import("desktop/deskinf.zig").MAX_BYTES;
pub const touch = @import("desktop/deskdirty.zig").touch; // a host wrote the desktop's state: repaint
pub const mustDraw = @import("desktop/deskdirty.zig").mustDraw; // the next render draws (deskRender's flip)
pub const deskflip = @import("desktop/deskflip.zig"); // the desk's two buffers
pub const DirModel = @import("desktop/dirmodel.zig").DirModel;
// The FAT record layout the host packs into Desktop.disk_dir. Published
// because the ROM clamps against it and the host must derive its own cap
// from it rather than mirroring the number (see deskDirCap).
pub const FILE_ENT = desktop.FILE_ENT;
pub const MAX_FILES = desktop.MAX_FILES;

// GEM services an app can put on screen itself. The ITEM SELECTOR is the box
// every TOS program opens for "Load from disc".
pub const FileSel = @import("desktop/filesel.zig").FileSel;
pub const FileSelResult = @import("desktop/filesel.zig").Result;
