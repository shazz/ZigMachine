// --------------------------------------------------------------------------
// KOS GEMDOS for C carts (docs/KOS_GEMDOS.md §5): the calls under TOS's names with C linkage, built
// as one wasm object a C cart links (apps/ports/kestrel_sdl2/include/kestrel_gemdos.h declares them;
// apps/ports/grafx2/Makefile builds it). The cart's own POSIX layer (kestrel_sdl2/src/opt/
// kestrel_wasi_c.c) is written over these, so fopen("/C/PICTURES/X.PI1") is GEMDOS underneath.
// Arguments in TOS's order; every int is 32 bits (wasm32's C ABI).
// --------------------------------------------------------------------------
const std = @import("std");
const cart = @import("gemdos_cart.zig");

fn str(p: [*:0]const u8) []const u8 {
    return std.mem.sliceTo(p, 0);
}

export fn Dgetdrv() i32 {
    return cart.dos().Dgetdrv();
}
export fn Dsetdrv(d: i32) i32 {
    return cart.dos().Dsetdrv(d);
}
export fn Dgetpath(buf: [*]u8, drv: i32) i32 {
    return cart.dos().Dgetpath(buf[0..128], drv); // TOS: the buffer holds 128 bytes
}
export fn Dsetpath(path: [*:0]const u8) i32 {
    return cart.dos().Dsetpath(str(path));
}
export fn Fopen(path: [*:0]const u8, mode: i32) i32 {
    return cart.dos().Fopen(str(path), mode);
}
export fn Fclose(h: i32) i32 {
    return cart.dos().Fclose(h);
}
export fn Fread(h: i32, count: i32, buf: [*]u8) i32 {
    return cart.dos().Fread(h, count, buf);
}
export fn Fseek(offset: i32, h: i32, mode: i32) i32 {
    return cart.dos().Fseek(offset, h, mode);
}
export fn Fattrib(path: [*:0]const u8, wflag: i32, attr: i32) i32 {
    return cart.dos().Fattrib(str(path), wflag, attr);
}
export fn Fsetdta(dta: *cart.Dta) void {
    cart.dos().Fsetdta(dta);
}
export fn Fgetdta() *cart.Dta {
    return cart.dos().Fgetdta();
}
export fn Fsfirst(spec: [*:0]const u8, attr: i32) i32 {
    return cart.dos().Fsfirst(str(spec), attr);
}
export fn Fsnext() i32 {
    return cart.dos().Fsnext();
}
/// Not TOS: A: forgets its disk (KOS's media count moved); the round trips a drive made (the cost
/// proofs).
export fn Kgemdos_media_a() void {
    cart.mediaChangeA();
}
export fn Kgemdos_trips(drive: i32) u32 {
    return cart.trips(@intCast(drive & 0xFF));
}
