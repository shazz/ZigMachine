// --------------------------------------------------------------------------
// ZigMachine — published hardware API header (the ONLY machine artefact a coder
// receives besides the two sealed .wasm binaries).
//
// All function bodies live in the sealed machine-video.wasm / machine-audio.wasm
// binaries; here they are `extern` declarations, resolved at instantiation time
// by the host wiring the demo module's imports to the machine module's exports.
// The constants document the memory map (re-exported from memmap.zig, which is
// the single ABI source of truth).
//
// ZigOS (zigos.zig) builds LogicalFB / palette / printText / HBL registration on
// top of this, so effects and scenes keep an unchanged API after the seal.
// --------------------------------------------------------------------------
const memmap = @import("memmap.zig");

// --- geometry (re-exported under the names ZigOS/effects already use) ---
pub const PHYSICAL_WIDTH = memmap.PHYSICAL_WIDTH;
pub const PHYSICAL_HEIGHT = memmap.PHYSICAL_HEIGHT;
pub const WIDTH = memmap.WIDTH;
pub const HEIGHT = memmap.HEIGHT;
pub const NB_PLANES = memmap.NB_PLANES;
pub const HORIZONTAL_BORDERS_WIDTH = memmap.HORIZONTAL_BORDERS_WIDTH;
pub const VERTICAL_BORDERS_HEIGHT = memmap.VERTICAL_BORDERS_HEIGHT;

// --- memory map (offsets/sizes, for ZigOS to compute its views) ---
pub const OFF_PAL = memmap.OFF_PAL;
pub const OFF_VRAM = memmap.OFF_VRAM;
pub const OFF_PFB = memmap.OFF_PFB;
pub const PAL_BYTES = memmap.PAL_BYTES;
pub const VRAM_BYTES = memmap.VRAM_BYTES;
pub const NORMAL_FB_BYTES = memmap.NORMAL_FB_BYTES;
pub const FULLSCREEN_FB_BYTES = memmap.FULLSCREEN_FB_BYTES;
pub const defaultFbBase = memmap.defaultFbBase;
pub const REG_RESOLUTION = memmap.REG_RESOLUTION;
pub const REG_BACKGROUND = memmap.REG_BACKGROUND;
pub const REG_GLOBAL_HBL_ID = memmap.REG_GLOBAL_HBL_ID;
pub const REG_FB_HBL_ID = memmap.REG_FB_HBL_ID;
pub const REG_FB_HBL_POS = memmap.REG_FB_HBL_POS;
pub const REG_FB_STRIDE = memmap.REG_FB_STRIDE;
pub const REG_FB_BASE = memmap.REG_FB_BASE;
pub const REG_HSCROLL = memmap.REG_HSCROLL;
pub const RES_PLANES = memmap.RES_PLANES;
pub const RES_TRUECOLOR = memmap.RES_TRUECOLOR;
pub const HBL_GLOBAL_ID = memmap.HBL_GLOBAL_ID;
pub const STRIDE_NORMAL = memmap.STRIDE_NORMAL;
pub const STRIDE_FULLSCREEN = memmap.STRIDE_FULLSCREEN;

// --- video hardware entry points (implemented in machine-video.wasm) ---
pub extern fn hwVideoBase() i32; // base of the video hardware region
pub extern fn hwInit() void; // reset registers/planes
pub extern fn hwClear() void; // fill PFB with BACKGROUND, run GLOBAL_HBL per row
pub extern fn hwRenderPlane(plane: u32) void; // composite one enabled LFB -> PFB
pub extern fn hwPhysicalPtr() i32; // pointer to PFB for the host to blit
pub extern fn hwPlanesNumber() u8;
pub extern fn hwPhysWidth() u32;
pub extern fn hwPhysHeight() u32;
pub extern fn hwVersion() u32; // ZM_HW_VERSION
