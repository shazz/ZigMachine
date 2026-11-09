// --------------------------------------------------------------------------
// DESKTOP.INF on a real disk (docs/GEM5_PLAN.md P1.2). The ROM's Save Desktop writes the
// text into its own buffer (deskInfPtr/deskInfLen) and reports `.save_inf`; only a cart can
// reach a disk, so the shell writes it to C:\DESKTOP.INF through KOS GEMDOS (the card's /HD
// on the board, the ?c= image on the page) and reads it back at every start: a boot, and the
// shell's return after each program (it is re-instantiated). Before this nothing was ever
// written anywhere but the ROM's memory, so the next start found nothing (Matt on the board,
// 9 Nov: "save desktop works but not read at start"). Without a C: (the page with no ?c=) a
// boot disk's own DESKTOP.INF (a .zmd's) is still read; there is nowhere to save one.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const rom = @import("rom_sdk");
const gemdos = @import("kos_gemdos");

pub const PATH_C = "C:\\DESKTOP.INF";
pub const MAX = 512; // rom/gem/desktop/deskinf.zig MAX_BYTES

/// DESKTOP.INF at a start: C:'s (Save Desktop's), else the boot disk's; null when neither has one.
pub fn read(buf: *[MAX]u8) ?[]const u8 {
    if (readC(buf)) |text| return text;
    const lay = zg.disk.mount() orelse return null;
    const ent = zg.disk.find(lay, "DESKTOP.INF") orelse return null;
    return buf[0..zg.disk.read(ent, buf)];
}

fn readC(buf: *[MAX]u8) ?[]const u8 {
    const dos = gemdos.dos();
    const h = dos.Fopen(PATH_C, 0); // no C: (no card, no image): EDRIVE / EPTHNF
    if (h < 0) return null;
    const n = dos.Fread(h, MAX, buf);
    _ = dos.Fclose(h);
    if (n <= 0) return null;
    return buf[0..@intCast(n)];
}

/// Save Desktop: the ROM's DESKTOP.INF onto C:\. 0, or GEMDOS's error (no C:: EDRIVE -46;
/// a full or failed card: EWRITF -10; Fwrite short: EWRITF too). The ROM keeps its copy and
/// lists the file either way; a failure is logged, the desktop has no alert to raise for it.
pub fn writeC() i32 {
    const len = rom.deskInfLen();
    if (len == 0 or len > MAX) return -10;
    const text: [*]const u8 = @ptrFromInt(rom.deskInfPtr());
    const dos = gemdos.dos();
    const h = dos.Fcreate(PATH_C, 0);
    if (h < 0) return logged(h);
    const w = dos.Fwrite(h, @intCast(len), text);
    const c = dos.Fclose(h); // the save itself (KOS_GEMDOS_WRITES §2: the commit is at Fclose)
    if (w < 0) return logged(w);
    if (w != len) return logged(-10);
    return logged(c);
}

fn logged(code: i32) i32 {
    if (code < 0) zg.Console.log("GEM: Save Desktop could not write C:\\DESKTOP.INF, GEMDOS {d}", .{code});
    return code;
}
