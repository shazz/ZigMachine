// --------------------------------------------------------------------------
// GEM 5's program API, the ITEM SELECTOR's folders (system table 1.18; rom_app.zig has
// fileSelSetName): the Directory: line is a path spec the user moves (a folder row, the
// close box, the line edited), fileSelProcess answers `relist` with the list emptied, and
// the program reads the spec here to add that folder's names again (filesel.zig).
// --------------------------------------------------------------------------
const main = @import("rom_main.zig");

/// The selector's path spec (`C:\NET\*.TXT`) into the caller's buffer; its length (0: a bad
/// handle or no room). The program provides the storage, as fileSelChosen.
export fn fileSelSpec(h: u32, out: u32, out_cap: u32) u32 {
    const f = main.fselAt(h) orelse return 0;
    const s = f.spec();
    if (s.len == 0 or out == 0 or out_cap < s.len) return 0;
    const dst: [*]u8 = @ptrFromInt(out);
    @memcpy(dst[0..s.len], s);
    return @intCast(s.len);
}
