// Check that a ZigMachine cart wasm fits the demo window: its static data + stack
// must end below the video region (HW_VIDEO_BASE), or it silently corrupts VRAM at
// runtime (the linker only catches overflow past the whole shared memory, not the
// subtler overflow into the video region). See docs/FLOPPY_DISK.md / build.zig.
//
// Usage: node apps/check_fits.mjs <cart.wasm> [more.wasm ...]   (exit 1 on any fail)
import { readFile } from "node:fs/promises";

const VIDEO_BASE = 0x300000; // HW_VIDEO_BASE (machine/sdk/memmap.zig) — demo window ends here
const GLOBAL_BASE = 0x100000; // demo module data starts here
const STACK = 6 * 65536; // conservative stack allowance (build.zig demo_stack); C/Rust use less

// Read an unsigned LEB128 at bytes[p]; returns [value, nextPos].
function uleb(b, p) {
    let r = 0, s = 0, x;
    do { x = b[p++]; r |= (x & 0x7f) << s; s += 7; } while (x & 0x80);
    return [r >>> 0, p];
}

// Highest (offset + length) across the wasm's active data segments = __data_end.
function dataEnd(b) {
    if (b[0] !== 0x00 || b[1] !== 0x61 || b[2] !== 0x73 || b[3] !== 0x6d) throw new Error("not a wasm module");
    let p = 8, end = GLOBAL_BASE;
    while (p < b.length) {
        const id = b[p++];
        let len; [len, p] = uleb(b, p);
        const next = p + len;
        if (id === 11) { // Data section
            let count; [count, p] = uleb(b, p);
            for (let i = 0; i < count; i++) {
                let flags; [flags, p] = uleb(b, p);
                if ((flags & 0x01) === 0) { // active segment: [i32.const off] end, then size+bytes
                    if (flags & 0x02) [, p] = uleb(b, p); // explicit memidx
                    // offset expr: 0x41 (i32.const) sleb, 0x0b (end)
                    p++; // 0x41
                    let off = 0, s = 0, x;
                    do { x = b[p++]; off |= (x & 0x7f) << s; s += 7; } while (x & 0x80);
                    if (s < 32 && (x & 0x40)) off |= (~0 << s); // sign-extend
                    p++; // 0x0b end
                    let sz; [sz, p] = uleb(b, p);
                    end = Math.max(end, (off >>> 0) + sz);
                    p += sz;
                } else { // passive: size + bytes (no memory placement)
                    let sz; [sz, p] = uleb(b, p);
                    p += sz;
                }
            }
        }
        p = next;
    }
    return end;
}

const files = process.argv.slice(2);
let ok = true;
for (const f of files) {
    try {
        const de = dataEnd(await readFile(f));
        const high = de + STACK;               // data + stack high-water
        const pass = high < VIDEO_BASE;
        const usedKB = ((high - GLOBAL_BASE) / 1024).toFixed(0);
        const freeKB = ((VIDEO_BASE - high) / 1024).toFixed(0);
        console.log(`${pass ? "FITS " : "OVER "} ${f}  used ${usedKB}KB / 2048KB window  (${freeKB}KB free)`);
        if (!pass) ok = false;
    } catch (e) {
        console.log(`ERROR ${f}: ${e.message}`);
        ok = false;
    }
}
process.exit(ok ? 0 : 1);
