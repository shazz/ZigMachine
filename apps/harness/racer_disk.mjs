// RACER's disk for the headless harnesses (Kestrel Racing M5 step 2): the cart reads its tracks off its own
// demo-racer.zmd (env.diskReadBlock, one 512-byte block a call), as the menu mounts it in the browser.
// bootObj(cart, log, diskHook()) mounts it; without the hook every import is a stub answering 0, so the cart sees
// no disk and lists the built-in oval only. `stats.reads` counts the block reads (the board's load-time estimate).
import { readFileSync } from "node:fs";

export const ZMD = process.env.RACER_ZMD || "site/carts/demo-racer.zmd";

export function diskHook(path = ZMD, stats = { reads: 0 }) { // path: a .zmd file, or its bytes
    const img = typeof path === "string" ? new Uint8Array(readFileSync(path)) : path;
    return (env) => {
        env.diskReadBlock = (block, dst) => {
            const at = block * 512;
            if (at >= img.length) return 0;
            const n = Math.min(512, img.length - at);
            new Uint8Array(env.memory.buffer, dst, n).set(img.subarray(at, at + n));
            stats.reads++;
            return n;
        };
    };
}

/** A file's { start, len } in a .zmd image (v1: FAT at $300, count at $2E4; v2: $800 / $4F4), or null. */
export function fatEntry(img, name) {
    const v2 = img[0x400] === 0x5a && img[0x401] === 0x4d; // "ZM" of ZMDISK at $400
    const dv = new DataView(img.buffer, img.byteOffset);
    const count = dv.getUint16(v2 ? 0x4f4 : 0x2e4, true), fat = v2 ? 0x800 : 0x300;
    for (let i = 0; i < count; i++) {
        const e = fat + 32 * i, n = new TextDecoder().decode(img.subarray(e, e + 16)).replace(/\0.*$/s, "");
        if (n === name) return { start: dv.getUint32(e + 16, true), len: dv.getUint32(e + 20, true) };
    }
    return null;
}
