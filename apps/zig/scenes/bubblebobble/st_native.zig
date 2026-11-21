// Native runner for the translated game (development + reference captures, no ZigOS):
//   zig run -OReleaseFast apps/zig/scenes/bubblebobble/st_native.zig -- <re_dir> <frames> <outdir> [every] [script]
// Loads <re_dir>/work/text_reloc.bin and <re_dir>/files/GRAPHICS/*, runs <frames> 50 Hz frames,
// writes the shown screen as <outdir>/fNNNNN.ppm every [every] frames. [script]: "frame:key:down"
// events separated by commas (key = scancode hex, or j0..j1=<hex> joystick states).
const std = @import("std");
const k = @import("st/cpu.zig");
const io = @import("st/io.zig");
const tos = @import("st/tos.zig");
const frame = @import("st/frame.zig");

const NAMES = [_][]const u8{ "BBLOCKS.PI1", "BUBBLE.SPR", "SPIC.PI1", "AIRFLOW.DAT", "UNSHIFT.SPR", "BDATA.DAT", "FRUIT.SPR", "SECRET.PI1", "EXTEND.PI1", "DWARF.SPR", "MUSIC.DAT" };

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io_ = init.io;
    var args = init.minimal.args.iterate();
    _ = args.next();
    const re = args.next().?;
    const nframes = try std.fmt.parseInt(u32, args.next().?, 10);
    const out = args.next().?;
    const every = if (args.next()) |e| try std.fmt.parseInt(u32, e, 10) else 50;
    const script = args.next() orelse "";
    const cwd = std.Io.Dir.cwd();
    var files: [NAMES.len]tos.File = undefined;
    for (NAMES, 0..) |n, i| {
        const p = try std.fmt.allocPrint(gpa, "{s}/files/GRAPHICS/{s}", .{ re, n });
        files[i] = .{ .name = n, .data = try cwd.readFileAlloc(io_, p, gpa, .limited(1 << 20)) };
    }
    tos.files = &files;
    const tp = try std.fmt.allocPrint(gpa, "{s}/work/text_reloc.bin", .{re});
    const text = try cwd.readFileAlloc(io_, tp, gpa, .limited(1 << 20));
    k.mem = try gpa.alloc(u8, k.RAM);
    frame.reset(text);
    cwd.createDirPath(io_, out) catch {};
    var f: u32 = 0;
    while (f < nframes) : (f += 1) {
        applyScript(script, f);
        frame.runFrame();
        if (f % every == every - 1) try dump(gpa, io_, out, f);
    }
    std.debug.print("frames {d} pc {x} cy {d} bad {d} (last {x}) io-dropped {d} tos-unknown {d} psg {d} stuck {d} term {}\n", .{ frame.frames, frame.pc, k.cy, k.bad_pcs, k.last_bad, io.dropped, tos.unknown, io.psg_writes, frame.stuck_irqs, tos.terminated });
}

fn applyScript(script: []const u8, f: u32) void {
    var it = std.mem.splitScalar(u8, script, ',');
    while (it.next()) |ev| {
        var p = std.mem.splitScalar(u8, ev, ':');
        const at = std.fmt.parseInt(u32, p.next() orelse continue, 10) catch continue;
        if (at != f) continue;
        const what = p.next() orelse continue;
        const val = std.fmt.parseInt(u8, p.next() orelse "0", 16) catch 0;
        if (what.len == 1 and what[0] == 't') {
            tos.typeKey(val);
        } else if (what.len == 2 and what[0] == 'j') {
            frame.setJoystick(@intCast(what[1] - '0'), val);
        } else {
            io.kbd_byte = std.fmt.parseInt(u8, what, 16) catch 0;
            if (val == 0) io.kbd_byte |= 0x80;
        }
    }
}

fn dump(gpa: std.mem.Allocator, io_: std.Io, out: []const u8, f: u32) !void {
    var buf: [15 + 320 * 200 * 3]u8 = undefined;
    const hdr = "P6\n320 200\n255\n";
    @memcpy(buf[0..hdr.len], hdr);
    var pal: [200][16]u16 = undefined;
    var cur = io.palette_top;
    var ri: usize = 0;
    for (0..200) |y| {
        while (ri < io.raster_n and io.rasters[ri].line < y) : (ri += 1) cur[io.rasters[ri].reg] = io.rasters[ri].value;
        pal[y] = cur;
    }
    const base = io.shown_base;
    for (0..200) |y| for (0..320) |x| {
        const g = base + @as(u32, @intCast(y * 160 + (x / 16) * 8));
        const bitn: u4 = @intCast(15 - (x % 16));
        var c: u4 = 0;
        for (0..4) |pl| {
            const w = k.rw(g + @as(u32, @intCast(pl * 2)));
            c |= @as(u4, @intCast((w >> bitn) & 1)) << @intCast(pl);
        }
        const col = pal[y][c];
        const o = hdr.len + (y * 320 + x) * 3;
        buf[o] = @intCast(((col >> 8) & 7) * 255 / 7);
        buf[o + 1] = @intCast(((col >> 4) & 7) * 255 / 7);
        buf[o + 2] = @intCast((col & 7) * 255 / 7);
    };
    const name = try std.fmt.allocPrint(gpa, "{s}/f{d:0>5}.ppm", .{ out, f + 1 });
    try std.Io.Dir.cwd().writeFile(io_, .{ .sub_path = name, .data = &buf });
}
