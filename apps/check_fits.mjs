// Check that a ZigMachine cart wasm fits the demo window: its static data + stack
// must end below the video region (memmap.CART_RAM_TOP), or it silently corrupts
// VRAM at runtime (the linker only catches overflow past the whole shared memory,
// not the subtler overflow into the video region). See docs/FLOPPY_DISK.md.
//
// The measurement is the same code the loader hands to hwSetCartHigh, so these
// numbers match what a running cart reads back from hwRamFree() to the byte.
//
// Usage: node apps/check_fits.mjs <cart.wasm> [more.wasm ...]   (exit 1 on any fail)
import { readFile } from "node:fs/promises";
import { cartRam, CART_RAM_BASE, CART_RAM_TOP } from "../docs/wasm_hiwater.js";

const WINDOW_KB = (CART_RAM_TOP - CART_RAM_BASE) / 1024;

const files = process.argv.slice(2);
let ok = true;
for (const f of files) {
    try {
        const ram = cartRam(await readFile(f));
        if (!ram.known && !ram.over) {
            console.log(`SKIP  ${f}  no static data or stack to measure`);
            continue;
        }
        const usedKB = (ram.used / 1024).toFixed(0);
        const freeKB = (ram.free / 1024).toFixed(0);
        if (ram.over) {
            console.log(`OVER  ${f}  data+stack end at 0x${ram.high.toString(16)}, past 0x${CART_RAM_TOP.toString(16)}`);
            ok = false;
        } else {
            console.log(`FITS  ${f}  used ${usedKB}KB / ${WINDOW_KB}KB window  (${freeKB}KB free)`);
        }
    } catch (e) {
        console.log(`ERROR ${f}: ${e.message}`);
        ok = false;
    }
}
process.exit(ok ? 0 : 1);
