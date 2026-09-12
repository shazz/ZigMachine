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
import { cartRam, audioRam, romRam, CART_RAM_BASE, CART_RAM_TOP,
         AUDIO_RAM_BASE, AUDIO_RAM_TOP, ROM_RAM_BASE, ROM_RAM_TOP } from "../docs/wasm_hiwater.js";

// Which memory map a module lives in. Getting this wrong is not cosmetic: the
// AUDIO thread's window is HALF the size at the same address, so measuring
// demo-audio against the video map would pass a cart that has already grown a
// megabyte into SONG RAM. (demo-audio went from ~40 KB to ~750 KB when a 68000
// core landed in it, so the headroom is real and worth watching.)
function windowFor(path) {
    const name = path.split("/").pop();
    if (name === "demo-audio.wasm") {
        return { measure: audioRam, label: "audio", kb: (AUDIO_RAM_TOP - AUDIO_RAM_BASE) / 1024 };
    }
    if (name === "rom.wasm") {
        return { measure: romRam, label: "ROM  ", kb: (ROM_RAM_TOP - ROM_RAM_BASE) / 1024 };
    }
    return { measure: cartRam, label: "cart ", kb: (CART_RAM_TOP - CART_RAM_BASE) / 1024 };
}

const files = process.argv.slice(2);
let ok = true;
for (const f of files) {
    try {
        const win = windowFor(f);
        const ram = win.measure(await readFile(f));
        if (!ram.known && !ram.over) {
            console.log(`SKIP  ${f}  no static data or stack to measure`);
            continue;
        }
        const usedKB = (ram.used / 1024).toFixed(0);
        const freeKB = (ram.free / 1024).toFixed(0);
        if (ram.over) {
            console.log(`OVER  ${f}  [${win.label}] data+stack end at 0x${ram.high.toString(16)}, past its window`);
            ok = false;
        } else {
            console.log(`FITS  ${f}  [${win.label}] used ${usedKB}KB / ${win.kb}KB window  (${freeKB}KB free)`);
        }
    } catch (e) {
        console.log(`ERROR ${f}: ${e.message}`);
        ok = false;
    }
}
process.exit(ok ? 0 : 1);
