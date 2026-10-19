// --------------------------------------------------------------------------
// Stable palette entries for the layer keys (layers.zig): walking an image's
// rows in order, a key present on the row above keeps its entry and a new key
// takes the lowest free one, so the HBL for a row has only the new keys to
// write. Entries are 1..POOL; a row never holds more keys than that (61
// measured), so a free entry always exists for a new key.
// --------------------------------------------------------------------------
const L = @import("layers.zig");

pub const INK_TAG: u16 = 1024; // ink keys share the key space above the 10-bit layer keys
const NONE: u16 = 0xFFFF;

pub const Assign = struct {
    owner: [L.POOL + 1]u16 = @splat(NONE), // entry -> key
    entry_of: [2048]u8 = @splat(0), // key -> entry, 0: none
    seen: [2048]u8 = @splat(0), // == gen: the key is on this row
    gen: u8 = 0,

    pub fn nextRow(self: *Assign) void {
        self.gen +%= 1;
        if (self.gen == 0) {
            self.seen = @splat(0);
            self.gen = 1;
        }
    }
};

/// Records key `k` as on this row, once; false when `keys` is full.
pub fn note(a: *Assign, keys: []u16, nk: *usize, k: u16) bool {
    if (a.seen[k] == a.gen) return true;
    if (nk.* == keys.len) return false;
    a.seen[k] = a.gen;
    keys[nk.*] = k;
    nk.* += 1;
    return true;
}

/// Entries for this row's keys, listing the new no-ink keys first.
pub fn assign(a: *Assign, keys: []const u16, rk: *L.RowKeys) bool {
    for (a.owner[1..]) |*k| {
        if (k.* != NONE and a.seen[k.*] != a.gen) {
            a.entry_of[k.*] = 0;
            k.* = NONE;
        }
    }
    rk.n_all = 0;
    rk.n_ink = 0;
    var next: usize = 1;
    for (keys) |k| {
        if (a.entry_of[k] != 0) continue;
        while (a.owner[next] != NONE) next += 1;
        if (next > L.POOL) return false;
        a.owner[next] = k;
        a.entry_of[k] = @intCast(next);
        if (k < INK_TAG and !push(rk, k, a.entry_of[k])) return false;
    }
    rk.n_new = rk.n_all;
    for (keys) |k| {
        if (k >= INK_TAG) {
            if (rk.n_ink == L.MAX_INK) return false;
            rk.ink_entry[rk.n_ink] = a.entry_of[k];
            rk.ink_key[rk.n_ink] = @intCast(k - INK_TAG);
            rk.n_ink += 1;
        } else if (!isNew(rk, a.entry_of[k]) and !push(rk, k, a.entry_of[k])) return false;
    }
    return true;
}

fn push(rk: *L.RowKeys, k: u16, e: u8) bool {
    if (rk.n_all == L.MAX_NI) return false;
    rk.ni_entry[rk.n_all] = e;
    rk.ni_key[rk.n_all] = k;
    rk.n_all += 1;
    return true;
}

fn isNew(rk: *const L.RowKeys, e: u8) bool {
    for (rk.ni_entry[0..rk.n_new]) |x| if (x == e) return true;
    return false;
}
