// RACER's disk for the headless harnesses (Kestrel Racing M5 step 2): the cart reads its tracks off its own
// demo-racer.zmd (env.diskReadBlock, one 512-byte block a call), as the menu mounts it in the browser.
// bootObj(cart, log, diskHook()) mounts it; without the hook every import is a stub answering 0, so the cart sees
// no disk and lists the built-in oval only. `stats.reads` counts the block reads (the board's load-time estimate).
import { readFileSync } from "node:fs";

export const ZMD = process.env.RACER_ZMD || "site/carts/demo-racer.zmd";

export function diskHook(path = ZMD, stats = { reads: 0 }) {
    const img = new Uint8Array(readFileSync(path));
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
