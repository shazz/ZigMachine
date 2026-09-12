// --------------------------------------------------------------------------
// rom.wasm — the ROM chip's entry point (Phase 2, step 2.2).
//
// GEM now lives in its own wasm module with its own RAM window
// ([ROM_RAM_BASE, ROM_RAM_TOP) — see machine/sdk/memmap.zig), linked against the
// sealed HW ABI exactly like a cart is. It exports the flat, app-facing ABI whose
// header is rom/sdk/rom.zig; the host wires an app's `env` to these exports.
//
// This is where the toolkit's STATE lives: the handle tables below are the ROM's
// statics, so they sit in the ROM's window and an app stops paying for them. An
// app holds a u32 and nothing else.
//
// Step 2.1 proved the ABI in-process before this file existed. If you are
// changing an entry point, change rom/sdk/rom.zig's `extern` declaration in the
// same commit — they are two halves of one wire and nothing checks them against
// each other but the linker.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const hw = @import("hardware");
const gem = @import("rom").gem;
const gui = @import("rom").gui;

const Rect = gui.Rect;

pub const Result = enum(u32) { none = 0, ok = 1, cancel = 2 };

// --------------------------------------------------------------------------
// ROM-side state. These are rom.wasm's statics, so they live in the ROM's RAM
// window and an app pays nothing for the toolkit's state — the point of the
// whole exercise.
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

/// Reclaim everything the previous program held. The HOST calls this when it
/// swaps a cart in, before boot().
///
/// A program cannot release its own handles when it is replaced: the host tears
/// the cart down and instantiates the next one, so the app is simply gone and its
/// close() calls never happen. The ROM would keep those slots marked used, and
/// after MAX_GUI launches every open() would return 0 and every call on it would
/// silently do nothing — an app that draws perfectly and whose dialogs never
/// appear. That is precisely what step 2.3b's real launches turned up.
///
/// This is what a real OS does when a program terminates: the resources go back.
/// It deliberately does NOT touch the desktop, which outlives any one program and
/// re-inits itself when the shell restarts.
export fn romReset() void {
    gui_used = [_]bool{false} ** MAX_GUI;
    dialog_used = [_]bool{false} ** MAX_DIALOG;
    fsel_used = [_]bool{false} ** MAX_FSEL;
    // The desktop holds the SHELL CART's ZigOS and LogicalFB addresses, which are
    // in the cart window. Once the host swaps another program into that window
    // those point at the new program's memory, so a desk* call would make the ROM
    // draw through garbage. Invalidate it: the shell re-inits on every boot.
    desk_ready = false;
}

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

// --------------------------------------------------------------------------
// Opening a context WITHOUT a ZigOS (step 2.3c — the polyglot half of the split).
//
// guiOpen() below takes the addresses of the caller's ZigOS and LogicalFB, which
// quietly means "the caller must be a Zig program that links ZigOS". A C or Rust
// app has neither: it writes palette indices straight into the video region. So
// the ABI was flat in its argument TYPES and not in their MEANINGS, and the claim
// that any language can call GEM was false in a way no amount of u32 could fix.
//
// The fix is to name a PLANE instead of a pointer. The ROM links the sealed HW
// ABI, so it can read that plane's framebuffer base and stride out of the video
// registers — which is the authoritative answer anyway, since ZigOS's VRAM
// allocator moves FB_BASE around. The ROM then lends its OWN ZigOS (fonts only;
// see initTextOnly) and its own LogicalFB wrapper.
//
// One raw context at a time: an app has one screen, and a second caller would
// silently repoint the first one's framebuffer.
var raw_os: zg.ZigOS = .{};
var raw_fb: zg.LogicalFB = .{};

// Point raw_fb at a plane by reading the SEALED registers — FB_BASE is where the
// VRAM allocator actually put it, which is the only correct answer, and it works
// the same whether the plane was set up by ZigOS or by a C program.
fn bindRawFb(plane: u32, screen_h: i32) bool {
    if (plane >= hw.NB_PLANES) return false;
    const base: usize = @intCast(hw.hwVideoBase());
    const regs: [*]u8 = @ptrFromInt(base);
    const fb_off = std.mem.readInt(u32, regs[hw.REG_FB_BASE + plane * 4 ..][0..4], .little);
    const stride = std.mem.readInt(u16, regs[hw.REG_FB_STRIDE + plane * 2 ..][0..2], .little);
    raw_os.initTextOnly();
    raw_fb = .{
        .fb = @ptrFromInt(base + fb_off),
        .palette = @ptrFromInt(base + hw.OFF_PAL + @as(usize, plane) * hw.PAL_BYTES),
        .stride = stride,
        .fb_w = stride,
        .fb_h = @intCast(screen_h),
        .id = @intCast(plane),
        .zigos = &raw_os,
    };
    return true;
}

/// Open a drawing context over PLANE `plane`, for a caller with no ZigOS of its
/// own. Returns a handle exactly like guiOpen, or 0 if none is free.
export fn guiOpenPlane(plane: u32, screen_w: i32, screen_h: i32) u32 {
    if (!bindRawFb(plane, screen_h)) return 0;
    return guiOpen(@intCast(@intFromPtr(&raw_os)), @intCast(@intFromPtr(&raw_fb)), screen_w, screen_h);
}

/// Install GEM's palette into a PLANE — the companion to guiOpenPlane, and for
/// the same reason: romInstallPalette wants a *LogicalFB, which a non-Zig app
/// cannot produce. Without this a C app's GEM widgets come out in whatever colours
/// its own palette happens to have at indices 0 and 1 (a plasma rainbow renders
/// the panel solid red — correct pixels, unreadable result).
export fn romInstallPalettePlane(plane: u32) void {
    if (!bindRawFb(plane, @intCast(raw_fb.fb_h))) return;
    gui.installPalette(&raw_fb);
}

/// Open a drawing context over a framebuffer. `os_ptr`/`fb_ptr` are addresses in
/// the ONE shared linear memory — which is why they can be passed at all. The
/// ROM's code is a different binary from the app's, but the MEMORY is common, so
/// the ROM's own ZigOS reads the app's ZigOS/framebuffer structs directly, no
/// copy and no serialisation. Same compiler, same source, same layout.
/// Returns 0 if no context is free. Note there is no blitter argument: the ROM
/// brings its own, so an app no longer has to own one for the toolkit's benefit.
export fn guiOpen(os_ptr: u32, fb_ptr: u32, screen_w: i32, screen_h: i32) u32 {
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
export fn guiClose(h: u32) void {
    if (h != 0 and h <= MAX_GUI) gui_used[h - 1] = false;
}
export fn guiResize(h: u32, screen_w: i32, screen_h: i32) void {
    const g = guiAt(h) orelse return;
    g.screen_w = @intCast(screen_w);
    g.screen_h = @intCast(screen_h);
}
export fn guiSetPointer(h: u32, x: i32, y: i32, buttons: u32) void {
    (guiAt(h) orelse return).setPointer(x, y, buttons);
}
export fn guiBeginFrame(h: u32) void {
    (guiAt(h) orelse return).beginFrame();
}
export fn guiEndFrame(h: u32) void {
    (guiAt(h) orelse return).endFrame();
}
/// Did a press START this frame? (`Gui.edge` — a field an app used to read.)
export fn guiEdge(h: u32) u32 {
    return if ((guiAt(h) orelse return 0).edge) 1 else 0;
}
export fn guiHit(h: u32, x: i32, y: i32, w: i32, hh: i32) u32 {
    const g = guiAt(h) orelse return 0;
    return if (g.hit(rectOf(x, y, w, hh))) 1 else 0;
}
export fn guiRect(h: u32, x: i32, y: i32, w: i32, hh: i32, color: u32) void {
    (guiAt(h) orelse return).rect(rectOf(x, y, w, hh), @intCast(color));
}
export fn guiFrame(h: u32, x: i32, y: i32, w: i32, hh: i32, color: u32) void {
    (guiAt(h) orelse return).frame(rectOf(x, y, w, hh), @intCast(color));
}
export fn guiPlot(h: u32, x: i32, y: i32, color: u32) void {
    (guiAt(h) orelse return).plot(@intCast(x), @intCast(y), @intCast(color));
}
export fn guiText(h: u32, ptr: u32, len: u32, x: i32, y: i32, ink: u32, paper: u32) void {
    const g = guiAt(h) orelse return;
    g.text(slice(ptr, len), @intCast(x), @intCast(y), @intCast(ink), @intCast(paper));
}
/// A raw filled span. This exists because app code used to reach THROUGH the
/// context — `g.blit.fill(g.fb, ...)` — for spans the toolkit had no verb for
/// (ST Replay's waveform). Across a module boundary that is impossible, so the
/// verb is here instead. It is `guiRect` without the Rect, kept separate so the
/// intent (a raw span, not a widget) stays legible at the call site.
export fn guiFill(h: u32, x: i32, y: i32, w: i32, hh: i32, color: u32) void {
    const g = guiAt(h) orelse return;
    g.blit.fill(g.fb, @intCast(x), @intCast(y), @intCast(w), @intCast(hh), @intCast(color));
}
/// Install the ROM's shared palette into a framebuffer (address, as above).
export fn romInstallPalette(fb_ptr: u32) void {
    gui.installPalette(@ptrFromInt(fb_ptr));
}

export fn dialogOpen() u32 {
    for (&dialog_used, 0..) |*used, i| {
        if (used.*) continue;
        dialogs[i] = .{};
        used.* = true;
        return @intCast(i + 1);
    }
    return 0;
}
export fn dialogClose(h: u32) void {
    if (h != 0 and h <= MAX_DIALOG) dialog_used[h - 1] = false;
}
export fn dialogAlert(h: u32, title: u32, title_len: u32, msg: u32, msg_len: u32) void {
    (dialogAt(h) orelse return).alert(slice(title, title_len), slice(msg, msg_len));
}
export fn dialogActive(h: u32) u32 {
    return if ((dialogAt(h) orelse return 0).active) 1 else 0;
}
export fn dialogProcess(h: u32, gui_h: u32) u32 {
    const d = dialogAt(h) orelse return @intFromEnum(Result.none);
    const g = guiAt(gui_h) orelse return @intFromEnum(Result.none);
    return switch (d.process(g)) {
        .ok => @intFromEnum(Result.ok),
        .cancel => @intFromEnum(Result.cancel),
        else => @intFromEnum(Result.none),
    };
}

export fn fileSelOpen() u32 {
    for (&fsel_used, 0..) |*used, i| {
        if (used.*) continue;
        fsels[i] = .{};
        used.* = true;
        return @intCast(i + 1);
    }
    return 0;
}
export fn fileSelClose(h: u32) void {
    if (h != 0 and h <= MAX_FSEL) fsel_used[h - 1] = false;
}
export fn fileSelShow(h: u32, mask: u32, mask_len: u32) void {
    (fselAt(h) orelse return).open(slice(mask, mask_len));
}
export fn fileSelAdd(h: u32, name: u32, name_len: u32) void {
    (fselAt(h) orelse return).add(slice(name, name_len));
}
export fn fileSelActive(h: u32) u32 {
    return if ((fselAt(h) orelse return 0).active) 1 else 0;
}
export fn fileSelKey(h: u32, cp: u32) void {
    (fselAt(h) orelse return).key(cp);
}
export fn fileSelProcess(h: u32, gui_h: u32) u32 {
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
export fn fileSelChosen(h: u32, out: u32, out_cap: u32) u32 {
    const f = fselAt(h) orelse return 0;
    const name = f.chosen();
    const n = @min(name.len, out_cap);
    if (n == 0 or out == 0) return 0;
    const dst: [*]u8 = @ptrFromInt(out);
    @memcpy(dst[0..n], name[0..n]);
    return @intCast(n);
}

// --------------------------------------------------------------------------
// The DESKTOP (Phase 2, step 2.3). GEM's top level now lives here rather than in
// a cart, so the toolkit exists exactly once: the shell cart is a few dozen lines
// that forwards frames and input, and every byte of desktop state — icons, window
// geometry, the mounted disk's FAT — sits in the ROM's window.
//
// A singleton, not a handle: there is one desktop, the machine has one screen,
// and inventing a table for a thing that can only ever have one member would be
// ceremony. `desk_ready` is the guard, so a call before deskInit() does nothing
// instead of touching undefined memory.
// --------------------------------------------------------------------------
var desk: gem.Desktop = .{};
var desk_blit: zg.Blitter = .{};
var desk_ready: bool = false;

/// Bring up the desktop over a framebuffer (addresses, as with guiOpen).
export fn deskInit(os_ptr: u32, fb_ptr: u32) void {
    desk = .{};
    desk_blit = .{};
    desk_blit.init();
    desk.init(@ptrFromInt(os_ptr), @ptrFromInt(fb_ptr), &desk_blit);
    desk_ready = true;
}
/// The desktop's screen changed size (the Options menu switches LOW/MEDIUM).
export fn deskSetScreen(w: i32, h: i32) void {
    if (!desk_ready) return;
    desk.g.screen_w = @intCast(w);
    desk.g.screen_h = @intCast(h);
    desk.clampIcons(); // keep icons on-screen at the new width
}
export fn deskBeginFrame() void {
    if (desk_ready) desk.beginFrame();
}
export fn deskEndFrame() void {
    if (desk_ready) desk.endFrame();
}
/// Draw a frame and report what the user asked for — the Action enum, flat.
export fn deskRender() u32 {
    if (!desk_ready) return 0;
    return switch (desk.render()) {
        .none => 0,
        .launch => 1,
        .res_low => 2,
        .res_medium => 3,
    };
}
export fn deskSetPointer(x: i32, y: i32, buttons: u32) void {
    if (desk_ready) desk.setPointer(x, y, buttons);
}
/// The host's native double-click pulse.
export fn deskRequestOpenAt(x: i32, y: i32) void {
    if (desk_ready) desk.requestOpenAt(x, y);
}
export fn deskKey(cp: u32) void {
    if (desk_ready) desk.key(cp);
}
export fn deskInput(dir: u32) void {
    if (desk_ready) desk.input(dir);
}
export fn deskSetDiskApp(present: u32) void {
    if (desk_ready) desk.disk_app = present != 0;
}
/// Where the HOST packs the mounted disk's FAT. It is the ROM's buffer now, so
/// the address is in the ROM's window — the host writes there directly, which is
/// the same shared memory it always wrote to.
export fn deskDirPtr() u32 {
    if (!desk_ready) return 0;
    return @intCast(@intFromPtr(&desk.disk_dir));
}
/// The FAT buffer's size in BYTES, so the host can size its write.
export fn deskDirCap() u32 {
    return @intCast(desk.disk_dir.len);
}
/// Its capacity in RECORDS, and the record size — so the host derives its cap and
/// its struct stride from the ROM instead of mirroring both as literals.
export fn deskDirMaxFiles() u32 {
    return @intCast(gem.MAX_FILES);
}
export fn deskDirEntryBytes() u32 {
    return @intCast(gem.FILE_ENT);
}
/// The program a `.launch` action refers to, copied into the caller's buffer;
/// returns its length, 0 if the disk holds no program. A name, not an index:
/// the HOST is the one that has to find it in the mounted disk's FAT and
/// instantiate it, and it reads the FAT by name.
export fn deskLaunchName(out: u32, out_cap: u32) u32 {
    if (!desk_ready or out == 0) return 0;
    const name = desk.launchName();
    const n = @min(name.len, out_cap);
    if (n == 0) return 0;
    const dst: [*]u8 = @ptrFromInt(out);
    @memcpy(dst[0..n], name[0..n]);
    return @intCast(n);
}
export fn deskSetFileCount(n: u32) void {
    // Clamp by the RECORD SIZE, not by 17. disk_dir is MAX_FILES * FILE_ENT bytes
    // (12 * 25 = 300); dividing by 17 admitted 17 records into a 12-record buffer,
    // and diskName() slices it unchecked in ReleaseSmall. Only ever masked because
    // the host happens to cap at 12 with a literal of its own — which is exactly
    // why the cap is published as deskDirCap() for the host to derive.
    if (desk_ready) desk.n_disk = @intCast(@min(n, gem.MAX_FILES));
}

inline fn rectOf(x: i32, y: i32, w: i32, h: i32) Rect {
    return .{ .x = @intCast(x), .y = @intCast(y), .w = @intCast(w), .h = @intCast(h) };
}
