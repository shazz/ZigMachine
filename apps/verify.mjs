// Headless ABI check: instantiate each foreign demo the way sealed-loader.js
// does (shared 79-page memory + env.hwVideoBase/consoleLogJS), run boot()+frames,
// and assert it (a) enabled plane 0, (b) wrote an opaque palette, (c) drew pixels
// that ANIMATE. Proves the polyglot app talks to the ABI — no browser needed.
import { readFile } from "node:fs/promises";

const PAGES = 79;
const VIDEO_BASE = 0x300000; // hwVideoBase() return value (HW_VIDEO_BASE)
const OFF_PAL = 0x0100, OFF_VRAM = 0x1100, W = 320, H = 200;

async function check(path) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const dec = new TextDecoder();
    let logged = "";
    const env = {
        memory,
        hwVideoBase: () => VIDEO_BASE,
        consoleLogJS: (ptr, len) => { logged = dec.decode(new Uint8Array(memory.buffer, ptr, len)); },
    };
    const { instance } = await WebAssembly.instantiate(await readFile(path), { env });
    const x = instance.exports;

    x.boot();
    const pal = new Uint8Array(memory.buffer, VIDEO_BASE + OFF_PAL, 256 * 4);
    const fb = new Uint8Array(memory.buffer, VIDEO_BASE + OFF_VRAM, W * H);

    x.frame(16.6);
    const snap1 = fb.slice(0, 4096);
    x.frame(16.6); x.frame(16.6);
    const snap2 = fb.slice(0, 4096);

    const planeOn = !!x.isPlaneEnabled(0);
    const alphaOpaque = pal[3] === 255 && pal[255 * 4 + 3] === 255;
    const drew = snap1.some((v) => v !== 0);
    let animated = false;
    for (let i = 0; i < snap1.length; i++) if (snap1[i] !== snap2[i]) { animated = true; break; }

    const ok = planeOn && alphaOpaque && drew && animated;
    console.log(`\n${path}`);
    console.log(`  console.log   : "${logged}"`);
    console.log(`  plane0 enabled: ${planeOn}`);
    console.log(`  palette opaque: ${alphaOpaque}`);
    console.log(`  pixels drawn  : ${drew}`);
    console.log(`  animates      : ${animated}`);
    console.log(`  => ${ok ? "PASS ✅" : "FAIL ❌"}`);
    return ok;
}

const targets = process.argv.slice(2);
const files = targets.length ? targets : ["docs/demo-c.wasm", "docs/demo-rust.wasm"];
let allOk = true;
for (const f of files) allOk = (await check(f)) && allOk;
process.exit(allOk ? 0 : 1);
