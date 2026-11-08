// t64_snap.zig: render VICE snapshots (tools/c64/capture.py's f<N>.ram/.col/.vic/.cia/.trace)
// through the Transmission64 port's VIC model (apps/zig/scenes/c64_transmission64/vic.zig),
// to check the model against VICE's own pictures (tools/c64/compare.py).
//   zig build-exe --dep vic -Mroot=tools/c64/t64_snap.zig -Mvic=apps/zig/scenes/c64_transmission64/vic.zig
//   ./t64_snap <chargen.bin> <capdir> <outdir> <frame>...
// writes <outdir>/f<N>.pix (400x280 indices) and f<N>.border (border, split_x, split_c).
// A traced read-modify-write of $D018 is the part-3 NMI's INC (bit 0 reads 1, so it adds 2).
const std = @import("std");
const vic = @import("vic");

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const io = init.io;
    const a = init.gpa;
    const dir = std.Io.Dir.cwd();
    const lim: std.Io.Limit = .limited(1 << 20);
    const chargen = try dir.readFileAlloc(io, args.next().?, a, lim);
    defer a.free(chargen);
    const cap = try dir.openDir(io, args.next().?, .{});
    defer cap.close(io);
    const outdir = try dir.openDir(io, args.next().?, .{});
    defer outdir.close(io);
    const pix = try a.create([vic.Out.ROWS_COLS]u8);
    defer a.destroy(pix);
    const st = try a.create(vic.Stores);
    defer a.destroy(st);
    while (args.next()) |f| {
        const name = struct {
            fn n(buf: []u8, frame: []const u8, ext: []const u8) []const u8 {
                return std.fmt.bufPrint(buf, "f{s}.{s}", .{ frame, ext }) catch unreachable;
            }
        }.n;
        var nb: [64]u8 = undefined;
        const ram = try cap.readFileAlloc(io, name(&nb, f, "ram"), a, lim);
        defer a.free(ram);
        const col = try cap.readFileAlloc(io, name(&nb, f, "col"), a, lim);
        defer a.free(col);
        const regs = try cap.readFileAlloc(io, name(&nb, f, "vic"), a, lim);
        defer a.free(regs);
        const cia = try cap.readFileAlloc(io, name(&nb, f, "cia"), a, lim);
        defer a.free(cia);
        const trace = try cap.readFileAlloc(io, name(&nb, f, "trace"), a, lim);
        defer a.free(trace);
        var v = vic.Vic.init(regs[0..vic.NREG].*, cia[0]);
        var q = vic.Queue{};
        st.reset();
        for (col) |*c| c.* &= 15;
        var it = std.mem.splitScalar(u8, trace, '\n');
        var wrapped = false;
        var bank: u8 = v.bank;
        var prev_line: u16 = 0;
        while (it.next()) |ln| {
            if (ln.len == 0) continue;
            var fs = std.mem.tokenizeScalar(u8, ln, ' ');
            const line = try std.fmt.parseInt(u16, fs.next().?, 10);
            const cyc = try std.fmt.parseInt(u8, fs.next().?, 10);
            const addr = try std.fmt.parseInt(u16, fs.next().?, 16);
            const val_s = fs.next().?;
            if (line < prev_line) wrapped = true;
            prev_line = line;
            if (addr < 0xD000 or (addr >= 0xD800 and addr < 0xDC00) or addr >= 0xE000) { // memory the VIC reads
                if (std.mem.eql(u8, val_s, "RMW")) continue; // an INC/DEC of RAM: the trace has no value
                const val = try std.fmt.parseInt(u8, val_s, 16);
                const is_col = addr >= 0xD800 and addr < 0xDC00;
                if (!wrapped and line >= 288) {
                    if (is_col) col[addr - 0xD800] = val & 15 else ram[addr] = val;
                } else st.put(@as(u32, line) * vic.CYCLES + cyc, addr, val, is_col);
                continue;
            }
            const reg: u8 = if (addr == 0xDD00) vic.BANK else if (addr >= 0xD000 and addr < 0xD02F) @intCast(addr - 0xD000) else continue;
            const val: u8 = if (std.mem.eql(u8, val_s, "RMW")) blk: {
                if (reg != 0x18) continue; // ASL $D019 and the like
                break :blk (lastD018(&q, v.reg[0x18]) | 1) +% 1; // bit 0 reads as 1: INC adds 2
            } else try std.fmt.parseInt(u8, val_s, 16);
            if (reg == vic.BANK) { // the KERNAL's serial bus shares $DD00: keep bank changes only
                if (3 - (val & 3) == bank) continue;
                bank = 3 - (val & 3);
            }
            if (!wrapped and line >= 288) { // before this frame's line 0: the frame's start state
                if (reg == vic.BANK) v.bank = 3 - (val & 3) else v.reg[reg] = val;
                continue;
            }
            q.w(line, cyc, reg, val);
        }
        const mem = vic.Mem{ .ram = ram[0..65536], .col = col[0..1024], .chargen = chargen[0..4096] };
        @memset(pix, 0);
        var out = vic.Out{ .pix = pix };
        _ = v.frame(&q, st.items(), mem, &out);
        try outdir.writeFile(io, .{ .sub_path = name(&nb, f, "pix"), .data = pix });
        var b: [280 * 4]u8 = undefined;
        for (0..280) |r| {
            b[r] = out.border[r];
            std.mem.writeInt(u16, b[280 + 2 * r ..][0..2], out.split_x[r], .little);
            b[840 + r] = out.split_c[r];
        }
        try outdir.writeFile(io, .{ .sub_path = name(&nb, f, "border"), .data = &b });
    }
}

fn lastD018(q: *const vic.Queue, start: u8) u8 {
    var v = start;
    for (q.items()) |w| if (w.reg == 0x18) {
        v = w.val;
    };
    return v;
}
