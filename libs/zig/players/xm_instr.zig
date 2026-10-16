// --------------------------------------------------------------------------
// XM instruments and samples: their headers, the volume envelope, and the
// sample PCM. The PCM is stored DELTA-coded (each frame is the difference from
// the one before, wrapping); it is decoded here IN PLACE in the song image,
// to signed 8-bit frames: a 16-bit sample keeps its top byte (Paula is 8-bit
// anyway), and the decoded frames are never bigger than the coded bytes, so
// the song's own buffer holds them and no second pool is needed. A loaded
// song is therefore consumed: a reload must re-stage the file.
// Pure: no chip, no allocation. Tested natively (xm_format_test.zig).
// --------------------------------------------------------------------------
const fmt = @import("xm_format.zig");
const rd16 = fmt.rd16;
const rd32 = fmt.rd32;

pub const MAX_ENV_POINTS: usize = 12;
pub const LOOP_NONE: u8 = 0;
pub const LOOP_FORWARD: u8 = 1;
pub const LOOP_PINGPONG: u8 = 2;

pub const Point = struct { x: u16 = 0, y: u16 = 0 };

pub const Envelope = struct {
    on: bool = false,
    sustain_on: bool = false,
    loop_on: bool = false,
    n: u8 = 0, // points in use
    sustain: u8 = 0, // point index held while the key is down
    loop_start: u8 = 0,
    loop_end: u8 = 0,
    pts: [MAX_ENV_POINTS]Point = [_]Point{.{}} ** MAX_ENV_POINTS,
};

pub const Instrument = struct {
    first: u16 = 0, // index of its first sample in the song's sample table
    count: u8 = 0,
    /// Note (0-based, C-0 = 0) -> sample index within the instrument.
    map: [96]u8 = [_]u8{0} ** 96,
    vol: Envelope = .{},
    fadeout: u16 = 0, // subtracted from 65536 a tick once the key is up
};

pub const Sample = struct {
    off: u32 = 0, // byte offset of the decoded frames in the song image
    len: u32 = 0, // frames
    loop_start: u32 = 0, // frames
    loop_len: u32 = 0, // frames; 0 = no loop
    loop: u8 = LOOP_NONE,
    volume: u8 = 0, // 0..64
    finetune: i8 = 0,
    relnote: i8 = 0,
};

/// Only the first `count` samples and the first num_instruments instruments are
/// ever read (the header and parseAll bound them), so the rest stay undefined: a
/// zero default here would be a ~30 KB zero blob in the data segment (zero_segments).
pub const Tables = struct {
    insts: [fmt.MAX_INSTRUMENTS]Instrument = undefined,
    samps: [fmt.MAX_SAMPLES]Sample = undefined,
    count: usize = undefined, // samples in use (parseAll sets it)
};

pub const Error = fmt.Error;

/// Read every instrument from `start` (the end of the patterns) and decode
/// their samples in place in `data`. Refuses (never plays) a sample that runs
/// past the file, a loop outside its sample, or an envelope over 12 points.
pub fn parseAll(data: []u8, hdr: *const fmt.Header, start: usize, t: *Tables) Error!void {
    var o = start;
    var ns: usize = 0;
    for (0..hdr.num_instruments) |i| {
        if (o + 29 > data.len) return error.Truncated;
        const isz = rd32(data, o);
        if (isz < 29 or o + isz > data.len) return error.Truncated;
        const nsmp = rd16(data, o + 27);
        if (ns + nsmp > fmt.MAX_SAMPLES) return error.TooManySamples;
        var inst: Instrument = .{ .first = @intCast(ns), .count = @intCast(nsmp) };
        if (nsmp > 0) try readInstHeader(data, o, isz, nsmp, &inst);
        t.insts[i] = inst;
        const sh_size: usize = if (nsmp > 0) rd32(data, o + 29) else 0;
        o = try readSamples(data, o + isz, nsmp, sh_size, t, ns);
        ns += nsmp;
    }
    t.count = ns;
}

/// The note map, the volume envelope and the fadeout: the parts of an instrument
/// header that exist only when it has samples.
fn readInstHeader(data: []const u8, o: usize, isz: u32, nsmp: u16, inst: *Instrument) Error!void {
    if (isz < 243) return error.BadInstrument;
    for (0..96) |n| {
        const s = data[o + 33 + n];
        if (s >= nsmp) return error.BadInstrument;
        inst.map[n] = s;
    }
    inst.vol = try readEnvelope(data, o);
    inst.fadeout = rd16(data, o + 239);
}

fn readEnvelope(data: []const u8, o: usize) Error!Envelope {
    const n = data[o + 225];
    if (n > MAX_ENV_POINTS) return error.BadInstrument;
    const flags = data[o + 233];
    var e: Envelope = .{
        .on = flags & 1 != 0,
        .sustain_on = flags & 2 != 0,
        .loop_on = flags & 4 != 0,
        .n = n,
        .sustain = data[o + 227],
        .loop_start = data[o + 228],
        .loop_end = data[o + 229],
    };
    for (0..MAX_ENV_POINTS) |k| e.pts[k] = .{ .x = rd16(data, o + 129 + 4 * k), .y = rd16(data, o + 131 + 4 * k) };
    return e;
}

/// The sample headers that follow the instrument header, then the PCM of each
/// sample in turn. Returns the offset after the instrument's last sample.
fn readSamples(data: []u8, sh0: usize, nsmp: u16, sh_size: usize, t: *Tables, first: usize) Error!usize {
    if (nsmp == 0) return sh0;
    if (sh_size < 40) return error.BadInstrument;
    var pcm = sh0 + @as(usize, nsmp) * sh_size;
    if (pcm > data.len) return error.Truncated;
    for (0..nsmp) |j| {
        const h = sh0 + j * sh_size;
        const s = try sampleHeader(data, h, pcm);
        t.samps[first + j] = s;
        pcm += @as(usize, s.len) * (if (data[h + 14] & 0x10 != 0) @as(usize, 2) else 1);
        if (pcm > data.len) return error.Truncated;
    }
    return pcm;
}

/// One sample's header, and its PCM decoded in place at `pcm`.
fn sampleHeader(data: []u8, h: usize, pcm: usize) Error!Sample {
    const bytes = rd32(data, h);
    const is16 = data[h + 14] & 0x10 != 0;
    const kind = data[h + 14] & 3;
    if (kind == 3) return error.BadInstrument;
    const frame: u32 = if (is16) 2 else 1;
    const len = bytes / frame;
    if (pcm + bytes > data.len) return error.Truncated;
    var s: Sample = .{
        .off = @intCast(pcm),
        .len = len,
        .loop_start = rd32(data, h + 4) / frame,
        .loop_len = rd32(data, h + 8) / frame,
        .volume = data[h + 12],
        .finetune = @bitCast(data[h + 13]),
        .relnote = @bitCast(data[h + 16]),
    };
    if (s.volume > 64) return error.BadInstrument;
    if (s.loop_len == 0 or kind == 0) {
        s.loop = LOOP_NONE;
        s.loop_len = 0;
    } else {
        if (s.loop_start > len or s.loop_len > len - s.loop_start) return error.BadInstrument;
        s.loop = if (kind == 2) LOOP_PINGPONG else LOOP_FORWARD;
    }
    decodeDelta(data[pcm..][0..bytes], is16);
    return s;
}

/// Undo the delta coding in place: the input is read ahead of the output at every
/// step (a 16-bit frame of two bytes becomes one 8-bit byte at the same place or
/// before it), so the forward walk never overwrites a byte it still needs.
fn decodeDelta(bytes: []u8, is16: bool) void {
    if (is16) {
        var acc: u16 = 0;
        var i: usize = 0;
        while (2 * i + 1 < bytes.len) : (i += 1) {
            acc +%= @as(u16, bytes[2 * i]) | (@as(u16, bytes[2 * i + 1]) << 8);
            bytes[i] = @truncate(acc >> 8);
        }
    } else {
        var acc: u8 = 0;
        for (bytes) |*b| {
            acc +%= b.*;
            b.* = acc;
        }
    }
}
