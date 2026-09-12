// --------------------------------------------------------------------------
// The ROM's app-facing ABI — the header an APP gets of the system software.
//
// Every entry point is `extern`: the bodies live in rom.wasm (rom/rom_main.zig),
// resolved by the host at instantiation exactly like the machine's hw* calls. An
// app therefore links NONE of GEM — importing `rom` from an app is a layering
// mistake, and this header deliberately re-exports nothing from it.
//
// Only u32/i32 cross: handles instead of pointers, (ptr, len) for strings, a u32
// for a modal result. That is not a style choice — a wasm module boundary passes
// only numbers, so a *Gui, a slice, or an enum with a payload simply cannot make
// the trip. The handle wrappers at the bottom hide it: `g.rect(r, WHITE)` still
// reads like a method call.
//
// The ROM OWNS the state behind a handle. An app used to declare `g: gui.Gui` as
// its own field and reach through it (`g.blit.fill(g.fb, …)`); across a module
// boundary that cannot work, because the ROM's code and the app's are different
// binaries and only the shared linear MEMORY is common. Anything an app used to
// do by reaching through is an entry point of its own — see fill().
// --------------------------------------------------------------------------
const zg = @import("zigos");

// --- values, not calls ---
// Defined HERE, not re-exported from the ROM: a header that imported rom/gem
// would drag the whole toolkit back into every app. These must match
// rom/gem/gui/types.zig — they are part of the ABI, like a register offset.
pub const Rect = struct { x: i16, y: i16, w: i16, h: i16 };
// GEM's reserved palette. These are ABI, like a register offset — GEM draws in
// INDICES, so an app that does not know which ones GEM owns either clashes with
// it or guesses (ST Replay took 8, 9 and 10 on folklore). Must match
// rom/gem/gui/types.zig.
pub const BLACK: u8 = 0;
pub const WHITE: u8 = 1;
pub const LGRAY: u8 = 2;
pub const MGRAY: u8 = 3;
pub const DGRAY: u8 = 4;
pub const DESK: u8 = 5;
pub const ACCENT: u8 = 6;
pub const WAVE: u8 = 7;
/// The first index GEM does NOT reserve below its rainbow ramp — an app's own
/// colours go here.
pub const APP_PAL0: u8 = 8;
/// GEM's spectrum ramp (the Desktop Info logo cycles it).
pub const RAINBOW0: u8 = 16;
pub const RAINBOW_N: u8 = 32;
/// One character cell — the GEM layout unit. Layout in cells, not pixels.
pub const CELL: i16 = 8;

/// Text alignment for textAlign().
pub const Align = enum(u32) { left = 0, center = 1, right = 2 };

/// What a modal returned this frame.
pub const Result = enum(u32) { none = 0, ok = 1, cancel = 2 };

// --------------------------------------------------------------------------
// Entry points — exports of rom.wasm. Signatures ARE the ABI.
// --------------------------------------------------------------------------
/// Host-only: reclaim every handle the previous program held (see rom_main.zig).
pub extern fn romReset() void;

/// Open a context over a PLANE, for a caller with no ZigOS of its own — which is
/// every app not written in Zig. The ROM reads the plane's framebuffer base out of
/// the video registers and lends its own text renderer. This is the entry point
/// that makes "any language can call GEM" true rather than merely flat.
pub extern fn guiOpenPlane(plane: u32, screen_w: i32, screen_h: i32) u32;
/// Install GEM's palette into a plane — the companion to guiOpenPlane.
pub extern fn romInstallPalettePlane(plane: u32) void;
pub extern fn guiClose(h: u32) void;
pub extern fn guiResize(h: u32, screen_w: i32, screen_h: i32) void;
pub extern fn guiSetPointer(h: u32, x: i32, y: i32, buttons: u32) void;
pub extern fn guiBeginFrame(h: u32) void;
pub extern fn guiEndFrame(h: u32) void;
pub extern fn guiEdge(h: u32) u32;
pub extern fn guiHit(h: u32, x: i32, y: i32, w: i32, hh: i32) u32;
pub extern fn guiRect(h: u32, x: i32, y: i32, w: i32, hh: i32, color: u32) void;
pub extern fn guiFrame(h: u32, x: i32, y: i32, w: i32, hh: i32, color: u32) void;
pub extern fn guiPlot(h: u32, x: i32, y: i32, color: u32) void;
pub extern fn guiText(h: u32, ptr: u32, len: u32, x: i32, y: i32, ink: u32, paper: u32) void;
pub extern fn guiFill(h: u32, x: i32, y: i32, w: i32, hh: i32, color: u32) void;
pub extern fn guiBox(h: u32, x: i32, y: i32, w: i32, hh: i32, inset: u32) void;
pub extern fn guiButton(h: u32, x: i32, y: i32, w: i32, hh: i32, ptr: u32, len: u32, active: u32, border: u32) u32;
pub extern fn guiTextAlign(h: u32, x: i32, y: i32, w: i32, ptr: u32, len: u32, mode: u32, ink: u32, paper: u32) void;

pub extern fn dialogOpen() u32;
pub extern fn dialogClose(h: u32) void;
pub extern fn dialogAlert(h: u32, title: u32, title_len: u32, msg: u32, msg_len: u32) void;
pub extern fn dialogActive(h: u32) u32;
pub extern fn dialogProcess(h: u32, gui_h: u32) u32;

pub extern fn fileSelOpen() u32;
pub extern fn fileSelClose(h: u32) void;
pub extern fn fileSelShow(h: u32, mask: u32, mask_len: u32) void;
pub extern fn fileSelAdd(h: u32, name: u32, name_len: u32) void;
pub extern fn fileSelActive(h: u32) u32;
pub extern fn fileSelKey(h: u32, cp: u32) void;
pub extern fn fileSelProcess(h: u32, gui_h: u32) u32;
pub extern fn fileSelChosen(h: u32, out: u32, out_cap: u32) u32;

// --- the desktop (step 2.3) ---
// A singleton: there is one desktop and one screen. `deskRender` returns the
// Action flat — see DeskAction.
pub const DeskAction = enum(u32) { none = 0, launch = 1, res_low = 2, res_medium = 3 };

pub extern fn deskInitPlane(plane: u32, screen_w: i32, screen_h: i32) void;
pub extern fn deskSetScreen(w: i32, h: i32) void;
pub extern fn deskBeginFrame() void;
pub extern fn deskEndFrame() void;
pub extern fn deskRender() u32;
pub extern fn deskSetPointer(x: i32, y: i32, buttons: u32) void;
pub extern fn deskRequestOpenAt(x: i32, y: i32) void;
pub extern fn deskKey(cp: u32) void;
pub extern fn deskInput(dir: u32) void;
pub extern fn deskSetDiskApp(present: u32) void;
pub extern fn deskDirPtr() u32;
pub extern fn deskDirCap() u32;
pub extern fn deskDirMaxFiles() u32;
pub extern fn deskDirEntryBytes() u32;
pub extern fn deskSetFileCount(n: u32) void;
pub extern fn deskLaunchName(out: u32, out_cap: u32) u32;

/// The desktop, as a shell cart drives it.
pub const Desktop = struct {
    pub fn initPlane(plane: u32, w: i32, ht: i32) void {
        deskInitPlane(plane, w, ht);
    }
    pub fn setScreen(w: i32, h: i32) void {
        deskSetScreen(w, h);
    }
    pub fn beginFrame() void {
        deskBeginFrame();
    }
    pub fn endFrame() void {
        deskEndFrame();
    }
    pub fn render() DeskAction {
        return @enumFromInt(deskRender());
    }
    pub fn setPointer(x: i32, y: i32, buttons: u32) void {
        deskSetPointer(x, y, buttons);
    }
    pub fn requestOpenAt(x: i32, y: i32) void {
        deskRequestOpenAt(x, y);
    }
    pub fn key(cp: u32) void {
        deskKey(cp);
    }
    pub fn input(dir: u32) void {
        deskInput(dir);
    }
    pub fn setDiskApp(present: u32) void {
        deskSetDiskApp(present);
    }
    pub fn dirPtr() [*]u8 {
        return @ptrFromInt(deskDirPtr());
    }
    pub fn setFileCount(n: u32) void {
        deskSetFileCount(n);
    }
    /// Fills `out` with the program a .launch refers to; empty if the disk has none.
    pub fn launchName(out: []u8) []const u8 {
        const n = deskLaunchName(@intCast(@intFromPtr(out.ptr)), @intCast(out.len));
        return out[0..n];
    }
};

/// GEM's palette into a plane. See romInstallPalettePlane.
pub fn installPalette(plane: u32) void {
    romInstallPalettePlane(plane);
}

// --------------------------------------------------------------------------
// Handle wrappers. Sugar ONLY — every one is a direct call to an entry point
// above, so app code keeps reading like `g.rect(r, WHITE)` while nothing but
// numbers crosses. When these become extern at step 2.2, this file is the only
// thing that changes.
// --------------------------------------------------------------------------
pub const Gui = struct {
    h: u32 = 0,

    /// Open a context over a PLANE. There is deliberately no pointer form: one
    /// shape, callable from any language. The plane must already be configured
    /// (resolution/buffer) — the ROM reads its stride from the registers.
    pub fn openPlane(plane: u32, w: i32, ht: i32) Gui {
        return .{ .h = guiOpenPlane(plane, w, ht) };
    }
    pub fn close(self: Gui) void {
        guiClose(self.h);
    }
    pub fn resize(self: Gui, w: i32, ht: i32) void {
        guiResize(self.h, w, ht);
    }
    pub fn setPointer(self: Gui, x: i32, y: i32, buttons: u32) void {
        guiSetPointer(self.h, x, y, buttons);
    }
    pub fn beginFrame(self: Gui) void {
        guiBeginFrame(self.h);
    }
    pub fn endFrame(self: Gui) void {
        guiEndFrame(self.h);
    }
    pub fn edge(self: Gui) bool {
        return guiEdge(self.h) != 0;
    }
    pub fn hit(self: Gui, r: Rect) bool {
        return guiHit(self.h, r.x, r.y, r.w, r.h) != 0;
    }
    pub fn rect(self: Gui, r: Rect, color: u8) void {
        guiRect(self.h, r.x, r.y, r.w, r.h, color);
    }
    pub fn frame(self: Gui, r: Rect, color: u8) void {
        guiFrame(self.h, r.x, r.y, r.w, r.h, color);
    }
    pub fn plot(self: Gui, x: i16, y: i16, color: u8) void {
        guiPlot(self.h, x, y, color);
    }
    pub fn text(self: Gui, s: []const u8, x: i16, y: i16, ink: u8, paper: u8) void {
        guiText(self.h, @intCast(@intFromPtr(s.ptr)), @intCast(s.len), x, y, ink, paper);
    }
    /// A GEM panel: white face inside `inset` nested black frames.
    pub fn box(self: Gui, r: Rect, inset: u32) void {
        guiBox(self.h, r.x, r.y, r.w, r.h, inset);
    }
    /// A GEM button. Returns true on the frame the press STARTS, so the caller
    /// needs no edge/hit bookkeeping of its own.
    pub fn button(self: Gui, r: Rect, label: []const u8, active: bool, border: u32) bool {
        return guiButton(self.h, r.x, r.y, r.w, r.h,
            @intCast(@intFromPtr(label.ptr)), @intCast(label.len),
            @intFromBool(active), border) != 0;
    }
    /// Text aligned within a box of width `w`.
    pub fn textAlign(self: Gui, s: []const u8, x: i16, y: i16, w: i16, mode: Align, ink: u8, paper: u8) void {
        guiTextAlign(self.h, x, y, w, @intCast(@intFromPtr(s.ptr)), @intCast(s.len),
            @intFromEnum(mode), ink, paper);
    }

    /// A raw span — see guiFill. Use `rect` for anything with a Rect already.
    pub fn fill(self: Gui, x: i16, y: i16, w: i16, h: i16, color: u8) void {
        guiFill(self.h, x, y, w, h, color);
    }
};

pub const Dialog = struct {
    h: u32 = 0,

    pub fn open() Dialog {
        return .{ .h = dialogOpen() };
    }
    pub fn close(self: Dialog) void {
        dialogClose(self.h);
    }
    pub fn alert(self: Dialog, title: []const u8, msg: []const u8) void {
        dialogAlert(self.h, @intCast(@intFromPtr(title.ptr)), @intCast(title.len),
                    @intCast(@intFromPtr(msg.ptr)), @intCast(msg.len));
    }
    pub fn active(self: Dialog) bool {
        return dialogActive(self.h) != 0;
    }
    pub fn process(self: Dialog, g: Gui) Result {
        return @enumFromInt(dialogProcess(self.h, g.h));
    }
};

pub const FileSel = struct {
    h: u32 = 0,

    pub fn open() FileSel {
        return .{ .h = fileSelOpen() };
    }
    pub fn close(self: FileSel) void {
        fileSelClose(self.h);
    }
    pub fn show(self: FileSel, mask: []const u8) void {
        fileSelShow(self.h, @intCast(@intFromPtr(mask.ptr)), @intCast(mask.len));
    }
    pub fn add(self: FileSel, name: []const u8) void {
        fileSelAdd(self.h, @intCast(@intFromPtr(name.ptr)), @intCast(name.len));
    }
    pub fn active(self: FileSel) bool {
        return fileSelActive(self.h) != 0;
    }
    pub fn key(self: FileSel, cp: u32) void {
        fileSelKey(self.h, cp);
    }
    pub fn process(self: FileSel, g: Gui) Result {
        return @enumFromInt(fileSelProcess(self.h, g.h));
    }
    /// Fills `out` with the chosen name and returns the used slice.
    pub fn chosen(self: FileSel, out: []u8) []const u8 {
        const n = fileSelChosen(self.h, @intCast(@intFromPtr(out.ptr)), @intCast(out.len));
        return out[0..n];
    }
};
