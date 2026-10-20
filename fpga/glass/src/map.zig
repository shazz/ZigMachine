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
pub const VERSION: u32 = 0x0001_0400; // 1.4.0: REG_OSD_POS, CTRL_OSD_STATS (1.3.0: REG_LOAD_BASE moves the HP window; 1.2.0: REG_AUDIO_VOL, CTRL_WARM; 1.1.0: REG_POINTER)

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
pub const REG_POINTER: u32 = 0x38; // rw, the mouse (PTR_*); reads back with the cart's view
pub const REG_AUDIO_VOL: u32 = 0x3C; // rw, AUDIO_*: the master volume and mute the PL's mixer applies
pub const REG_OSD_POS: u32 = 0x40; // rw, OSD_POS_*: the OSD window's top-left on the output (1.4.0)

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

// REG_OSD_POS: where the window's top-left sits, in output pixels. The reset
// value is the centred place above, so a glass older than 1.4.0 sees no change.
// Part of the window past the right or bottom edge is simply not drawn.
pub const OSD_POS_X_SHIFT: u32 = 0;
pub const OSD_POS_Y_SHIFT: u32 = 16;
pub const OSD_POS_X_MASK: u32 = 0x7FF;
pub const OSD_POS_Y_MASK: u32 = 0x3FF;
pub const OSD_POS_RESET: u32 = OSD_X0 << OSD_POS_X_SHIFT | OSD_Y0 << OSD_POS_Y_SHIFT;
// The PL that has REG_OSD_POS and CTRL_OSD_STATS; an older one simply has no
// frame-rate overlay (glass checks, never refuses).
pub const VERSION_OSD_STATS: u32 = 0x0001_0400;

// --- CTRL / STATUS bits ------------------------------------------------------
pub const CTRL_RUN: u32 = 1 << 0; // 0 holds the cart CPU in reset (the reset value)
pub const CTRL_OSD: u32 = 1 << 1; // show the OSD over the picture
pub const CTRL_KEY_FLUSH: u32 = 1 << 2; // strobe: empty the key FIFO, clear ST_KEY_OVERFLOW
// The next boot is WARM: the firmware keeps the cart's memory and re-enters the
// cart's boot (the ST's reset button). Stored; the firmware reads it once, at boot
// (glass/firmware/glass_boot.h). A cold load writes CTRL without it.
pub const CTRL_WARM: u32 = 1 << 3;
// The stats overlay (F11): a character cell holding a plain space (no inverse)
// is TRANSPARENT, so only the text covers the picture; other cells draw as ever.
pub const CTRL_OSD_STATS: u32 = 1 << 4;

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
pub const KEY_ALT: u32 = 0xE013; // KEY_CODES.Alt in sealed-loader.js (ST Replay's ALTernate O/P)
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
// Page Up/Down page the OSD's shelf (Matt, 2026-10-20). The ST has no such keys and no
// cart has a code for them, so the glass never forwards them (App.keyEvent drops them).
pub const KEY_PAGE_UP: u32 = 0xE024;
pub const KEY_PAGE_DOWN: u32 = 0xE025;

/// Keys only the OSD uses: never pushed to the cart.
pub fn osdOnly(code: u32) bool {
    return code == KEY_PAGE_UP or code == KEY_PAGE_DOWN;
}

// --- joypad (REG_JOY): the demo.input() directions, as held bits -------------
pub const JOY_UP: u32 = 1 << 0;
pub const JOY_DOWN: u32 = 1 << 1;
pub const JOY_LEFT: u32 = 1 << 2;
pub const JOY_RIGHT: u32 = 1 << 3;
pub const JOY_FIRE: u32 = 1 << 5; // bit 5 = demo.input(5), the browser's fire

// --- the mouse (REG_POINTER): demo.pointer(x, y, buttons) ----------------------
// A STATE, not an event queue: the browser calls pointer() on every move with
// the latest position, so only the newest one matters and motion never crowds
// keys out of the FIFO. The ARM writes x, y and the held buttons; the PL keeps
// every button pressed since the cart CPU's last ack visible (the browser
// defers a release by a frame for the same reason: a click shorter than a
// frame must still be seen), and counts changes in SEQ, so the firmware polls
// one word. The firmware acks with the SEQ it delivered; an ack that is stale
// (the ARM wrote since) is ignored, and an ack that drops a latched button the
// ARM no longer holds bumps SEQ, so that release is delivered next.
pub const PTR_X_SHIFT: u32 = 0;
pub const PTR_Y_SHIFT: u32 = 10;
pub const PTR_BTN_SHIFT: u32 = 20;
pub const PTR_SEQ_SHIFT: u32 = 24; // read-only: the ARM's write leaves it alone
pub const PTR_COORD_MASK: u32 = 0x3FF;
pub const PTR_BTN_MASK: u32 = 0xF;
pub const PTR_SEQ_MASK: u32 = 0xFF;
// sealed-loader.js: any mouse button is bit 0, and a double-click is a one-off
// pulse of bit 1 (gem_desktop.zig opens the item under the pointer on it).
pub const PTR_BTN_PRESS: u32 = 1 << 0;
pub const PTR_BTN_DOUBLE: u32 = 1 << 1;
// The coordinate space: the machine's physical-visible area, what the browser
// sends (hwPhysWidth - 2*hwBorderX by hwPhysHeight - 2*hwBorderY = 800-160 by
// 280-80). A low-res cart halves x itself. app_test.zig checks it against
// machine/sdk/memmap.zig.
pub const PTR_WIDTH: u32 = 640;
pub const PTR_HEIGHT: u32 = 200;

// --- REG_CART_STATE, as the cart CPU's firmware reports it --------------------
pub const CART_RESET: u32 = 0; // also what a CPU held in reset leaves there
pub const CART_BOOTING: u32 = 1;
pub const CART_RUNNING: u32 = 2;
pub const CART_TRAPPED: u32 = 3; // bits 31:8 = the wasm2c trap code
// Bits 31:8 carry an argument: TRAPPED's trap code; BOOTING's and RUNNING's
// firmware version (major.minor.patch, 8 bits each), which the debug page shows.
pub const CART_ARG_SHIFT: u32 = 8;
pub const CART_STATE_MASK: u32 = 0xFF;
// A warm boot found no cart memory to keep (a cold load zeroed it, or the cart
// never finished its cold boot): the ARM offers a cold reset instead.
pub const TRAP_WARM_LOST: u32 = 0xFF_FF01;

// --- the master volume (REG_AUDIO_VOL) -----------------------------------------
// The mixer (fpga/rtl/audio/) multiplies every mixed sample before the HDMI
// sample FIFO: gain = vol + vol[7] (0..256, so 255 is exactly unity), out =
// (sample * gain) >>> 8, and 0 while AUDIO_MUTE is set. The ARM restores it from
// glass.cfg at start; the reset value plays at unity, so a PL with no glass
// program running is never silent.
pub const AUDIO_VOL_MASK: u32 = 0xFF;
pub const AUDIO_MUTE: u32 = 1 << 8;
pub const AUDIO_VOL_RESET: u32 = 0xFF;

// --- DDR (PS physical addresses) ---------------------------------------------
// The cart CPU's whole RAM: the top 32 MiB of the Z7-Lite's 512 MiB, kept from
// Linux by a reserved-memory node (no-map). The cart CPU sees it at
// CART_CPU_BASE, as LiteX's main_ram, laid out as fpga/cycles links it.
pub const DDR_CART_BASE: u32 = 0x1E00_0000;
pub const DDR_CART_BYTES: u32 = 0x0200_0000;
pub const CART_CPU_BASE: u32 = 0x4000_0000;
// LOAD_BASE's reset value: the window U-Boot leaves alone (it relocates itself
// into the top of DDR, over DDR_CART_BASE), so the U-Boot flow (board_run.py,
// loadx to 0x0400_0000) needs no write. Under Linux that is the initramfs:
// the glass writes DDR_CART_BASE before CTRL_RUN. Only bits 31..25 are used
// (a 32 MiB-aligned window, soc/zm_board_mem.py hp_slice).
pub const LOAD_BASE_RESET: u32 = 0x0400_0000;

// --- the disk in the cart window (docs/FPGA_GLASS.md, "The disk in DDR") -----
// ZWINDOW places the whole shelf disk (the .zmd the browser mounts: the fat
// disk minus its board image) in the window, after the image, so ZIGGY's
// firmware serves env.diskReadBlock from DDR as sealed-loader.js serves it from
// the JS heap. ZWINDOW then writes a descriptor of DISK_DESC_WORDS words at
// window end - DISK_DESC_FROM_TOP (CPU 0x41FF_FC00, in the top 4 KiB the link
// keeps free): DISK_MAGIC, the disk's window offset, its bytes, and the check
// ~(magic ^ offset ^ bytes). Offsets, not CPU addresses: the ARM never sees
// CART_CPU_BASE. No descriptor (U-Boot's flow, an old glass): no disk, the
// drive answers 0 as scene_hash.mjs's does.
pub const DISK_DESC_FROM_TOP: u32 = 0x400;
pub const DISK_DESC_WORDS: u32 = 4;
pub const DISK_MAGIC: u32 = 0x4B44_4D5A; // "ZMDK"
pub const DISK_ALIGN: u32 = 0x1000; // the disk starts on the first 4 KiB boundary after the image
// The disk must end by here: the two pictures (cycles/bmailbox.h ZM_FB0_ADDR,
// window offset 12 MiB), where the image's own limit is too (cycles/board.mk).
pub const DISK_END: u32 = 0x00C0_0000;

// --- the disk (.zmd) ---------------------------------------------------------
// A "fat" disk carries the cart's rv32 board image as one more FAT file, found
// by type (fpga/tools/zmd_fat.py writes it, ZX0-packed like the wasm cart).
pub const ZMD_TYPE_WASM: u32 = 0;
pub const ZMD_TYPE_RAW: u32 = 1;
pub const ZMD_TYPE_RV32: u32 = 3;
