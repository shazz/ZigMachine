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
pub const CART_RAM_BASE = memmap.CART_RAM_BASE;
pub const CART_RAM_TOP = memmap.CART_RAM_TOP;
pub const CART_RAM_BYTES = memmap.CART_RAM_BYTES;
pub const ROM_RAM_BASE = memmap.ROM_RAM_BASE;
pub const ROM_RAM_TOP = memmap.ROM_RAM_TOP;
pub const ROM_RAM_BYTES = memmap.ROM_RAM_BYTES;
pub const defaultFbBase = memmap.defaultFbBase;
pub const REG_RESOLUTION = memmap.REG_RESOLUTION;
pub const REG_BACKGROUND = memmap.REG_BACKGROUND;
pub const REG_GLOBAL_HBL_ID = memmap.REG_GLOBAL_HBL_ID;
pub const REG_FB_HBL_ID = memmap.REG_FB_HBL_ID;
pub const REG_FB_HBL_POS = memmap.REG_FB_HBL_POS;
pub const REG_FB_STRIDE = memmap.REG_FB_STRIDE;
pub const REG_FB_BASE = memmap.REG_FB_BASE;
pub const REG_HSCROLL = memmap.REG_HSCROLL;
pub const REG_FB_MODE = memmap.REG_FB_MODE;
pub const REG_RES_FLICKER = memmap.REG_RES_FLICKER;
pub const REG_BEAM_COUNT = memmap.REG_BEAM_COUNT; // 1.6.0 BEAM: mid-line colour-0 writes
pub const REG_BEAM_DROPPED = memmap.REG_BEAM_DROPPED;
pub const OFF_BEAM_TABLE = memmap.OFF_BEAM_TABLE;
pub const BEAM_MAX = memmap.BEAM_MAX;
pub const BEAM_GRID = memmap.BEAM_GRID;
pub const BEAM_MIN_GAP = memmap.BEAM_MIN_GAP;
pub const FB_MODE_NORMAL = memmap.FB_MODE_NORMAL;
pub const FB_MODE_FULLSCREEN = memmap.FB_MODE_FULLSCREEN;
pub const FB_MODE_SCROLL = memmap.FB_MODE_SCROLL;
pub const FB_MODE_MEDIUM = memmap.FB_MODE_MEDIUM;
pub const FB_MODE_OVERSCAN = memmap.FB_MODE_OVERSCAN;
pub const OVERSCAN_MAGIC_X = memmap.OVERSCAN_MAGIC_X;
pub const OVERSCAN_X_TOL = memmap.OVERSCAN_X_TOL;
pub const RES_MEDIUM = memmap.RES_MEDIUM;
pub const MEDIUM_WIDTH = memmap.MEDIUM_WIDTH;
pub const MEDIUM_HEIGHT = memmap.MEDIUM_HEIGHT;
pub const MEDIUM_PLANES = memmap.MEDIUM_PLANES;
pub const MEDIUM_FB_BYTES = memmap.MEDIUM_FB_BYTES;
pub const MEDIUM_FULL_FB_BYTES = memmap.MEDIUM_FULL_FB_BYTES;
pub const RASTER_WIDTH = memmap.RASTER_WIDTH;
pub const RASTER_HEIGHT = memmap.RASTER_HEIGHT;
pub const RASTER_VIS_WIDTH = memmap.RASTER_VIS_WIDTH;
pub const RASTER_VIS_HEIGHT = memmap.RASTER_VIS_HEIGHT;
pub const RES_PLANES = memmap.RES_PLANES;
pub const RES_TRUECOLOR = memmap.RES_TRUECOLOR;
pub const HBL_GLOBAL_ID = memmap.HBL_GLOBAL_ID;
pub const STRIDE_NORMAL = memmap.STRIDE_NORMAL;
pub const STRIDE_FULLSCREEN = memmap.STRIDE_FULLSCREEN;

// --- blitter register block + command/control/minterm constants (see BLITTER_HW_SPEC) ---
pub const OFF_BLIT = memmap.OFF_BLIT;
pub const BLIT_COMMAND = memmap.BLIT_COMMAND;
pub const BLIT_MINTERM = memmap.BLIT_MINTERM;
pub const BLIT_CON = memmap.BLIT_CON;
pub const BLIT_STATUS = memmap.BLIT_STATUS;
pub const BLIT_COLOR = memmap.BLIT_COLOR;
pub const BLIT_BG_COLOR = memmap.BLIT_BG_COLOR;
pub const BLIT_COLOR_KEY = memmap.BLIT_COLOR_KEY;
pub const BLIT_CON2 = memmap.BLIT_CON2;
pub const CON2_SRC_ABS = memmap.CON2_SRC_ABS;
pub const CON2_FILL_MT = memmap.CON2_FILL_MT;
pub const CON2_HALFTONE_EN = memmap.CON2_HALFTONE_EN;
pub const BLIT_A_BASE = memmap.BLIT_A_BASE;
pub const BLIT_A_STRIDE = memmap.BLIT_A_STRIDE;
pub const BLIT_B_BASE = memmap.BLIT_B_BASE;
pub const BLIT_B_STRIDE = memmap.BLIT_B_STRIDE;
pub const BLIT_C_BASE = memmap.BLIT_C_BASE;
pub const BLIT_C_STRIDE = memmap.BLIT_C_STRIDE;
pub const BLIT_D_BASE = memmap.BLIT_D_BASE;
pub const BLIT_D_STRIDE = memmap.BLIT_D_STRIDE;
pub const BLIT_W = memmap.BLIT_W;
pub const BLIT_H = memmap.BLIT_H;
pub const BLIT_X0 = memmap.BLIT_X0;
pub const BLIT_Y0 = memmap.BLIT_Y0;
pub const BLIT_X1 = memmap.BLIT_X1;
pub const BLIT_Y1 = memmap.BLIT_Y1;
pub const BLIT_X2 = memmap.BLIT_X2;
pub const BLIT_Y2 = memmap.BLIT_Y2;
pub const BLIT_CLIP_X = memmap.BLIT_CLIP_X;
pub const BLIT_CLIP_Y = memmap.BLIT_CLIP_Y;
pub const BLIT_CLIP_W = memmap.BLIT_CLIP_W;
pub const BLIT_CLIP_H = memmap.BLIT_CLIP_H;
pub const BLIT_HALFTONE = memmap.BLIT_HALFTONE;
pub const BLIT_CYCLES = memmap.BLIT_CYCLES;
pub const BLIT_CMD_NOP = memmap.BLIT_CMD_NOP;
pub const BLIT_CMD_BLIT = memmap.BLIT_CMD_BLIT;
pub const BLIT_CMD_FILL = memmap.BLIT_CMD_FILL;
pub const BLIT_CMD_LINE = memmap.BLIT_CMD_LINE;
pub const BLIT_CMD_TRIANGLE = memmap.BLIT_CMD_TRIANGLE;
pub const CON_USEA = memmap.CON_USEA;
pub const CON_USEB = memmap.CON_USEB;
pub const CON_USEC = memmap.CON_USEC;
pub const CON_KEY_EN = memmap.CON_KEY_EN;
pub const CON_IFE = memmap.CON_IFE;
pub const CON_EFE = memmap.CON_EFE;
pub const CON_DESC = memmap.CON_DESC;
pub const CON_CLIP_EN = memmap.CON_CLIP_EN;
pub const MT_A = memmap.MT_A;
pub const MT_B = memmap.MT_B;
pub const MT_C = memmap.MT_C;
pub const MT_COOKIE = memmap.MT_COOKIE;
pub const MT_XOR_BC = memmap.MT_XOR_BC;
pub const MT_OR_BC = memmap.MT_OR_BC;
pub const MT_CLEAR = memmap.MT_CLEAR;
pub const MT_SET = memmap.MT_SET;

// --- video hardware entry points (implemented in machine-video.wasm) ---
pub extern fn hwVideoBase() i32; // base of the video hardware region
pub extern fn hwInit() void; // reset registers/planes
pub extern fn hwClear() void; // fill PFB with BACKGROUND, run GLOBAL_HBL per row
pub extern fn hwRenderPlane(plane: u32) void; // composite one enabled LFB -> PFB
pub extern fn hwBlit() void; // execute the blitter COMMAND in the register block
pub extern fn hwBorderX() u32; // physical border width (host pointer mapping)
pub extern fn hwBorderY() u32;
pub extern fn hwPhysicalPtr() i32; // pointer to PFB for the host to blit
pub extern fn hwPlanesNumber() u8;
pub extern fn hwPhysWidth() u32;
pub extern fn hwPhysHeight() u32;
pub extern fn hwVersion() u32; // ZM_HW_VERSION

// --- RAM instructions ---
// How much of the cart's RAM window [CART_RAM_BASE, CART_RAM_TOP) is left. The
// window holds this cart's static data AND its stack, and running past the top
// corrupts the video region silently instead of trapping — so size big buffers
// against hwRamFree() rather than a constant. hwRamFree() returns 0 when the
// host has not declared the cart's high-water (an old loader), which is
// deliberately indistinguishable from "full": treat 0 as "take nothing".
pub extern fn hwRamBase() u32; // first byte of the cart's window (0x100000)
pub extern fn hwRamTop() u32; // first byte ABOVE it (= the video region)
pub extern fn hwRamSize() u32; // the whole window, in bytes (2 MiB)
pub extern fn hwRamUsed() u32; // this cart's static data + stack
pub extern fn hwRamFree() u32; // what is left below the video region

// The ROM chip's own window, above the video region (Phase 2). Reports 0 until
// a rom.wasm is fitted — an app asking about a ROM that is not there gets the
// same answer as an app asking about a full one: take nothing.
pub extern fn hwRomRamBase() u32;
pub extern fn hwRomRamTop() u32;
pub extern fn hwRomRamSize() u32;
pub extern fn hwRomRamUsed() u32;
pub extern fn hwRomRamFree() u32;
