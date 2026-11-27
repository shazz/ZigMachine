// --------------------------------------------------------------------------
// RACER: a track's panorama off the disk (R82 32X look, LOOK.md item 1). When a track goes on show the cart
// looks for `<TRACK>.PAN` on its own disk (panofile.zig: a strip that wraps a full turn, with its own colours);
// found and good, it is drawn behind the 3D instead of the mood's backdrop shape (backdrop.zig) and its colours
// go on the entries it names. No file: the mood's shape, as before. A bad file is refused by name with its
// reason (the console and the select's refusals) and the shape is drawn: never a trap. The file is read into the
// library's stage and depacked into backdrop's strip buffer, which `init` sizes to the disk's largest panorama
// (before the library takes what the RAM window has left): a disk without one costs nothing.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const zx0 = @import("depackers").zx0;
const backdrop = @import("backdrop.zig");
const panofile = @import("panofile.zig");
const refusals = @import("refusals.zig");
const trk = @import("trk.zig");

pub const Fail = error{ ReadFailed, TooBig, BadPack } || panofile.Error;

/// The bytes the disk's largest panorama depacks to (0: none on the disk). Read from each file's first bytes only.
pub fn largest() usize {
    const lay = zg.disk.mount() orelse return 0;
    var most: usize = 0;
    var i: u16 = 0;
    while (i < lay.count) : (i += 1) {
        const e = zg.disk.entryAt(lay, i) orelse continue;
        if (!std.ascii.endsWithIgnoreCase(std.mem.sliceTo(&e.name, 0), ".PAN")) continue;
        var head: [16]u8 = undefined;
        const got = zg.disk.read(e.e, &head);
        const raw = if (zx0.isPacked(head[0..got])) zx0.depackedLen(head[0..got]) orelse 0 else e.e.len;
        if (raw <= maxRaw()) most = @max(most, raw); // a bigger one is refused when its track is shown
    }
    return most;
}

pub fn maxRaw() usize {
    return panofile.HEADER + 4 * panofile.MAX_COLOURS + panofile.MAX_W * (panofile.MAX_ROWS + panofile.MAX_LOWER);
}

/// The panorama for track `t` (its library label) on show, or none (the mood's shape). Its colours: `paint`.
pub fn forTrack(label: []const u8, t: *const trk.Track, stage: []u8, rej: *refusals.Refusals) void {
    backdrop.pan = null;
    var nb: [12]u8 = undefined;
    const name = std.fmt.bufPrint(&nb, "{s}.PAN", .{label[0..@min(label.len, 8)]}) catch return;
    const p = load(name, t, stage) catch |err| {
        zg.Console.log("racer,pan,refused,{s},{s}", .{ name, @errorName(err) });
        rej.add(name, .bad_pan);
        return;
    } orelse return;
    backdrop.pan = p;
    zg.Console.log("racer,pan,{s},{},{},{}", .{ name, p.width, p.rows, p.colours.len });
}

/// The panorama's colours on its entries (after palette.install, which clears them).
pub fn paint(pal: [*]u32) void {
    const p = backdrop.pan orelse return;
    for (p.colours, p.first..) |c, i| pal[i] = zg.linepal.rgb(c[0], c[1], c[2]);
}

fn load(name: []const u8, t: *const trk.Track, stage: []u8) Fail!?panofile.Pan {
    const lay = zg.disk.mount() orelse return null;
    const e = zg.disk.find(lay, name) orelse return null;
    const buf = backdrop.panBuffer();
    var head: [16]u8 = undefined;
    const got = zg.disk.read(e, &head);
    var raw: usize = e.len;
    if (zx0.isPacked(head[0..got])) { // packed (the disk tool's way): staged, depacked into the strip buffer
        raw = zx0.depackedLen(head[0..got]) orelse return error.BadPack;
        if (e.len > stage.len or raw > buf.len) return error.TooBig;
        if (zg.disk.read(e, stage[0..e.len]) != e.len) return error.ReadFailed;
        backdrop.lose(); // the shape strip shares the buffer
        if ((zx0.depack(stage[0..e.len], buf[0..raw]) orelse 0) != raw) return error.BadPack;
    } else { // raw: straight into the strip buffer
        if (raw > buf.len) return error.TooBig;
        backdrop.lose();
        if (zg.disk.read(e, buf[0..raw]) != raw) return error.ReadFailed;
    }
    const p = try panofile.parse(buf[0..raw]);
    try panofile.clash(&p, t);
    return p;
}
