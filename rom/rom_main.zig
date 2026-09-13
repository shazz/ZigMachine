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
// romDepack: the machine unpacks a program it loads from a disk.
//
// A disk stores its cart ZX0-packed (tools/mkdisks.sh). The host is only the
// drive: it copies the packed image into free RAM and calls this, much as a
// Pack-Ice'd program on an ST depacked itself before running. `src`/`dst` are
// absolute addresses in shared memory. The result may only land in the CART
// window, the one place a loaded program belongs, so a bad `dst` can never reach
// the video region or this ROM's own statics.
//
// Returns the depacked length, or 0 (having written nothing outside `dst`) when a
// pointer is null, a range runs past memory, `dst` is not wholly inside the cart
// window, the two ranges overlap, or the image is unreadable, corrupt or bigger
// than `dst_cap`.
// --------------------------------------------------------------------------
const depackers = @import("depackers");

export fn romDepack(src: u32, src_len: u32, dst: u32, dst_cap: u32) u32 {
    const mem_len: u64 = @as(u64, @wasmMemorySize(0)) * 65536;
    const s0: u64 = src;
    const s1: u64 = s0 + src_len;
    const d0: u64 = dst;
    const d1: u64 = d0 + dst_cap;
    if (src == 0 or dst == 0 or src_len == 0 or dst_cap == 0) return 0;
    if (s1 > mem_len or d1 > mem_len) return 0;
    if (d0 < hw.CART_RAM_BASE or d1 > hw.CART_RAM_TOP) return 0;
    if (s0 < d1 and d0 < s1) return 0; // overlapping: the stream would overwrite itself
    const in = @as([*]const u8, @ptrFromInt(src))[0..src_len];
    const out = @as([*]u8, @ptrFromInt(dst))[0..dst_cap];
    return depackers.zx0.depack(in, out) orelse 0;
}

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
// --------------------------------------------------------------------------
// Narrowing a CALLER's integer. `-Drelease=true` is ReleaseSmall, where @intCast
// is UNCHECKED — so a C app passing color = 256 or x = 70000 was undefined
// behaviour inside the ROM, not a clipped pixel. The handle tables already
// promise that a caller's bug must not become the ROM's crash; these make that
// promise true for the numbers as well. Saturate rather than reject: a widget
// drawn at a clamped edge is debuggable, a silently skipped one is not.
// --------------------------------------------------------------------------
inline fn i16Of(v: i32) i16 {
    return @intCast(@max(@as(i32, -32768), @min(@as(i32, 32767), v)));
}
inline fn u8Of(v: u32) u8 {
    return @intCast(@min(v, 255));
}
// A SIZE from a caller: negative means nothing, so clamp to zero rather than
// wrapping it into a 65535-wide fill.
inline fn u16Of(v: i32) u16 {
    return @intCast(@max(@as(i32, 0), @min(@as(i32, 65535), v)));
}

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
// The ROM lends its own ZigOS (fonts only — initTextOnly touches no hardware) and
// its own LogicalFB per context. One LogicalFB PER SLOT, not one shared: a second
// caller used to silently repoint the first one's framebuffer.
var raw_os: zg.ZigOS = .{};
var raw_fbs: [MAX_GUI]zg.LogicalFB = undefined;

// Point `fb` at a plane by reading the SEALED registers. FB_BASE is where the VRAM
// allocator actually put it and FB_STRIDE is what the machine reads per row — the
// only correct answers, and they change under you: setResLow/setResMedium rewrite
// the stride register on the same buffer. So anything holding a bound context has
// to re-bind when the resolution changes (see deskSetScreen).
fn bindFb(fb: *zg.LogicalFB, plane: u32, screen_h: i32) bool {
    if (plane >= hw.NB_PLANES) return false;
    const base: usize = @intCast(hw.hwVideoBase());
    const regs: [*]u8 = @ptrFromInt(base);
    const fb_off = std.mem.readInt(u32, regs[hw.REG_FB_BASE + plane * 4 ..][0..4], .little);
    const stride = std.mem.readInt(u16, regs[hw.REG_FB_STRIDE + plane * 2 ..][0..2], .little);
    raw_os.initTextOnly();
    fb.* = .{
        .fb = @ptrFromInt(base + fb_off),
        .palette = @ptrFromInt(base + hw.OFF_PAL + @as(usize, plane) * hw.PAL_BYTES),
        .stride = stride,
        .fb_w = stride, // the clip bound Gui.plot uses; the register is the truth
        .fb_h = @intCast(@max(@as(i32, 1), @min(@as(i32, 4096), screen_h))),
        .id = @intCast(plane),
        .zigos = &raw_os,
    };
    return true;
}

/// Open a drawing context over PLANE `plane`. THE way to get a context: naming a
/// plane works from any language, where handing over a *ZigOS and a *LogicalFB
/// only worked from Zig. Returns a handle, or 0 if no context is free.
export fn guiOpenPlane(plane: u32, screen_w: i32, screen_h: i32) u32 {
    for (&gui_used, 0..) |*used, i| {
        if (used.*) continue;
        if (!bindFb(&raw_fbs[i], plane, screen_h)) return 0;
        blits[i] = .{};
        blits[i].init();
        guis[i] = .{
            .os = &raw_os,
            .fb = &raw_fbs[i],
            .blit = &blits[i],
            .screen_w = i16Of(screen_w),
            .screen_h = i16Of(screen_h),
        };
        used.* = true;
        return @intCast(i + 1);
    }
    return 0;
}

// --------------------------------------------------------------------------
// WIDGETS. Until now the ABI exposed only drawing primitives, so an app could
// draw but not USE the toolkit — and ST Replay reimplemented a panel box, text
// centring and hit-testing that already existed in here, six and five times over
// respectively. These are the ROM's own widgets, not new ones.
// --------------------------------------------------------------------------

/// A GEM panel: white face inside `inset` nested black frames. The ROM draws
/// this in six places at two different insets (dialog 3, filesel 1, info, prefs,
/// about) and ST Replay drew a seventh.
export fn guiBox(h: u32, x: i32, y: i32, w: i32, hh: i32, inset: u32) void {
    const g = guiAt(h) orelse return;
    const r = rectOf(x, y, w, hh);
    g.rect(r, gui.WHITE);
    var i: i16 = 0;
    const n: i16 = @intCast(@min(inset, 8));
    while (i < n) : (i += 1)
        g.frame(.{ .x = r.x + i, .y = r.y + i, .w = r.w - 2 * i, .h = r.h - 2 * i }, gui.BLACK);
}

/// A GEM button: inverse video while pressed or `active`, `border` nested frames
/// (GEM uses 1 for multi-choice, 2 for an exit button, 3 for the default). Returns
/// 1 on the frame the press STARTS — the caller does not need its own edge/hit
/// bookkeeping, which is the part an app cannot reimplement correctly by eye.
export fn guiButton(h: u32, x: i32, y: i32, w: i32, hh: i32, ptr: u32, len: u32, active: u32, border: u32) u32 {
    const g = guiAt(h) orelse return 0;
    const b = g.buttonThick(rectOf(x, y, w, hh), slice(ptr, len), active != 0, @intCast(@min(border, 8)));
    return if (b) 1 else 0;
}

/// Text aligned in a box of width `w`: 0 = left, 1 = centre, 2 = right. The
/// "x + (w - len*CELL)/2" expression appears five times inside the ROM alone.
export fn guiTextAlign(h: u32, x: i32, y: i32, w: i32, ptr: u32, len: u32, mode: u32, ink: u32, paper: u32) void {
    const g = guiAt(h) orelse return;
    const str = slice(ptr, len);
    const tw: i32 = @as(i32, @intCast(str.len)) * gui.CELL;
    const tx: i32 = switch (mode) {
        1 => x + @divTrunc(w - tw, 2),
        2 => x + w - tw,
        else => x,
    };
    g.text(str, i16Of(tx), i16Of(y), u8Of(ink), u8Of(paper));
}

/// Install GEM's palette into a PLANE — the companion to guiOpenPlane, and for
/// the same reason: romInstallPalette wants a *LogicalFB, which a non-Zig app
/// cannot produce. Without this a C app's GEM widgets come out in whatever colours
/// its own palette happens to have at indices 0 and 1 (a plasma rainbow renders
/// the panel solid red — correct pixels, unreadable result).
export fn romInstallPalettePlane(plane: u32) void {
    var tmp: zg.LogicalFB = undefined;
    if (!bindFb(&tmp, plane, memmapScreenH)) return;
    gui.installPalette(&tmp);
}
// installPalette only writes palette entries, so the height it is bound with is
// irrelevant; name it rather than pass a meaningless argument through the ABI.
const memmapScreenH: i32 = 200;

export fn guiClose(h: u32) void {
    if (h != 0 and h <= MAX_GUI) gui_used[h - 1] = false;
}
export fn guiResize(h: u32, screen_w: i32, screen_h: i32) void {
    const g = guiAt(h) orelse return;
    g.screen_w = i16Of(screen_w);
    g.screen_h = i16Of(screen_h);
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
    (guiAt(h) orelse return).rect(rectOf(x, y, w, hh), u8Of(color));
}
export fn guiFrame(h: u32, x: i32, y: i32, w: i32, hh: i32, color: u32) void {
    (guiAt(h) orelse return).frame(rectOf(x, y, w, hh), u8Of(color));
}
export fn guiPlot(h: u32, x: i32, y: i32, color: u32) void {
    (guiAt(h) orelse return).plot(i16Of(x), i16Of(y), u8Of(color));
}
export fn guiText(h: u32, ptr: u32, len: u32, x: i32, y: i32, ink: u32, paper: u32) void {
    const g = guiAt(h) orelse return;
    g.text(slice(ptr, len), i16Of(x), i16Of(y), u8Of(ink), u8Of(paper));
}
/// A raw filled span. This exists because app code used to reach THROUGH the
/// context — `g.blit.fill(g.fb, ...)` — for spans the toolkit had no verb for
/// (ST Replay's waveform). Across a module boundary that is impossible, so the
/// verb is here instead. It is `guiRect` without the Rect, kept separate so the
/// intent (a raw span, not a widget) stays legible at the call site.
export fn guiFill(h: u32, x: i32, y: i32, w: i32, hh: i32, color: u32) void {
    const g = guiAt(h) orelse return;
    g.blit.fill(g.fb, i16Of(x), i16Of(y), u16Of(w), u16Of(hh), u8Of(color));
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
var desk_fb: zg.LogicalFB = undefined;
var desk_plane: u32 = 0;
var desk_ready: bool = false;

/// Bring up the desktop over PLANE `plane`. Same reasoning as guiOpenPlane: a
/// shell written in C could not have called the pointer form.
export fn deskInitPlane(plane: u32, screen_w: i32, screen_h: i32) void {
    if (!bindFb(&desk_fb, plane, screen_h)) return;
    desk_plane = plane;
    desk = .{};
    desk_blit = .{};
    desk_blit.init();
    desk.init(&raw_os, &desk_fb, &desk_blit);
    desk.g.screen_w = i16Of(screen_w);
    desk.g.screen_h = i16Of(screen_h);
    desk_ready = true;
}
/// The desktop's screen changed size (the Options menu switches LOW/MEDIUM).
export fn deskSetScreen(w: i32, h: i32) void {
    if (!desk_ready) return;
    // RE-BIND: switching LOW/MEDIUM rewrites the plane's stride register on the
    // same buffer, and our LogicalFB copy would keep the old one — drawing at the
    // wrong pitch, which looks like a shear rather than like a bug.
    _ = bindFb(&desk_fb, desk_plane, h);
    desk.g.screen_w = i16Of(w);
    desk.g.screen_h = i16Of(h);
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
    return @intCast(@intFromPtr(&desk.dir.disk_dir));
}
/// The FAT buffer's size in BYTES, so the host can size its write.
export fn deskDirCap() u32 {
    return @intCast(desk.dir.disk_dir.len);
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
    if (desk_ready) desk.dir.n_disk = @intCast(@min(n, gem.MAX_FILES));
}

inline fn rectOf(x: i32, y: i32, w: i32, h: i32) Rect {
    return .{ .x = i16Of(x), .y = i16Of(y), .w = i16Of(w), .h = i16Of(h) };
}
