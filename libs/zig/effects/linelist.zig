// --------------------------------------------------------------------------
// Line list (HW 1.10.0, fpga/review/COPPER_LINEBASE.md): the STE line-list screen
// as a copper list. Each raster line names where its pixels come from (the video
// counter $FF8205/07/09 an STE kernel rewrites in the border), a fine scroll
// ($FF8264) and colour 0 ($FF8240); the machine applies them before the line, so
// a distorter, wobble, flip or line zoom costs the CPU one table a frame and no
// pixel copy.
//
// The scene fills one Line per raster row it covers, from `first_row`; build()
// writes the plane's list, only the words that change:
//   - LBASE when the line does not follow on from the line above (base != the
//     previous base + stride: the counter runs on by itself);
//   - REG HSCROLL when the scroll changes (the register keeps it between lines
//     AND frames, so the first line always writes it);
//   - PAL colour_entry when the colour changes (first line always);
//   - FLICK on every line with .flicker (open borders with no HBL handler).
// Bases are region byte offsets in VRAM (LogicalFB.lineAddr, zg.vramWords().off);
// one outside VRAM stops the list on the machine.
//
// Generic over the register offset so it has no ZigOS import and tests natively
// (linelist_test.zig); zigos.zig instantiates it as `zg.linelist`.
// --------------------------------------------------------------------------

pub const Line = struct {
    base: u32, // region byte offset of the line's first byte (logical column 0)
    hscroll: u16 = 0, // byte (= pixel) offset added to it
    colour: u32 = 0, // RGBA for colour_entry
};

pub const Options = struct {
    plane: u8, // the plane whose list this is (REG HSCROLL names its register)
    stride: u32, // the plane's FB_STRIDE: how the counter runs on between lines
    first_row: u16 = 0, // raster line of lines[0] (0 for an overscan plane)
    flicker: bool = false,
    hscroll: bool = true, // false: never write HSCROLL (the plane keeps what it has)
    colour_entry: ?u8 = 0, // null: no colour raster
};

pub const MAX_WORDS_PER_LINE = 6; // HEAD, FLICK, LBASE, REG, PAL + colour

/// The list buffer `rows` lines need (LogicalFB.copperList(words(rows))).
pub fn words(rows: usize) usize {
    return rows * MAX_WORDS_PER_LINE + 1;
}

pub fn LineList(comptime reg_hscroll: u8) type {
    return struct {
        /// Write `lines` into `l` as copper records; the words used, or error.ListTooSmall
        /// (nothing written) when `l` is shorter than words(lines.len).
        pub fn build(l: []u32, lines: []const Line, o: Options) error{ListTooSmall}!usize {
            if (l.len < words(lines.len) or @as(usize, o.first_row) + lines.len > 280) return error.ListTooSmall;
            var w: usize = 0;
            for (lines, 0..) |ln, i| {
                const first = i == 0;
                const prev = if (first) ln else lines[i - 1];
                const lbase = first or ln.base != prev.base +% o.stride;
                const hs = o.hscroll and (first or ln.hscroll != prev.hscroll);
                const col = o.colour_entry != null and (first or ln.colour != prev.colour);
                const n: u32 = @as(u32, @intFromBool(o.flicker)) + @intFromBool(lbase) + @intFromBool(hs) +
                    2 * @as(u32, @intFromBool(col));
                if (n == 0) continue;
                const row: u32 = @as(u32, o.first_row) + @as(u32, @intCast(i));
                put(l, &w, 0xF000_0000 | row << 19 | n);
                if (o.flicker) put(l, &w, 0x3000_0000);
                if (lbase) put(l, &w, 0x5000_0000 | @as(u32, @min(ln.base, 0x0FFF_FFFF))); // past 28 bits: refused, never aliased
                if (hs) put(l, &w, 0x2000_0000 | @as(u32, reg_hscroll + 2 * o.plane) << 20 | ln.hscroll);
                if (col) {
                    put(l, &w, 0x1000_0000 | @as(u32, o.colour_entry.?) << 20 | 1 << 12);
                    put(l, &w, ln.colour);
                }
            }
            put(l, &w, 0xF000_0000 | 511 << 19);
            return w;
        }

        // A word already right is not stored again: on the board every store is a bus write.
        inline fn put(l: []u32, w: *usize, v: u32) void {
            if (l[w.*] != v) l[w.*] = v;
            w.* += 1;
        }
    };
}
