// --------------------------------------------------------------------------
// An open GEMDOS file (docs/KOS_GEMDOS.md §4): its entry, its position, and the cluster the
// position is in (so a sequential read never walks the chain from the start again). A read of at
// least a cache run (4 KB) of whole sectors into a word-aligned buffer goes straight from the drive
// to the caller, contiguous clusters merged into one request of up to 64 sectors: a 32 KB picture
// read whole is one round trip to glass. The rest (stdio's 1 KB reads, a head or tail inside a
// sector, an odd buffer) goes through the drive's cache of 4 KB runs: a round trip per 4 KB.
// --------------------------------------------------------------------------
const fat = @import("fat.zig");
const gd = @import("gemdos_drive.zig");

const S = fat.SECTOR;

pub const File = struct {
    used: bool = false,
    drive: u8 = 0,
    entry: fat.Entry = .{},
    pos: u32 = 0,
    cl: u32 = 0, // the cluster holding byte cl_index * cluster size
    cl_index: u32 = 0,

    pub fn open(f: *File, drive: u8, e: fat.Entry) void {
        f.* = .{ .used = true, .drive = drive, .entry = e, .cl = e.cluster };
    }

    /// Up to dst.len bytes from the position on; the count read (short at the file's end).
    pub fn read(f: *File, d: *gd.Drive, dst: []u8) fat.Error!u32 {
        if (f.pos >= f.entry.size) return 0;
        const want: u32 = @intCast(@min(dst.len, f.entry.size - f.pos));
        const csize = d.vol.spc * S;
        var done: u32 = 0;
        while (done < want) {
            const c = try f.clusterAt(d, f.pos / csize);
            const off = f.pos % csize;
            const sector = d.vol.clusterSector(c) + off / S;
            const out = dst[done..want];
            const k = if (off % S == 0 and out.len >= gd.RUN * S and @intFromPtr(out.ptr) % 4 == 0)
                try f.direct(d, c, sector, out, csize)
            else
                try viaCache(d, sector, off % S, out);
            done += k;
            f.pos += k;
        }
        return done;
    }

    // Whole sectors from `sector` (in cluster `c`) on, through the clusters that follow it on
    // the disk, in one request.
    fn direct(f: *File, d: *gd.Drive, c: u32, sector: u32, out: []u8, csize: u32) fat.Error!u32 {
        const cap: u32 = @intCast(@min(out.len / S, gd.MAX_RUN));
        var n: u32 = @min(cap, (d.vol.clusterSector(c) + d.vol.spc) - sector);
        var last = c;
        var index = f.pos / csize;
        while (n < cap) {
            const nx = (try d.vol.next(last)) orelse break;
            if (nx != last + 1) break;
            last = nx;
            index += 1;
            n = @min(cap, n + d.vol.spc);
        }
        if (!d.readRun(sector, n, @alignCast(out.ptr))) return error.Io;
        f.cl = last; // the request ended in `last` (cluster index `index`)
        f.cl_index = index;
        return n * S;
    }

    fn viaCache(d: *gd.Drive, sector: u32, at: u32, out: []u8) fat.Error!u32 {
        const b = try d.vol.sector(sector);
        const k: u32 = @intCast(@min(out.len, S - at));
        @memcpy(out[0..k], b[at..][0..k]);
        return k;
    }

    // The cluster of the file's `index`-th cluster, walked from the one remembered, else the first.
    fn clusterAt(f: *File, d: *gd.Drive, index: u32) fat.Error!u32 {
        if (index < f.cl_index) {
            f.cl = f.entry.cluster;
            f.cl_index = 0;
        }
        var hops: u32 = 0;
        while (f.cl_index < index) {
            f.cl = (try d.vol.next(f.cl)) orelse return error.Corrupt; // shorter than its size
            f.cl_index += 1;
            hops += 1;
            if (hops > d.vol.clusters) return error.Corrupt; // a chain that loops
        }
        return f.cl;
    }
};
