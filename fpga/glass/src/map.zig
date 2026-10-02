// The glass register map: the ONE place the PS<->PL interface is defined.
//
// The ARM program imports this file, and fpga/tools/glass_export.zig turns it
// into gen/glass_map.vh (the RTL) and gen/glass_map.py (LiteX, the tests), so
// an offset is never typed twice. Same rule as machine/sdk/memmap.zig, which
// this deliberately does NOT extend: the glass is the console's front panel,
// not part of the machine a cart sees. docs/FPGA_GLASS.md explains each field.
//
// Pure integer constants only: the exporter skips anything else.

// --- where the block sits ----------------------------------------------------
// M_AXI_GP0 covers 0x4000_0000..0x7FFF_FFFF on the PS; 0x43C0_0000 is where
// Vivado puts the first PL peripheral, so every Zynq tutorial and device tree
// reads the same. The PL decodes only the low 16 bits.
pub const GP0_BASE: u32 = 0x43C0_0000;
pub const WINDOW_BYTES: u32 = 0x1_0000;

pub const ID_VALUE: u32 = 0x5A4D_474C; // "ZMGL": the ARM refuses to drive anything else
pub const VERSION: u32 = 0x0001_0000; // 1.0.0

// --- registers (byte offsets, 32-bit, word access only) ----------------------
pub const REG_ID: u32 = 0x00; // ro
pub const REG_VERSION: u32 = 0x04; // ro
pub const REG_CTRL: u32 = 0x08; // rw, CTRL_* bits
pub const REG_STATUS: u32 = 0x0C; // ro, ST_* bits
pub const REG_CART_STATE: u32 = 0x10; // ro here, written by the cart CPU (CART_*)
pub const REG_CART_BEAT: u32 = 0x14; // ro here, frames the cart CPU has finished
pub const REG_LOAD_BASE: u32 = 0x18; // rw, DDR address the cart CPU's RAM starts at
pub const REG_LOAD_SIZE: u32 = 0x1C; // rw, bytes of image the ARM placed there
pub const REG_KEY_PUSH: u32 = 0x20; // wo, one key event (KEY_*) into the FIFO
pub const REG_KEY_LEVEL: u32 = 0x24; // ro, events waiting for the cart CPU
pub const REG_JOY: u32 = 0x28; // rw, JOY_* bits held now
pub const REG_OSD_FG: u32 = 0x2C; // rw, 0x00RRGGBB
pub const REG_OSD_BG: u32 = 0x30; // rw, 0x00RRGGBB
pub const REG_SCRATCH: u32 = 0x34; // rw, bring-up: proves the bus before anything else

// The OSD text: one character a WORD (no byte lanes to get wrong), row-major.
// Write-only: the ARM keeps the text it wrote, reads return 0.
pub const OFF_OSD_TEXT: u32 = 0x1000;
pub const OSD_COLS: u32 = 32;
pub const OSD_ROWS: u32 = 16;
pub const OSD_CHARS: u32 = OSD_COLS * OSD_ROWS; // 512
pub const OSD_INVERSE: u32 = 0x100; // bit 8 of a character word: swap ink and paper

// The OSD's place on the 800x600 output: 8x8 glyphs drawn 2x, centred.
pub const OSD_SCALE: u32 = 2;
pub const OSD_WIDTH: u32 = OSD_COLS * 8 * OSD_SCALE; // 512
pub const OSD_HEIGHT: u32 = OSD_ROWS * 8 * OSD_SCALE; // 256
pub const OSD_X0: u32 = (800 - OSD_WIDTH) / 2; // 144
pub const OSD_Y0: u32 = (600 - OSD_HEIGHT) / 2; // 172

// --- CTRL / STATUS bits ------------------------------------------------------
pub const CTRL_RUN: u32 = 1 << 0; // 0 holds the cart CPU in reset (the reset value)
pub const CTRL_OSD: u32 = 1 << 1; // show the OSD over the picture
pub const CTRL_KEY_FLUSH: u32 = 1 << 2; // strobe: empty the key FIFO, clear ST_KEY_OVERFLOW

pub const ST_RUNNING: u32 = 1 << 0; // the cart CPU is out of reset
pub const ST_KEY_FULL: u32 = 1 << 1;
pub const ST_KEY_OVERFLOW: u32 = 1 << 2; // sticky: a push found the FIFO full and was dropped

pub const KEY_DEPTH: u32 = 16;

// --- key events (REG_KEY_PUSH) -----------------------------------------------
// The machine has no keyboard register: a cart takes input through its exports
// (input, inputRelease, key, keyUp), and which one a key goes to depends on the
// cart (ownsKeyboard). Only the cart CPU can ask the cart, so the ARM sends
// neutral events and the cart CPU's firmware applies docs/sealed-loader.js's
// rules. The code is what the browser hands demo.key(): the character for a
// printable key, else a Unicode private-use code.
pub const KEY_CODE_MASK: u32 = 0x1F_FFFF;
pub const KEY_DOWN: u32 = 1 << 24; // clear = released
pub const KEY_REPEAT: u32 = 1 << 25; // auto-repeat of a key still held

pub const KEY_BACKSPACE: u32 = 8;
pub const KEY_ENTER: u32 = 13;
pub const KEY_F1: u32 = 0xE001; // F1..F10 = 0xE001..0xE00A, as KEY_CODES in sealed-loader.js
pub const KEY_INSERT: u32 = 0xE00B;
pub const KEY_DELETE: u32 = 0xE00C;
pub const KEY_UNDO: u32 = 0xE010;
pub const KEY_HELP: u32 = 0xE011;
pub const KEY_ESCAPE: u32 = 0xE012;
pub const KEY_CTRL_LEFT: u32 = 0xE014; // MOD_CODES in sealed-loader.js
pub const KEY_SHIFT_LEFT: u32 = 0xE015;
pub const KEY_CTRL_RIGHT: u32 = 0xE016;
pub const KEY_SHIFT_RIGHT: u32 = 0xE017;
// The browser sends arrows to demo.input() and never to demo.key(), so they had
// no code: these are the glass's own, and the firmware turns them into input().
pub const KEY_ARROW_UP: u32 = 0xE020;
pub const KEY_ARROW_DOWN: u32 = 0xE021;
pub const KEY_ARROW_LEFT: u32 = 0xE022;
pub const KEY_ARROW_RIGHT: u32 = 0xE023;

// --- joypad (REG_JOY): the demo.input() directions, as held bits -------------
pub const JOY_UP: u32 = 1 << 0;
pub const JOY_DOWN: u32 = 1 << 1;
pub const JOY_LEFT: u32 = 1 << 2;
pub const JOY_RIGHT: u32 = 1 << 3;
pub const JOY_FIRE: u32 = 1 << 5; // bit 5 = demo.input(5), the browser's fire

// --- REG_CART_STATE, as the cart CPU's firmware reports it --------------------
pub const CART_RESET: u32 = 0; // also what a CPU held in reset leaves there
pub const CART_BOOTING: u32 = 1;
pub const CART_RUNNING: u32 = 2;
pub const CART_TRAPPED: u32 = 3; // bits 31:8 = the wasm2c trap code

// --- DDR (PS physical addresses) ---------------------------------------------
// The cart CPU's whole RAM: the top 32 MiB of the Z7-Lite's 512 MiB, kept from
// Linux by a reserved-memory node (no-map). The cart CPU sees it at
// CART_CPU_BASE, as LiteX's main_ram, laid out as fpga/cycles links it.
pub const DDR_CART_BASE: u32 = 0x1E00_0000;
pub const DDR_CART_BYTES: u32 = 0x0200_0000;
pub const CART_CPU_BASE: u32 = 0x4000_0000;

// --- the disk (.zmd) ---------------------------------------------------------
// A "fat" disk carries the cart's rv32 board image as one more FAT file, found
// by type (fpga/tools/zmd_fat.py writes it, ZX0-packed like the wasm cart).
pub const ZMD_TYPE_WASM: u32 = 0;
pub const ZMD_TYPE_RAW: u32 = 1;
pub const ZMD_TYPE_RV32: u32 = 3;
