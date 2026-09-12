// --------------------------------------------------------------------------
// The ROM — ZigMachine reference system software.
//
// Currently the GEM desktop + its GUI toolkit. Apps link this as the `rom`
// named module (@import("rom")). Layer position: machine < libs/zig < ROM < apps
// — the ROM uses ZigOS helpers (@import("zigos")) and the HW ABI, and apps sit
// on top of it.
//
// This is our REFERENCE ROM. The machine/rom split is a real seam: a ROM is a
// module linked against the HW ABI (machine/sdk/), so anyone can write their own
// OS/desktop — in Zig, C, or Rust — and expose their own app-facing ABI.
//
// That seam is REAL as of 2026-09-12: GEM is its own rom.wasm (rom/rom_main.zig)
// in its own RAM window, wired by the loader the way the machine is, and a C
// program draws GEM widgets through it (apps/c/hello.c). This file is what the
// chip links; rom/sdk/rom.zig is what an app links.
// --------------------------------------------------------------------------
pub const gem = @import("gem/gem.zig");
pub const gui = @import("gem/gui.zig");
// The flat, app-facing ABI lives in rom/sdk/rom.zig and is published as its OWN
// named module, `rom_sdk` — deliberately NOT re-exported here. An app imports
// rom_sdk and never `rom`: .gem/.gui are the ROM's internals and are NOT reachable
// from an app any more — they live in a different wasm module. rom_sdk depends on
// rom, so re-exporting it here would also be a module cycle.
