// --------------------------------------------------------------------------
// The level data: MISSIONS.DAT (301-byte records, read by GET # at 1665) and
// SCRNDATA.DAT (the 51 screen types, BLOADed into bank 6 at 2500). The game
// reads both from its disk; this cart has them built in (assets.zig), and a
// file of the same name on the mounted .zmd takes their place. That is how a
// mission set edited in Tiled (tools/skystrike/levels.py) is played without
// rebuilding the cart: docs/ports/SKYSTRIKE_LEVELS.md.
//
// A disk file of the wrong size is refused LOUDLY (the error trap, 2700):
// the importer validates the contents; the cart only checks what would make
// GET # or BLOAD read past the data.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const assets = @import("assets.zig");
const files = @import("files.zig");

pub const WORLD_LEN: usize = 51;
/// More records than any briefing chain reaches; bounds the RAM a disk costs.
pub const MAX_RECORDS: usize = 64;

var missions_dat: []const u8 = assets.MISSIONS_DAT;
var world_dat: []const u8 = assets.SCRNDATA_DAT;
var loaded: bool = false;
/// Why a disk's level file was refused (shown by the error trap), or null.
pub var err: ?[]const u8 = null;

pub fn missions() []const u8 {
    return missions_dat;
}

pub fn world() []const u8 {
    return world_dat;
}

/// Once per power-on: the disk's MISSIONS.DAT / SCRNDATA.DAT, if it has them.
/// False: one was refused (err says why).
pub fn load() bool {
    if (loaded) return err == null;
    loaded = true;
    const lay = zg.disk.mount() orelse return true; // no disk: the built-in set
    if (zg.disk.find(lay, "MISSIONS.DAT")) |e| {
        if (e.len == 0 or e.len % files.REC != 0 or e.len / files.REC > MAX_RECORDS)
            return fail("MISSIONS.DAT: not 1-64 records of 301 bytes");
        missions_dat = readAll(e) orelse return false;
    }
    if (zg.disk.find(lay, "SCRNDATA.DAT")) |e| {
        if (e.len != WORLD_LEN) return fail("SCRNDATA.DAT: not 51 bytes");
        world_dat = readAll(e) orelse return false;
    }
    return true;
}

fn readAll(e: zg.disk.Entry) ?[]const u8 {
    const buf = zg.mem.alloc(u8, e.len) orelse {
        _ = fail("level file: no RAM for it");
        return null;
    };
    if (zg.disk.read(e, buf) != e.len) {
        _ = fail("level file: the disk ran out");
        return null;
    }
    return buf;
}

fn fail(why: []const u8) bool {
    err = why;
    return false;
}
