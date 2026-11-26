// --------------------------------------------------------------------------
// RACER: the track binary tools/racer/trackc.py writes (layout in its docstring), checked and
// viewed in place. Nothing is copied: every slice points into the blob, which the cart embeds
// in an aligned array (a misaligned word load traps on the board).
// A bad magic, version, CRC or block bound is refused with a name, never defaulted. Since M5 step 2 a track
// can be a FILE (a disk's, a user's): every count and offset in the header is untrusted input, bounded here
// before the cart follows it (overflow-safe block maths, the palette's 30 ramps, seg.MAXSEG, the 8 grid
// slots, every PVS list inside its block, the mood block: tools/racer/mood.py; M6 its haze, bytes 27-31).
// No ZigOS import: trk_test.zig runs it natively.
// --------------------------------------------------------------------------
const std = @import("std");

pub const MAGIC: u32 = 0x4B52544B;
pub const VERSION: u32 = 3;
pub const HEADER = 128;
pub const GRID = 32;
pub const TILES = GRID * GRID;
pub const BUCKETS = 16;
pub const RAYS = 33;
pub const NOT_BAKED: u32 = 0xFFFF_FFFF;
pub const Error = error{ Truncated, BadMagic, BadVersion, BadCrc, BadBlock, BadMood };
pub const MAX_RAMPS = 30; // 16 + 30 x 8 = 256 palette entries
pub const MAX_SEG = 256; // seg.MAXSEG, minimap.MAXPTS
pub const MAX_GRID = 8; // race.NCARS
pub const MAX_RBAKE = 8; // pvs.dda's distances
pub const MOOD_WORD = 25;
pub const MOOD_SIZE = 32;
pub const BACKDROPS = 3; // backdrop.zig's shapes: hills, docks, peaks
pub const BENCH_ONLY: u8 = 1;
pub const MAX_CLOCK = [2]u8{ 250, 60 }; // clock.MAX_START, MAX_EXTEND

/// How a track looks beyond its faces (tools/racer/mood.py): the far ground (palette index 4), the sky, the backdrop.
pub const Mood = extern struct {
    ground_ramp: u8 = 1,
    ground_level: u8 = 4,
    flags: u8 = 0, // BENCH_ONLY: no drive / race here (the stress city)
    backdrop: u8 = 0,
    sky: [2][4]u8 = .{ .{ 28, 60, 150, 0 }, .{ 170, 205, 235, 0 } }, // top, horizon
    hills: [3][4]u8 = .{ .{ 110, 130, 170, 0 }, .{ 70, 100, 90, 0 }, .{ 60, 60, 90, 0 } }, // palette 12, 13, 14
    clock: [2]u8 = .{ 0, 0 }, // the race clock: start, extension a checkpoint (s); 0 = computed (clock.zig, M5 step 4)
    draw_r: u8 = 0, // the track's draw distance cap, tiles 3..8; 0 = none (M5 finish: trackset.playR)
    haze: [3]u8 = .{ 0, 0, 0 }, // the horizon haze's colour (M6, haze.zig)
    haze_start: u8 = 0, // where it starts, x/256 of the draw distance
    haze_strength: u8 = 0, // its blend at the draw distance, x/255; 0 = no haze (then the colour and start are 0 too)
};

pub const FLAG_DUAL: u8 = 1;
pub const FLAG_INNER: u8 = 0x20; // set on an inner (decal) record by the converter

/// A face: up to 4 vertices, the baked palette colour, the plane (n Q14, cp = n . v0 Q21).
pub const Face = extern struct {
    v: [4]u16,
    flags: u8,
    nv: u8,
    colour: u8,
    inner_n: u8,
    n: [3]i16,
    borders: u16, // physics: bit k = edge k (vertex k to k + 1) is a wall edge
    cp: i32,
    inner_first: u32,
    alt: u32, // 0, or (a local VR import) the debug key's other shades: byte 0 lit by the normal, byte 1 gently lit (project.shade)
};

pub const Seg = extern struct { pos: [3]i32, yaw: u16, segment: u16 }; // segment: the racing-line index (a start-grid pose); on the line, flags
pub const LINE_ROOF: u16 = 1; // a line entry's flag: a roof over the segment (zone.zig: the far camera goes near; M5 finish)
pub const Vert = [3]i16; // 1/128 unit

pub const Track = struct {
    name: [24]u8,
    palette: []const [4]u8,
    verts: []const Vert,
    faces: []const Face,
    inner: []const Face,
    tile_first: []const u32, // TILES + 1
    tile_faces: []const u16,
    rays: []const [BUCKETS][RAYS][2]i16, // 1 entry
    pvs_index: []const u32, // TILES * BUCKETS
    pvs: []const u16,
    line: []const Seg,
    grid: []const Seg,
    lr: []const [2]u16, // per racing-line segment: the left and right vertex ids (the physics' quads)
    checkpoints: []const u32, // racing-line segment indices, in lap order (the race rules)
    rbake: u32,
    mood: Mood,

    pub fn tileFaces(self: *const Track, tile: usize) []const u16 {
        return self.tile_faces[self.tile_first[tile]..self.tile_first[tile + 1]];
    }
};

fn word(b: []const u8, i: usize) u32 {
    return std.mem.readInt(u32, b[i * 4 ..][0..4], .little);
}

fn block(comptime T: type, b: []align(4) const u8, off: u32, n: usize, end: u32) Error![]const T {
    const bytes = @as(u64, n) * @sizeOf(T); // u64: a hostile count cannot wrap the bound
    if (off < HEADER or off % 4 != 0 or end > b.len or off > end or bytes > end - off) return error.BadBlock;
    const p: [*]const T = @ptrCast(@alignCast(&b[off]));
    return p[0..n];
}

pub fn parse(b: []align(4) const u8) Error!Track {
    if (b.len < HEADER) return error.Truncated;
    if (word(b, 0) != MAGIC) return error.BadMagic;
    if (word(b, 1) != VERSION) return error.BadVersion;
    const total = word(b, 3);
    if (total != b.len) return error.Truncated;
    if (std.hash.crc.Crc32IsoHdlc.hash(b[HEADER..]) != word(b, 2)) return error.BadCrc;
    const nv = word(b, 4);
    const nf = word(b, 5);
    const ni = word(b, 6);
    const nseg = word(b, 7);
    const ngrid = word(b, 8);
    const nramps = word(b, 9);
    if (nramps > MAX_RAMPS or nseg > MAX_SEG or ngrid < 1 or ngrid > MAX_GRID or word(b, 10) > MAX_RBAKE) return error.BadBlock;
    // offsets are words 12..24, then the mood block's (word 25, 0 = none); each block ends where the next begins
    const mood_at = word(b, MOOD_WORD);
    const cps_end = if (mood_at == 0) total else mood_at;
    var t: Track = undefined;
    t.rbake = word(b, 10);
    t.mood = try mood(b, mood_at, total);
    @memcpy(&t.name, b[104..128]);
    t.palette = try block([4]u8, b, word(b, 12), nramps, word(b, 13));
    t.verts = try block(Vert, b, word(b, 13), nv, word(b, 14));
    t.faces = try block(Face, b, word(b, 14), nf, word(b, 15));
    t.inner = try block(Face, b, word(b, 15), ni, word(b, 16));
    t.tile_first = try block(u32, b, word(b, 16), TILES + 1, word(b, 17));
    const nt = t.tile_first[TILES];
    t.tile_faces = try block(u16, b, word(b, 17), nt, word(b, 18));
    t.rays = try block([BUCKETS][RAYS][2]i16, b, word(b, 18), 1, word(b, 19));
    t.pvs_index = try block(u32, b, word(b, 19), TILES * BUCKETS, word(b, 20));
    if (word(b, 21) < word(b, 20)) return error.BadBlock;
    t.pvs = try block(u16, b, word(b, 20), (word(b, 21) - word(b, 20)) / 2, word(b, 21));
    t.line = try block(Seg, b, word(b, 21), nseg, word(b, 22));
    t.grid = try block(Seg, b, word(b, 22), ngrid, word(b, 23));
    t.lr = try block([2]u16, b, word(b, 23), nseg, word(b, 24));
    t.checkpoints = try block(u32, b, word(b, 24), word(b, 11), cps_end);
    try check(&t);
    return t;
}

fn mood(b: []align(4) const u8, at: u32, total: u32) Error!Mood {
    if (at == 0) return .{};
    const m = (try block(Mood, b, at, 1, total))[0];
    if (at + MOOD_SIZE != total) return error.BadMood; // the file's last block
    if (m.ground_ramp >= word(b, 9) or m.ground_level > 7 or m.flags & ~BENCH_ONLY != 0 or m.backdrop >= BACKDROPS) return error.BadMood;
    if (m.clock[0] > MAX_CLOCK[0] or m.clock[1] > MAX_CLOCK[1]) return error.BadMood;
    if (m.haze_strength == 0 and (m.haze_start != 0 or !std.mem.allEqual(u8, &m.haze, 0))) return error.BadMood; // M6: 0 = none
    if (m.draw_r != 0 and (m.draw_r < 3 or m.draw_r > MAX_RBAKE)) return error.BadMood;
    return m;
}

/// Indices the cart will follow blindly are bounded here, once.
fn check(t: *const Track) Error!void {
    for (t.faces) |f| {
        if (f.nv < 3 or f.nv > 4) return error.BadBlock;
        for (f.v[0..f.nv]) |v| if (v >= t.verts.len) return error.BadBlock;
        if (@as(u64, f.inner_first) + f.inner_n > t.inner.len) return error.BadBlock;
    }
    for (t.inner) |f| for (f.v[0..@min(f.nv, 4)]) |v| if (f.nv < 3 or f.nv > 4 or v >= t.verts.len) return error.BadBlock;
    for (t.tile_faces) |f| if (f >= t.faces.len) return error.BadBlock;
    for (t.tile_first[1..], t.tile_first[0..TILES]) |hi, lo| if (hi < lo) return error.BadBlock;
    if (t.line.len < 3) return error.BadBlock;
    for (t.line) |s| if (s.segment & ~LINE_ROOF != 0) return error.BadBlock; // a flag this cart does not know
    for (t.pvs_index) |at| if (at != NOT_BAKED and (at >= t.pvs.len or t.pvs[at] > t.pvs.len - at - 1)) return error.BadBlock;
    for (t.lr) |s| if (s[0] >= t.verts.len or s[1] >= t.verts.len) return error.BadBlock;
    for (t.checkpoints, 0..) |c, i| if (c >= t.line.len or (i > 0 and c <= t.checkpoints[i - 1])) return error.BadBlock;
}
