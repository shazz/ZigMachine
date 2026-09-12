// --------------------------------------------------------------------------
// The ROM's app-facing ABI — the header an APP gets of the system software.
//
// Phase 2, step 2.1 (docs/PHASE2_ROM_CHIP.md): change the CALL SHAPE first, the
// module boundary second. Every entry point below is already flat — only u32/i32
// cross it, handles instead of pointers, (ptr,len) for strings — but the bodies
// still call rom/gem in-process, because GEM is still statically linked. At step
// 2.2 the bodies are deleted, each `fn` becomes `pub extern fn`, and the host
// resolves them against rom.wasm. App code does not change again.
//
// That is the whole point of doing it in this order: if the ABI is wrong, it is
// cheap to find out now, while a mistake is a compile error rather than a
// LinkError against a binary that no longer exists in this build.
//
// WHY FLAT: a wasm module boundary passes only numbers. A `*Gui` cannot cross it,
// and neither can a slice, an error, or an enum with a payload. The handle
// wrappers at the bottom hide that from app code — `g.rect(r, WHITE)` still reads
// like a method call — but underneath it is guiRect(h, x, y, w, h, c).
//
// WHY THE ROM OWNS THE STATE: an app used to declare `g: gui.Gui` as its own
// field, so the toolkit's state lived in the APP's memory and the app could reach
// through it (`g.blit.fill(g.fb, ...)` — st_replay_draw.zig did exactly that).
// Across a module boundary that reach-through cannot work: the ROM's code and the
// app's code are different binaries. So the ROM allocates, the app holds a u32,
// and anything the app used to do by reaching through is an entry point of its
// own (see fill()).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const gem = @import("rom").gem;
const gui = @import("rom").gui;

// --- values, not calls: constants and plain data are part of the header ---
pub const Rect = gui.Rect;
pub const BLACK = gui.BLACK;
pub const WHITE = gui.WHITE;

/// What a modal returned this frame. Flat on the wire (see dialogProcess).
pub const Result = enum(u32) { none = 0, ok = 1, cancel = 2 };

// --------------------------------------------------------------------------
// ROM-side state. Today these live in the rom module's statics; at step 2.2 the
// same declarations land in rom.wasm and therefore in the ROM's own RAM window,
// which is the point — an app stops paying for the toolkit's state.
//
// Handles are index+1 so that 0 is always invalid: a zeroed or garbage handle
// fails closed instead of aliasing slot 0. Every entry point below tolerates a
// bad handle by doing nothing, because a module boundary is exactly where a
// caller's bug must not become the ROM's crash.
// --------------------------------------------------------------------------
// Deliberately TINY. An app is re-init'd every time it is launched, so a handle
// leaked on re-init exhausts the table within a couple of launches and every call
// starts silently doing nothing — which is precisely the bug this caught during
// step 2.1 (ST Replay re-opened its Dialog and FileSel on every launch without
// closing them). Small tables make that failure arrive in seconds instead of
// hiding until someone opens their fifth window. Raise them for a REAL need, and
// only after checking the caller closes what it opens.
const MAX_GUI = 2; // one app + one desktop
const MAX_DIALOG = 2;
const MAX_FSEL = 2;

var guis: [MAX_GUI]gui.Gui = undefined;
var gui_used: [MAX_GUI]bool = [_]bool{false} ** MAX_GUI;
var blits: [MAX_GUI]zg.Blitter = undefined; // the ROM's OWN blitter, one per context
var dialogs: [MAX_DIALOG]gui.Dialog = undefined;
var dialog_used: [MAX_DIALOG]bool = [_]bool{false} ** MAX_DIALOG;
var fsels: [MAX_FSEL]gem.FileSel = undefined;
var fsel_used: [MAX_FSEL]bool = [_]bool{false} ** MAX_FSEL;

fn guiAt(h: u32) ?*gui.Gui {
    if (h == 0 or h > MAX_GUI or !gui_used[h - 1]) return null;
    return &guis[h - 1];
}
fn dialogAt(h: u32) ?*gui.Dialog {
    if (h == 0 or h > MAX_DIALOG or !dialog_used[h - 1]) return null;
    return &dialogs[h - 1];
}
fn fselAt(h: u32) ?*gem.FileSel {
    if (h == 0 or h > MAX_FSEL or !fsel_used[h - 1]) return null;
    return &fsels[h - 1];
}
// A slice from a caller's (ptr, len). Only ever read, never retained: the caller
// owns that memory and it is the app's window, not ours.
fn slice(ptr: u32, len: u32) []const u8 {
    if (ptr == 0 or len == 0) return &.{};
    const p: [*]const u8 = @ptrFromInt(ptr);
    return p[0..len];
}

// --------------------------------------------------------------------------
// Entry points. Signatures are the ABI: only u32/i32 cross.
// --------------------------------------------------------------------------

/// Open a drawing context over a framebuffer. `os_ptr`/`fb_ptr` are addresses in
/// the ONE shared linear memory, so the ROM reads them directly with no copy.
/// Returns 0 if no context is free. Note there is no blitter argument: the ROM
/// brings its own, so an app no longer has to own one for the toolkit's benefit.
pub fn guiOpen(os_ptr: u32, fb_ptr: u32, screen_w: i32, screen_h: i32) u32 {
    for (&gui_used, 0..) |*used, i| {
        if (used.*) continue;
        blits[i] = .{};
        blits[i].init();
        guis[i] = .{
            .os = @ptrFromInt(os_ptr),
            .fb = @ptrFromInt(fb_ptr),
            .blit = &blits[i],
            .screen_w = @intCast(screen_w),
            .screen_h = @intCast(screen_h),
        };
        used.* = true;
        return @intCast(i + 1);
    }
    return 0;
}
pub fn guiClose(h: u32) void {
    if (h != 0 and h <= MAX_GUI) gui_used[h - 1] = false;
}
pub fn guiResize(h: u32, screen_w: i32, screen_h: i32) void {
    const g = guiAt(h) orelse return;
    g.screen_w = @intCast(screen_w);
    g.screen_h = @intCast(screen_h);
}
pub fn guiSetPointer(h: u32, x: i32, y: i32, buttons: u32) void {
    (guiAt(h) orelse return).setPointer(x, y, buttons);
}
pub fn guiBeginFrame(h: u32) void {
    (guiAt(h) orelse return).beginFrame();
}
pub fn guiEndFrame(h: u32) void {
    (guiAt(h) orelse return).endFrame();
}
/// Did a press START this frame? (`Gui.edge` — a field an app used to read.)
pub fn guiEdge(h: u32) u32 {
    return if ((guiAt(h) orelse return 0).edge) 1 else 0;
}
pub fn guiHit(h: u32, x: i32, y: i32, w: i32, hh: i32) u32 {
    const g = guiAt(h) orelse return 0;
    return if (g.hit(rectOf(x, y, w, hh))) 1 else 0;
}
pub fn guiRect(h: u32, x: i32, y: i32, w: i32, hh: i32, color: u32) void {
    (guiAt(h) orelse return).rect(rectOf(x, y, w, hh), @intCast(color));
}
pub fn guiFrame(h: u32, x: i32, y: i32, w: i32, hh: i32, color: u32) void {
    (guiAt(h) orelse return).frame(rectOf(x, y, w, hh), @intCast(color));
}
pub fn guiPlot(h: u32, x: i32, y: i32, color: u32) void {
    (guiAt(h) orelse return).plot(@intCast(x), @intCast(y), @intCast(color));
}
pub fn guiText(h: u32, ptr: u32, len: u32, x: i32, y: i32, ink: u32, paper: u32) void {
    const g = guiAt(h) orelse return;
    g.text(slice(ptr, len), @intCast(x), @intCast(y), @intCast(ink), @intCast(paper));
}
/// A raw filled span. This exists because app code used to reach THROUGH the
/// context — `g.blit.fill(g.fb, ...)` — for spans the toolkit had no verb for
/// (ST Replay's waveform). Across a module boundary that is impossible, so the
/// verb is here instead. It is `guiRect` without the Rect, kept separate so the
/// intent (a raw span, not a widget) stays legible at the call site.
pub fn guiFill(h: u32, x: i32, y: i32, w: i32, hh: i32, color: u32) void {
    const g = guiAt(h) orelse return;
    g.blit.fill(g.fb, @intCast(x), @intCast(y), @intCast(w), @intCast(hh), @intCast(color));
}
/// Install the ROM's shared palette into a framebuffer (address, as above).
pub fn installPalette(fb_ptr: u32) void {
    gui.installPalette(@ptrFromInt(fb_ptr));
}

pub fn dialogOpen() u32 {
    for (&dialog_used, 0..) |*used, i| {
        if (used.*) continue;
        dialogs[i] = .{};
        used.* = true;
        return @intCast(i + 1);
    }
    return 0;
}
pub fn dialogClose(h: u32) void {
    if (h != 0 and h <= MAX_DIALOG) dialog_used[h - 1] = false;
}
pub fn dialogAlert(h: u32, title: u32, title_len: u32, msg: u32, msg_len: u32) void {
    (dialogAt(h) orelse return).alert(slice(title, title_len), slice(msg, msg_len));
}
pub fn dialogActive(h: u32) u32 {
    return if ((dialogAt(h) orelse return 0).active) 1 else 0;
}
pub fn dialogProcess(h: u32, gui_h: u32) u32 {
    const d = dialogAt(h) orelse return @intFromEnum(Result.none);
    const g = guiAt(gui_h) orelse return @intFromEnum(Result.none);
    return switch (d.process(g)) {
        .ok => @intFromEnum(Result.ok),
        .cancel => @intFromEnum(Result.cancel),
        else => @intFromEnum(Result.none),
    };
}

pub fn fileSelOpen() u32 {
    for (&fsel_used, 0..) |*used, i| {
        if (used.*) continue;
        fsels[i] = .{};
        used.* = true;
        return @intCast(i + 1);
    }
    return 0;
}
pub fn fileSelClose(h: u32) void {
    if (h != 0 and h <= MAX_FSEL) fsel_used[h - 1] = false;
}
pub fn fileSelShow(h: u32, mask: u32, mask_len: u32) void {
    (fselAt(h) orelse return).open(slice(mask, mask_len));
}
pub fn fileSelAdd(h: u32, name: u32, name_len: u32) void {
    (fselAt(h) orelse return).add(slice(name, name_len));
}
pub fn fileSelActive(h: u32) u32 {
    return if ((fselAt(h) orelse return 0).active) 1 else 0;
}
pub fn fileSelKey(h: u32, cp: u32) void {
    (fselAt(h) orelse return).key(cp);
}
pub fn fileSelProcess(h: u32, gui_h: u32) u32 {
    const f = fselAt(h) orelse return @intFromEnum(Result.none);
    const g = guiAt(gui_h) orelse return @intFromEnum(Result.none);
    return switch (f.process(g)) {
        .ok => @intFromEnum(Result.ok),
        .cancel => @intFromEnum(Result.cancel),
        else => @intFromEnum(Result.none),
    };
}
/// Copy the chosen name into the caller's buffer; returns its length. A slice
/// cannot cross a module boundary, and a pointer INTO the ROM's window would be
/// a lifetime the app cannot reason about — so the app provides the storage.
pub fn fileSelChosen(h: u32, out: u32, out_cap: u32) u32 {
    const f = fselAt(h) orelse return 0;
    const name = f.chosen();
    const n = @min(name.len, out_cap);
    if (n == 0 or out == 0) return 0;
    const dst: [*]u8 = @ptrFromInt(out);
    @memcpy(dst[0..n], name[0..n]);
    return @intCast(n);
}

inline fn rectOf(x: i32, y: i32, w: i32, h: i32) Rect {
    return .{ .x = @intCast(x), .y = @intCast(y), .w = @intCast(w), .h = @intCast(h) };
}

// --------------------------------------------------------------------------
// Handle wrappers. Sugar ONLY — every one is a direct call to an entry point
// above, so app code keeps reading like `g.rect(r, WHITE)` while nothing but
// numbers crosses. When these become extern at step 2.2, this file is the only
// thing that changes.
// --------------------------------------------------------------------------
pub const Gui = struct {
    h: u32 = 0,

    pub fn open(os: *zg.ZigOS, fb: *zg.LogicalFB, w: i32, ht: i32) Gui {
        return .{ .h = guiOpen(@intCast(@intFromPtr(os)), @intCast(@intFromPtr(fb)), w, ht) };
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
