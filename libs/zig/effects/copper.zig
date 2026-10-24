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
/// `hblLinesArePhysical() bool`, `setFrameBufferHBLHandlerPure(pos, handler)` (copper.hbl is pure:
/// own palette + flicker), `clearFrameBufferHBLHandler()`, `copperList(words) ?[]u32` and
/// `copperBuffer() ?[]u32` (HW 1.9.0: the list the machine applies itself; endFrame builds it).
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
            // A list the machine applies itself (HW 1.9.0), built by endFrame(); else the handler.
            fb.setFrameBufferHBLHandlerPure(if (opts.flicker) g.magic_x else 0, hbl);
            if (fb.copperList(LIST_WORDS) != null) fb.clearFrameBufferHBLHandler();
        }

        // A list: per row a HEAD, a FLICK, and a PAL op + its word per slot that changed.
        pub const LIST_WORDS = g.rows * (2 + 2 * MAX_SLOTS) + 1;

        /// After the scene's frame (demo_main.zig): each plane with a published list gets this
        /// frame's tables as copper records (machine/copper.zig): its first covered row writes every
        /// slot, the others the slots whose colour changed from the row above (what hbl's dedupe
        /// leaves the palette holding), FLICK on every row with .flicker. Only words that differ
        /// from last frame's list are stored: on the board every store is a bus write.
        pub fn endFrame(os: *OS) void {
            for (&os.lfbs) |*fb| {
                const l = fb.copperBuffer() orelse continue;
                if (used[fb.id] != 0) build(fb, l);
            }
        }

        fn build(fb: *FB, l: []u32) void {
            const id = fb.id;
            const phys = fb.hblLinesArePhysical();
            const lo: usize = if (phys) 0 else g.visible_top;
            const hi: usize = if (phys) g.rows else g.visible_top + g.visible_rows;
            var w: usize = 0;
            var row = lo;
            while (row < hi) : (row += 1) {
                var n: u32 = @intFromBool(flicker[id]);
                for (0..used[id]) |s| n += 2 * @as(u32, @intFromBool(row == lo or bank[id][s][row] != bank[id][s][row - 1]));
                if (n == 0) continue;
                put(l, &w, 0xF000_0000 | @as(u32, @intCast(row)) << 19 | n);
                if (flicker[id]) put(l, &w, 0x3000_0000);
                for (0..used[id]) |s| {
                    if (row != lo and bank[id][s][row] == bank[id][s][row - 1]) continue;
                    put(l, &w, 0x1000_0000 | @as(u32, entries[id][s]) << 20 | 1 << 12);
                    put(l, &w, bank[id][s][row]);
                }
            }
            put(l, &w, 0xF000_0000 | 511 << 19);
        }

        inline fn put(l: []u32, w: *usize, v: u32) void {
            if (l[w.*] != v) l[w.*] = v;
            w.* += 1;
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
            // A register that already holds the colour is not rewritten: on the
            // board every store is a bus write (write-through D-cache), a load is not.
            for (entries[id][0..used[id]], 0..) |e, s| {
                const c = bank[id][s][row];
                if (fb.palette[e] != c) fb.palette[e] = c;
            }
        }
    };
}
