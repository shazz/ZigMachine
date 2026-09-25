// --------------------------------------------------------------------------
// The colour list (DATA $29DB2) and VBL handler 2's walk along it (TEXT $4F2,
// $76E). The whole text effect -- the per-row cycling, the centre-out reveal,
// the fades, the invisible page swaps -- is this one sliding window: every VBL
// the pointer moves one entry, and the next 128 entries become palette
// 128-255. A text pixel is 128 + hump value v, so it shows entry n+1+v.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");

pub const WINDOW = 128;

fn entry(i: usize) u32 {
    return assets.long(assets.colours, i);
}
/// tst.w d0 / bpl: a negative low word is a marker.
fn isMarker(v: u32) bool {
    return v & 0x8000 != 0;
}
fn isPageMarker(v: u32) bool {
    return v & 0xFFFF == 0xFFFE;
}

/// The long at $29DAE, as an entry index.
pub const List = struct {
    p: u32,

    pub fn reset(self: *List) void {
        self.p = 0;
    }

    /// One VBL. Steps past one colour; a $FFFE on the way sets the page flag
    /// ($5CD7D) and takes the next entry as well; $FFFF sends the pointer back
    /// to the start and consumes nothing that VBL. True when a page is due.
    pub fn advance(self: *List) bool {
        var page = false;
        while (true) {
            const v = entry(self.p);
            self.p += 1;
            if (!isMarker(v)) return page;
            if (isPageMarker(v)) {
                page = true;
                continue;
            }
            self.p = 0;
            return page;
        }
    }

    /// $76E: the next 128 non-marker entries from the pointer, wrapping at $FFFF.
    pub fn window(self: *const List, out: *[WINDOW]u32) void {
        var p = self.p;
        var k: usize = 0;
        while (k < WINDOW) {
            var v = entry(p);
            p += 1;
            if (isMarker(v)) {
                if (isPageMarker(v)) continue;
                p = 0;
                v = entry(p);
                p += 1;
            }
            out[k] = v;
            k += 1;
        }
    }
};

comptime {
    // The list ends in $FFFF, so neither walk can run off it.
    if (entry(assets.COLOURS - 1) & 0xFFFF != 0xFFFF) @compileError("the colour list must end with $FFFF");
    if (isMarker(entry(0))) @compileError("the restart entry must be a colour");
}
