// --------------------------------------------------------------------------
// Wavefront OBJ loader (open ZigOS util).
//
// Parses the subset of OBJ that low-poly models use: `v x y z` vertices and
// `f a b c ...` faces (with optional `a/vt/vn` slashes — only the vertex index
// is used). Polygons are triangulated with a simple fan. The mesh is recentred
// and scaled to fit a unit sphere so any model displays at a consistent size.
//
// Runtime parse into fixed-capacity storage (no allocator on this machine).
// Feed it an @embedFile'd .obj; see apps/scenes/obj_demo.zig.
// --------------------------------------------------------------------------
const std = @import("std");

pub const MAX_VERTS: u16 = 2048;
pub const MAX_FACES: u16 = 4096;

pub const Vec3 = struct { x: f32 = 0, y: f32 = 0, z: f32 = 0 };
pub const Face = struct { a: u16, b: u16, c: u16 };

pub const Mesh = struct {
    verts: [MAX_VERTS]Vec3 = undefined,
    nverts: u16 = 0,
    faces: [MAX_FACES]Face = undefined,
    nfaces: u16 = 0,

    pub fn load(self: *Mesh, text: []const u8) void {
        self.nverts = 0;
        self.nfaces = 0;
        var lines = std.mem.tokenizeScalar(u8, text, '\n');
        while (lines.next()) |raw| self.line(raw);
        self.normalize();
    }

    fn line(self: *Mesh, raw: []const u8) void {
        var toks = std.mem.tokenizeAny(u8, raw, " \t\r");
        const kind = toks.next() orelse return;
        if (std.mem.eql(u8, kind, "v")) {
            self.addVertex(&toks);
        } else if (std.mem.eql(u8, kind, "f")) {
            self.addFace(&toks);
        }
    }

    fn addVertex(self: *Mesh, toks: *std.mem.TokenIterator(u8, .any)) void {
        if (self.nverts >= MAX_VERTS) return;
        self.verts[self.nverts] = .{
            .x = nextF32(toks),
            .y = nextF32(toks),
            .z = nextF32(toks),
        };
        self.nverts += 1;
    }

    fn addFace(self: *Mesh, toks: *std.mem.TokenIterator(u8, .any)) void {
        var idx: [16]u16 = undefined;
        var n: usize = 0;
        while (toks.next()) |t| {
            if (n >= idx.len) break;
            const end = std.mem.indexOfScalar(u8, t, '/') orelse t.len;
            const vi = std.fmt.parseInt(i32, t[0..end], 10) catch continue;
            if (vi < 1) continue; // no negative/relative index support
            idx[n] = @intCast(vi - 1); // OBJ is 1-indexed
            n += 1;
        }
        var k: usize = 1;
        while (k + 1 < n) : (k += 1) { // fan triangulation
            if (self.nfaces >= MAX_FACES) return;
            self.faces[self.nfaces] = .{ .a = idx[0], .b = idx[k], .c = idx[k + 1] };
            self.nfaces += 1;
        }
    }

    // Recentre on the bounding-box centre and scale so the furthest vertex sits
    // at radius 1 — models of any original size/offset render the same.
    fn normalize(self: *Mesh) void {
        if (self.nverts == 0) return;
        var lo = self.verts[0];
        var hi = self.verts[0];
        for (self.verts[0..self.nverts]) |v| {
            lo = .{ .x = @min(lo.x, v.x), .y = @min(lo.y, v.y), .z = @min(lo.z, v.z) };
            hi = .{ .x = @max(hi.x, v.x), .y = @max(hi.y, v.y), .z = @max(hi.z, v.z) };
        }
        const cx = (lo.x + hi.x) * 0.5;
        const cy = (lo.y + hi.y) * 0.5;
        const cz = (lo.z + hi.z) * 0.5;
        var r: f32 = 0.0001;
        for (self.verts[0..self.nverts]) |v| {
            const dx = v.x - cx;
            const dy = v.y - cy;
            const dz = v.z - cz;
            r = @max(r, @sqrt(dx * dx + dy * dy + dz * dz));
        }
        const s = 1.0 / r;
        for (self.verts[0..self.nverts]) |*v| {
            v.x = (v.x - cx) * s;
            v.y = (v.y - cy) * s;
            v.z = (v.z - cz) * s;
        }
    }
};

fn nextF32(toks: *std.mem.TokenIterator(u8, .any)) f32 {
    const t = toks.next() orelse return 0;
    return std.fmt.parseFloat(f32, t) catch 0;
}

// --------------------------------------------------------------------------
// Wireframes, parsed at COMPTIME: `v x y z` vertices and `l a b c ...`
// polylines (each consecutive pair is one edge, in file order). Vertices are
// kept exactly as written: no recentring, so a scene's hand-tuned coordinates
// survive bit for bit. Faces are ignored here. Nothing lands in the cart but
// the arrays the scene actually references: the text itself stays at comptime.
//
//   const logo = obj.parseWire(@embedFile("../assets/obj/empire_logo.obj"));
// --------------------------------------------------------------------------
pub const Edge = [2]u16;

pub fn Wire(comptime nverts: usize, comptime nedges: usize) type {
    return struct {
        verts: [nverts][3]f32,
        edges: [nedges]Edge,
    };
}

fn wireCounts(comptime text: []const u8) [2]usize {
    @setEvalBranchQuota(1_000_000);
    var nv: usize = 0;
    var ne: usize = 0;
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        var toks = std.mem.tokenizeAny(u8, raw, " \t\r");
        const kind = toks.next() orelse continue;
        if (std.mem.eql(u8, kind, "v")) nv += 1;
        if (std.mem.eql(u8, kind, "l")) {
            var n: usize = 0;
            while (toks.next()) |_| n += 1;
            if (n < 2) @compileError("obj: an `l` record needs at least 2 indices");
            ne += n - 1;
        }
    }
    return .{ nv, ne };
}

pub fn parseWire(comptime text: []const u8) Wire(wireCounts(text)[0], wireCounts(text)[1]) {
    return comptime parseWireAt(text);
}

fn parseWireAt(comptime text: []const u8) Wire(wireCounts(text)[0], wireCounts(text)[1]) {
    @setEvalBranchQuota(1_000_000);
    const R = Wire(wireCounts(text)[0], wireCounts(text)[1]);
    var out: R = undefined;
    var nv: usize = 0;
    var ne: usize = 0;
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        var toks = std.mem.tokenizeAny(u8, raw, " \t\r");
        const kind = toks.next() orelse continue;
        if (std.mem.eql(u8, kind, "v")) {
            for (&out.verts[nv]) |*c| c.* = wireFloat(toks.next());
            nv += 1;
        } else if (std.mem.eql(u8, kind, "l")) {
            var prev = wireIndex(toks.next(), out.verts.len);
            while (toks.next()) |t| {
                const cur = wireIndex(t, out.verts.len);
                out.edges[ne] = .{ prev, cur };
                ne += 1;
                prev = cur;
            }
        }
    }
    return out;
}

fn wireFloat(tok: ?[]const u8) f32 {
    const t = tok orelse @compileError("obj: `v` record needs x y z");
    return std.fmt.parseFloat(f32, t) catch @compileError("obj: bad float '" ++ t ++ "'");
}

// OBJ indices are 1-based; a vertex index must name a vertex of the file.
fn wireIndex(tok: ?[]const u8, nverts: usize) u16 {
    const t = tok orelse unreachable;
    const end = std.mem.indexOfScalar(u8, t, '/') orelse t.len;
    const vi = std.fmt.parseInt(u16, t[0..end], 10) catch @compileError("obj: bad index '" ++ t ++ "'");
    if (vi < 1 or vi > nverts) @compileError("obj: index out of range '" ++ t ++ "'");
    return vi - 1;
}
