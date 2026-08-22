// --------------------------------------------------------------------------
// ZigMachine — memory map (THE ABI)
//
// This file is the single source of truth for the sealed hardware's memory
// layout. Both the sealed machine (machine/video.zig) and the SDK header the
// coder receives (sdk/hardware.zig) derive their addresses from here, so the
// two can never disagree. Changing a value here is an ABI change.
//
// Layer: this is machine-side data, but it is pure constants (no code, no
// extern/export), so it is safe for both the sealed binary and the open SDK to
// import without entangling their symbol tables.
// --------------------------------------------------------------------------

// --- geometry (fixed; the console's identity) ---
pub const PHYSICAL_WIDTH: u16 = 400;
pub const PHYSICAL_HEIGHT: u16 = 280;
pub const WIDTH: u16 = 320;
pub const HEIGHT: u16 = 200;
pub const NB_PLANES: u8 = 4;
pub const HORIZONTAL_BORDERS_WIDTH: u16 = (PHYSICAL_WIDTH - WIDTH) / 2; // 40
pub const VERTICAL_BORDERS_HEIGHT: u16 = (PHYSICAL_HEIGHT - HEIGHT) / 2; // 40

// --- sizes ---
pub const PAL_ENTRIES: usize = 256;
pub const PAL_BYTES: usize = PAL_ENTRIES * 4; // 1024 (RGBA u32 per entry)
pub const LFB_BYTES: usize = @as(usize, WIDTH) * @as(usize, HEIGHT); // 64000
pub const PFB_PIXELS: usize = @as(usize, PHYSICAL_WIDTH) * @as(usize, PHYSICAL_HEIGHT); // 112000
pub const PFB_BYTES: usize = PFB_PIXELS * 4; // 448000

// --- region layout (offsets from the video hardware base) ---
pub const OFF_REG: usize = 0x0000;
pub const OFF_PAL: usize = 0x0100; // 4 x PAL_BYTES
pub const OFF_LFB: usize = 0x1100; // 4 x LFB_BYTES
pub const OFF_PFB: usize = OFF_LFB + NB_PLANES * LFB_BYTES; // 260352
pub const REGION_BYTES: usize = OFF_PFB + PFB_BYTES; // 708352

// --- registers (offsets from OFF_REG) ---
pub const REG_RESOLUTION: usize = 0x00; // u8   0 = planes, 1 = truecolor (border-open)
pub const REG_NB_PLANES: usize = 0x01; // u8   (ro) = 4
pub const REG_BACKGROUND: usize = 0x04; // u32  border/background RGBA
pub const REG_PLANE_ENABLE: usize = 0x08; // u8 x4 (informational in v1; host gates blits)
pub const REG_GLOBAL_HBL_ID: usize = 0x10; // u16  border/background HBL handler id (0 = none)
pub const REG_FB_HBL_ID: usize = 0x20; // u16 x4 per-plane HBL handler id (0 = none)
pub const REG_FB_HBL_POS: usize = 0x28; // u16 x4 x position at which the per-plane HBL fires
pub const REG_FRAME: usize = 0x30; // u32  (ro) frame counter

pub const RES_PLANES: u8 = 0;
pub const RES_TRUECOLOR: u8 = 1;

// HBL dispatch ids. Per-plane handlers use id = plane + 1 (1..4); the global
// border/background handler uses a distinct id. Only integer ids cross the
// sealed boundary — the machine never sees a Zig function pointer.
pub const HBL_GLOBAL_ID: u16 = 5;

// --------------------------------------------------------------------------
// Reserved hardware address space.
//
// The video region is NOT a linker-allocated array in either module. It lives
// at a fixed linear-memory address ABOVE both modules' static data + stacks, so
// the two wasm modules can share ONE WebAssembly.Memory with no collision. The
// machine reads/writes it; the demo writes framebuffers/registers into it. This
// is the "you get the memory map, not the schematics" contract, and it gives
// the authentic fixed-address feel the spec's §10 asks about.
//
// Layout of the 48-page (3 MiB) shared memory:
//   [0x000000 .. 0x100000)  machine module data + stack  (global-base 0x400)
//   [0x100000 .. 0x200000)  demo module data + stack     (global-base 0x100000)
//   [0x200000 .. 0x2AD000)  video hardware region        (this base)
// --------------------------------------------------------------------------
pub const HW_VIDEO_BASE: usize = 0x200000; // 2 MiB
pub const SHARED_PAGES: u32 = 48; // 3 MiB, initial == max (no growth; views stay valid)

pub const ZM_HW_VERSION: u32 = 0x0001_0000; // 1.0.0
