// Native tests for the 6502 (cpu6502.zig): `zig test` this file. The vectors are
// SingleStepTests/65x02 (MIT, github.com/SingleStepTests/65x02, 6502/v1, commit
// 2f6980a2d957, 2025-05-10): the first 60 tests of every opcode the core runs,
// baked by prototypes/sap_re/sst_fetch.py into testdata/cpu6502_sst.bin
// (testdata/README.md). Each test is one instruction from a random state: the
// registers, the RAM it touched, its cycle count and its bus writes, in order,
// must all come out as the real chip's.
const std = @import("std");
const cpu = @import("cpu6502.zig");

const BLOB = @embedFile("testdata/cpu6502_sst.bin");

var mem: [65536]u8 = [_]u8{0} ** 65536;
var writes: [16][3]u16 = undefined;
var nwrites: usize = 0;

const Bus = struct {
    pub fn read(a: u16) u8 {
        return mem[a];
    }
    pub fn write(a: u16, v: u8) void {
        if (nwrites < writes.len) writes[nwrites] = .{ a, v, 0 };
        nwrites += 1;
        mem[a] = v;
    }
};

const Reader = struct {
    b: []const u8,
    i: usize = 0,
    fn u8_(r: *Reader) u8 {
        r.i += 1;
        return r.b[r.i - 1];
    }
    fn u16_(r: *Reader) u16 {
        const lo = r.u8_();
        return lo | (@as(u16, r.u8_()) << 8);
    }
};

const State = struct { pc: u16, s: u8, a: u8, x: u8, y: u8, p: u8, ram: []const u8 };

fn state(r: *Reader) State {
    const pc = r.u16_();
    const s = State{ .pc = pc, .s = r.u8_(), .a = r.u8_(), .x = r.u8_(), .y = r.u8_(), .p = r.u8_(), .ram = undefined };
    const n = r.u8_();
    const ram = r.b[r.i..][0 .. 3 * @as(usize, n)];
    r.i += ram.len;
    var out = s;
    out.ram = ram;
    return out;
}

fn addr(entry: []const u8) u16 {
    return entry[0] | (@as(u16, entry[1]) << 8);
}

/// One vector; null if it matches, else what differed.
fn one(r: *Reader, why: []u8) !?[]const u8 {
    const op = r.u8_();
    const in = state(r);
    const want = state(r);
    const cycles = r.u8_();
    const nw = r.u8_();
    const wlist = r.b[r.i..][0 .. 3 * @as(usize, nw)];
    r.i += wlist.len;
    var i: usize = 0;
    while (i < in.ram.len) : (i += 3) mem[addr(in.ram[i..])] = in.ram[i + 2];
    var c: cpu.Cpu(Bus) = .{ .pc = in.pc, .s = in.s, .a = in.a, .x = in.x, .y = in.y, .p = in.p };
    nwrites = 0;
    c.step();
    const got = .{ c.pc, c.s, c.a, c.x, c.y, c.p };
    const exp = .{ want.pc, want.s, want.a, want.x, want.y, want.p };
    if (!std.meta.eql(got, exp))
        return try std.fmt.bufPrint(why, "op {X:0>2}: pc s a x y p {any}, want {any}", .{ op, got, exp });
    if (c.cycles != cycles) return try std.fmt.bufPrint(why, "op {X:0>2}: {d} cycles, want {d}", .{ op, c.cycles, cycles });
    i = 0;
    while (i < want.ram.len) : (i += 3) if (mem[addr(want.ram[i..])] != want.ram[i + 2])
        return try std.fmt.bufPrint(why, "op {X:0>2}: ram ${X:0>4} = {X:0>2}, want {X:0>2}", .{ op, addr(want.ram[i..]), mem[addr(want.ram[i..])], want.ram[i + 2] });
    if (nwrites != nw) return try std.fmt.bufPrint(why, "op {X:0>2}: {d} bus writes, want {d}", .{ op, nwrites, nw });
    i = 0;
    while (i < nw) : (i += 1) if (writes[i][0] != addr(wlist[3 * i ..]) or writes[i][1] != wlist[3 * i + 2])
        return try std.fmt.bufPrint(why, "op {X:0>2}: write {d} ${X:0>4}={X:0>2}, want ${X:0>4}={X:0>2}", .{ op, i, writes[i][0], writes[i][1], addr(wlist[3 * i ..]), wlist[3 * i + 2] });
    return null;
}

test "every opcode the core runs matches SingleStepTests: registers, RAM, cycles, bus writes" {
    var r = Reader{ .b = BLOB, .i = 4 };
    const count = std.mem.readInt(u32, BLOB[0..4], .little);
    var failed: u32 = 0;
    var why: [200]u8 = undefined;
    var t: u32 = 0;
    while (t < count) : (t += 1) {
        if (try one(&r, &why)) |msg| {
            if (failed < 12) std.debug.print("{s}\n", .{msg});
            failed += 1;
        }
    }
    try std.testing.expect(count > 10_000);
    try std.testing.expectEqual(@as(u32, 0), failed);
}

test "the unstable opcodes and the JAMs stop the CPU, with the opcode, and nothing runs after" {
    for ([_]u8{ 0x02, 0x8B, 0x9C }) |op| {
        mem[0x400] = op;
        var c: cpu.Cpu(Bus) = .{ .pc = 0x400 };
        c.step();
        c.step();
        try std.testing.expect(c.stop != .none);
        try std.testing.expectEqual(op, c.stop_op);
        try std.testing.expectEqual(@as(u16, 0x400), c.pc);
        try std.testing.expectEqual(@as(u64, 0), c.cycles);
    }
}
