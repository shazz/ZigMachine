// "Reboot" (console > Reboot... after a Yes/No, `glass ctl reboot` with no question), Matt 14 Nov.
// The request only marks it and says "Rebooting..." (the OSD, or the ctl reply, goes out first);
// the next App.tick runs it: the cart CPU held and the mixer muted (a clean stop of the audio),
// a pending settings save done, `sync`, the card read-only again, then the restart.
//
// The restart is reboot(2) RESTART after /tmp/glass.stop is touched (S99glass's loop then does not
// bring glass back for a second life while the kernel is going down). Not busybox `reboot`: that
// needs init, PATH and rcK to cooperate and kills glass in the middle of it; the card is read-only
// and synced here, and nothing else on the rootfs needs a clean stop. If reboot(2) is refused the
// stop mark goes again, so the menu comes back and says so.
// Everything is on the main thread, so no settings/screenshot/Wi-Fi write can be half done here.
const std = @import("std");
const map = @import("map.zig");
const loader = @import("loader.zig");
const App = @import("app.zig").App;
const cart = @import("app_cart.zig");

pub const STOP_MARK = "/tmp/glass.stop";

/// `sync_fn` and `restart_fn` are injected by the tests: the host must never reboot.
pub const State = struct {
    pending: bool = false,
    sync_fn: *const fn () void = realSync,
    restart_fn: *const fn () bool = realRestart, // returns only if the restart failed
};

/// Mark the reboot; the next tick does it. False if one is already under way.
pub fn request(app: *App) bool {
    if (app.reboot.pending) return false;
    app.reboot.pending = true;
    app.menu.setStatus("Rebooting...", .{});
    if (app.open) app.redraw();
    return true;
}

/// From App.tick.
pub fn tick(app: *App) void {
    if (!app.reboot.pending) return;
    app.reboot.pending = false;
    loader.hold(app.regs) catch |err| std.log.warn("reboot: the cart CPU did not stop: {t}", .{err});
    app.regs.write(map.REG_AUDIO_VOL, app.menu.settings.audioWord() | map.AUDIO_MUTE);
    cart.saveSettings(app); // a volume change not saved yet goes first
    app.reboot.sync_fn();
    if (app.sd_writable) |rw| if (!rw(false)) std.log.warn("reboot: the card stayed writable", .{});
    std.log.info("reboot: synced, restarting", .{});
    if (app.reboot.restart_fn()) return;
    app.menu.setStatus("reboot failed", .{});
    if (!app.open) app.setOpen(true) else app.redraw();
}

fn realSync() void {
    std.os.linux.sync();
}

fn realRestart() bool {
    const linux = std.os.linux;
    touch(STOP_MARK);
    const rc = linux.reboot(.MAGIC1, .MAGIC2, .RESTART, null);
    std.log.err("reboot(2): {t}", .{linux.errno(rc)});
    _ = linux.unlink(STOP_MARK); // still here: the loop must restart glass
    return false;
}

fn touch(path: [:0]const u8) void {
    const fd = std.os.linux.open(path, .{ .ACCMODE = .WRONLY, .CREAT = true }, 0o644);
    if (std.os.linux.errno(fd) == .SUCCESS) _ = std.os.linux.close(@intCast(fd));
}
