// --------------------------------------------------------------------------
// Copper: per-line palette tables, played back by one HBL handler per plane.
//
// A scene fills a table of colours per scanline for up to MAX_SLOTS palette
// entries; the handler writes them before each line is composited. That is the
// raster-bar / gradient-ink trick a dozen scenes hand-wrote, each with its own
// module-scope arrays and its own guess at the line numbering.
//
// Tables are ALWAYS indexed by PHYSICAL row (0 = top of the top border). The
// machine hands a per-plane handler LOGICAL lines 0..199 on a normal, scroll or
// medium plane, but PHYSICAL lines 0..279 on an overscan, fullscreen or
// full-raster medium plane (machine/video.zig). The handler asks the plane which
// on every call, so calling setOverscanBuffer() before or after install() cannot
// shift a raster by 40 rows.
//
// The SCENE owns the tables (a module-scope `[n][rows]u32`, n = the entries it
// drives). Library-owned tables for every plane and slot would cost ~18 KB in
// every cart that imports this: the cart link materialises uninitialised
// module-scope arrays as zero bytes in the data segment, `undefined` or not.
// HBL handlers take no user pointer, so the library keeps only a pointer and
// the entry list per plane.
//
// Generic over the plane type so it has no ZigOS import and tests natively
// (copper_test.zig). zigos.zig instantiates it as `zg.copper`.
// --------------------------------------------------------------------------

pub const Geometry = struct {
    nb_planes: usize,
    rows: usize, // physical rows (280)
    visible_top: usize, // first visible physical row (40)
    visible_rows: usize, // 200
    magic_x: u16, // OVERSCAN_MAGIC_X
};

/// `FB` needs: `id: u8`, `palette: [*]u32`, `flickerBorder()`,
/// `hblLinesArePhysical() bool` and `setFrameBufferHBLHandler(pos, handler)`.
pub fn Copper(comptime FB: type, comptime OS: type, comptime g: Geometry) type {
    if (g.visible_top + g.visible_rows > g.rows) @compileError("copper: visible band outside the raster");
    return struct {
        pub const MAX_SLOTS = 4;
        pub const Slot = u2; // cannot name a slot past MAX_SLOTS
        pub const Table = [g.rows]u32;

        var bank: [g.nb_planes][*]Table = undefined;
        var entries: [g.nb_planes][MAX_SLOTS]u8 = undefined;
        var used: [g.nb_planes]u8 = [_]u8{0} ** g.nb_planes;
        var flicker: [g.nb_planes]bool = [_]bool{false} ** g.nb_planes;
        // What table() hands back for a slot that was never installed: written,
        // never played, so a wrong slot is a no-op rather than a stray write.
        var scratch: Table = undefined;

        pub const Options = struct {
            /// Also open every border: flickerBorder() on every line, with the
            /// handler registered at the magic column the trick needs.
            flicker: bool = false,
        };

        /// Drive `palette_entries` (slot i = entry palette_entries[i]) on `fb`
        /// from `storage` (one table per entry, module scope in the scene).
        /// Every row starts as the entry's current colour, so an untouched table
        /// changes nothing on screen.
        pub fn install(fb: *FB, comptime palette_entries: []const u8, storage: *[palette_entries.len]Table, opts: Options) void {
            if (palette_entries.len == 0 or palette_entries.len > MAX_SLOTS)
                @compileError("copper.install: 1 to 4 palette entries");
            const id = fb.id;
            bank[id] = storage;
            flicker[id] = opts.flicker;
            for (palette_entries, 0..) |e, s| {
                entries[id][s] = e;
                @memset(&storage[s], fb.palette[e]);
            }
            used[id] = palette_entries.len;
            fb.setFrameBufferHBLHandler(if (opts.flicker) g.magic_x else 0, hbl);
        }

        /// Slot `slot`'s colours (RGBA as the palette stores them), one per
        /// PHYSICAL row.
        pub fn table(fb: *const FB, slot: Slot) *Table {
            if (slot >= used[fb.id]) return &scratch;
            return &bank[fb.id][slot];
        }

        /// The visible band of the same table: index 0 is visible line 0.
        pub fn visible(fb: *const FB, slot: Slot) *[g.visible_rows]u32 {
            return table(fb, slot)[g.visible_top..][0..g.visible_rows];
        }

        /// The physical row a handler `line` is on, given the plane's mode.
        pub fn physicalRow(lines_are_physical: bool, line: u16) usize {
            return if (lines_are_physical) line else @as(usize, line) + g.visible_top;
        }

        pub fn hbl(fb: *FB, _: *OS, line: u16, _: u16) void {
            const id = fb.id;
            if (flicker[id]) fb.flickerBorder();
            const row = physicalRow(fb.hblLinesArePhysical(), line);
            if (row >= g.rows) return;
            for (entries[id][0..used[id]], 0..) |e, s| fb.palette[e] = bank[id][s][row];
        }
    };
}
