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
// OS/desktop — in Zig, C, or Rust — and expose their own app-facing ABI. When
// GEM is cut into its own rom.wasm (Phase 2), its flat app-facing ABI lands in
// rom/sdk/ and the loader wires it like it wires the machine today.
// --------------------------------------------------------------------------
pub const gem = @import("gem/gem.zig");
pub const gui = @import("gem/gui.zig");
// The flat, app-facing ABI lives in rom/sdk/rom.zig and is published as its OWN
// named module, `rom_sdk` — deliberately NOT re-exported here. An app imports
// rom_sdk and never `rom`: .gem/.gui are the ROM's internals and stop being
// reachable once GEM moves into rom.wasm (Phase 2 step 2.2). rom_sdk depends on
// rom, so re-exporting it would also be a module cycle.
