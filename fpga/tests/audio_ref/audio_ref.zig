//! The audio oracle for the RTL: the machine's own sound chips
//! (machine/audio/engine.zig + ym.zig, imported unchanged as module `engine`)
//! driven by the same stimulus script as the CXXRTL testbenches, writing the
//! samples they make as 16-bit stereo (little-endian L, R).
//!
//!   audio_ref <script> <out.raw>
//!
//! Script lines (tests/tb/audio_script.h reads the same; `#` starts a comment):
//!   pcm <file>            the PCM memory: byte n at address n (machinePaulaTrigger's data_abs)
//!   run <n>               render n samples
//!   ym <reg> <val>        machineYmWrite
//!   trig <c> <data> <len> <loop_start> <loop_len> <pan>   machinePaulaTrigger (pan / 128)
//!   step|vol|pan|pos|act <c> <v>    machinePaulaSet{Step,Volume (v / 256),Pan (v / 128),Pos,Active}
//!   reset                 machineAudioReset
//!   mid <command>         render one sample, then the command: the RTL testbench
//!                         makes its writes while that sample is being mixed
//!   rom <file> <frames>   play a register-dump ROM (tools/ym_rom.py) for <frames> 50 Hz frames
//!   ymraw <file> <frames> play a YM5!/YM6! file exactly as libs/zig/players/ym_player.zig does
//! A sample's 16 bits are floor(x * 32768) of the clamped bus, +1.0 saturating
//! (zm_audio_mix does the same).
const std = @import("std");
const eng = @import("engine");

const FRAME = 882; // 44100 / 50: ym_player's samples_per_frame

var engine: eng.Engine = undefined;
var pcm: []const u8 = &.{};
var out: std.ArrayList(u8) = .empty;
var gpa: std.mem.Allocator = undefined;

pub fn main(init: std.process.Init) !void {
    gpa = init.arena.allocator(); // the process arena: everything lives until exit
    var args = init.minimal.args.iterate();
    _ = args.next();
    const script_path = args.next() orelse return usage();
    const out_path = args.next() orelse return usage();
    const script = try std.Io.Dir.cwd().readFileAlloc(init.io, script_path, gpa, .limited(1 << 24));
    engine.init();
    var lines = std.mem.splitScalar(u8, script, '\n');
    while (lines.next()) |line| try command(init.io, line);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out_path, .data = out.items });
}

fn usage() error{Usage} {
    std.debug.print("usage: audio_ref <script> <out.raw>\n", .{});
    return error.Usage;
}

fn num(it: *std.mem.TokenIterator(u8, .any)) !i64 {
    return std.fmt.parseInt(i64, it.next() orelse return error.Syntax, 0);
}

fn command(io: std.Io, raw: []const u8) !void {
    const line = if (std.mem.indexOfScalar(u8, raw, '#')) |i| raw[0..i] else raw;
    var it = std.mem.tokenizeAny(u8, line, " \t\r");
    const op = it.next() orelse return;
    if (std.mem.eql(u8, op, "mid")) {
        try render(1);
        return command(io, it.rest());
    }
    if (std.mem.eql(u8, op, "pcm")) {
        pcm = try std.Io.Dir.cwd().readFileAlloc(io, it.next() orelse return error.Syntax, gpa, .limited(1 << 24));
    } else if (std.mem.eql(u8, op, "run")) {
        try render(@intCast(try num(&it)));
    } else if (std.mem.eql(u8, op, "ym")) {
        const r = try num(&it);
        engine.ym.writeReg(@intCast(r), @intCast(try num(&it)));
    } else if (std.mem.eql(u8, op, "reset")) {
        audioReset();
    } else if (std.mem.eql(u8, op, "trig")) {
        try trigger(&it);
    } else if (std.mem.eql(u8, op, "rom") or std.mem.eql(u8, op, "ymraw")) {
        const data = try std.Io.Dir.cwd().readFileAlloc(io, it.next() orelse return error.Syntax, gpa, .limited(1 << 24));
        const frames: u32 = @intCast(try num(&it));
        if (op[0] == 'r') try playRom(data, frames) else try playYm(data, frames);
    } else {
        try channelSet(op, &it);
    }
}

// machinePaulaSet*: the channel's field, with the register forms of the floats.
fn channelSet(op: []const u8, it: *std.mem.TokenIterator(u8, .any)) !void {
    const c = &engine.channels[@intCast(try num(it))];
    const v = try num(it);
    if (std.mem.eql(u8, op, "step")) {
        c.step = @intCast(v);
    } else if (std.mem.eql(u8, op, "vol")) {
        c.volume = @as(f32, @floatFromInt(v)) / 256.0;
    } else if (std.mem.eql(u8, op, "pan")) {
        c.pan = @as(f32, @floatFromInt(v)) / 128.0;
    } else if (std.mem.eql(u8, op, "pos")) {
        c.pos = @as(u64, @intCast(v)) << 16;
    } else if (std.mem.eql(u8, op, "act")) {
        c.active = v != 0;
    } else return error.Syntax;
}

// machinePaulaTrigger, as machine/machine_audio.zig does it.
fn trigger(it: *std.mem.TokenIterator(u8, .any)) !void {
    const c = &engine.channels[@intCast(try num(it))];
    const data: usize = @intCast(try num(it));
    const len: usize = @intCast(try num(it));
    c.data = @ptrCast(pcm[data .. data + len]);
    c.pos = 0;
    c.loop_start = @intCast(try num(it));
    c.loop_len = @intCast(try num(it));
    c.pan = @as(f32, @floatFromInt(try num(it))) / 128.0;
    c.active = true;
}

// machineAudioReset (machine/machine_audio.zig).
fn audioReset() void {
    engine.ym.writeReg(7, 0x3F);
    engine.ym.writeReg(8, 0);
    engine.ym.writeReg(9, 0);
    engine.ym.writeReg(10, 0);
    for (&engine.channels) |*ch| ch.active = false;
}

// One block, as a player renders it: clear, Paula, YM, clamp.
fn render(n_total: usize) !void {
    var left = n_total;
    while (left > 0) {
        const n = @min(left, eng.MAX_FRAMES);
        engine.clearBus(n);
        engine.mixChannels(engine.left[0..n], engine.right[0..n]);
        engine.ym.render(engine.left[0..n], engine.right[0..n]);
        engine.clampBus(n);
        for (0..n) |i| {
            try put(engine.left[i]);
            try put(engine.right[i]);
        }
        left -= n;
    }
}

fn put(x: f32) !void {
    const v: i32 = @min(@as(i32, @intFromFloat(@floor(x * 32768.0))), 32767);
    const s: i16 = @intCast(v);
    try out.appendSlice(gpa, &@as([2]u8, @bitCast(std.mem.nativeToLittle(i16, s))));
}

// The dump ROM (tools/ym_rom.py): 16-bit little-endian words; 0rrrrrrr vvvvvvvv
// writes register r, 1nnnnnnn nnnnnnnn waits n frames, 0x8000 then a word index
// jumps there (the loop).
fn playRom(data: []const u8, frames: u32) !void {
    var pc: usize = 0;
    var wait: u32 = 0;
    for (0..frames) |_| {
        while (wait == 0) {
            const w = std.mem.readInt(u16, data[2 * pc ..][0..2], .little);
            pc += 1;
            if (w == 0x8000) {
                pc = std.mem.readInt(u16, data[2 * pc ..][0..2], .little);
            } else if (w & 0x8000 != 0) {
                wait = w & 0x7FFF;
            } else {
                engine.ym.writeReg(@intCast(w >> 8), @truncate(w));
            }
        }
        try render(FRAME);
        wait -= 1;
    }
}

// ym_player.zig's writeFrame + renderStereo, for a YM5!/YM6! file without drums
// (the player ignores them anyway): all 14 registers, every frame.
fn playYm(data: []const u8, frames: u32) !void {
    const nb = std.mem.readInt(u32, data[12..16], .big);
    const interleaved = std.mem.readInt(u32, data[16..20], .big) & 1 != 0;
    const loop = std.mem.readInt(u32, data[28..32], .big);
    var off: usize = 34 + std.mem.readInt(u16, data[32..34], .big);
    for (0..std.mem.readInt(u16, data[20..22], .big)) |_| off += 4 + std.mem.readInt(u32, data[off..][0..4], .big);
    for (0..3) |_| off = std.mem.indexOfScalarPos(u8, data, off, 0).? + 1;
    var frame: u32 = 0;
    for (0..frames) |_| {
        if (frame >= nb) frame = if (loop < nb) loop else 0;
        for (0..14) |r| {
            const idx = if (interleaved) r * nb + frame else frame * 16 + r;
            engine.ym.writeReg(@intCast(r), data[off + idx]);
        }
        frame += 1;
        try render(FRAME);
    }
}
