// Headless ABI check for FOREIGN-LANGUAGE carts: instantiate each one the way
// sealed-loader.js does — the real machine, the real ROM chip, one shared memory —
// run boot()+frames, and assert it (a) enabled plane 0, (b) wrote an opaque
// palette, (c) drew pixels that ANIMATE.
//
// And, for a cart that imports the ROM's ABI, (d) that GEM ACTUALLY DREW FOR IT.
// That last one is the whole claim of the machine/rom split — "a ROM is just a
// module linked against the HW ABI, so any language can call it" — which was an
// assertion in a README until this checked it. It is not satisfied by the cart
// merely linking: the test reads the framebuffer back and requires the ROM's own
// output to be there.
import { readFile } from "node:fs/promises";
import { cartRam, CART_RAM_BASE, CART_RAM_TOP } from "../docs/wasm_hiwater.js";

const PAGES = 112; // memmap.SHARED_PAGES
const VIDEO_BASE = 0x300000; // hwVideoBase() return value (HW_VIDEO_BASE)
const OFF_PAL = 0x0100, OFF_VRAM = 0x1100, W = 320, H = 200;

// Every import name a wasm module asks for, so the check can tell a cart that
// uses the ROM from one that does not and assert accordingly.
function importNames(bytes) {
    let p = 8; const names = []; const dec = new TextDecoder();
    const u = () => { let r = 0, s = 0, x; do { x = bytes[p++]; r |= (x & 0x7f) << s; s += 7; } while (x & 0x80); return r >>> 0; };
    while (p < bytes.length) {
        const id = bytes[p++]; const len = u(); const next = p + len;
        if (id === 2) {
            const c = u();
            for (let i = 0; i < c; i++) {
                const ml = u(); p += ml;
                const nl = u(); names.push(dec.decode(bytes.subarray(p, p + nl))); p += nl;
                const k = bytes[p++];
                if (k === 0) u();
                else if (k === 1) { p++; const fl = bytes[p++]; u(); if (fl & 1) u(); }
                else if (k === 2) { const fl = bytes[p++]; u(); if (fl & 1) u(); }
                else if (k === 3) { p++; p++; }
            }
        }
        p = next;
    }
    return names;
}

async function check(path) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const dec = new TextDecoder();
    let logged = "";
    const cart = new Uint8Array(await readFile(path));
    const wantsRom = importNames(cart).includes("guiOpenPlane");
    // The REAL machine and the REAL ROM chip, wired machine -> rom -> cart exactly
    // as the loader does. Stubbing hwVideoBase here would test nothing about the
    // ROM, which is the point of the exercise.
    let live = { demo: null };
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (...a) => live.demo && live.demo.hblDispatch(...a) },
    })).instance.exports;
    const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwInit();
    rom.romReset();
    const ram = cartRam(cart);
    const env = {
        memory,
        hwVideoBase: () => VIDEO_BASE,
        consoleLogJS: (ptr, len) => { logged = dec.decode(new Uint8Array(memory.buffer, ptr, len)); },
        hwRamBase: () => CART_RAM_BASE,
        hwRamTop: () => CART_RAM_TOP,
        hwRamSize: () => CART_RAM_TOP - CART_RAM_BASE,
        hwRamUsed: () => ram.used,
        hwRamFree: () => ram.free,
    };
    const { instance } = await WebAssembly.instantiate(cart, { env: { ...rom, ...env } });
    live.demo = instance.exports;
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

    // (d) Did the ROM draw? The C and Rust apps ask GEM for a panel over plane 0: a white
    // face with GEM's double black border and an inverse title bar. Plasma cannot
    // produce that, so require a run of pure GEM_WHITE (palette index 1) inside
    // the panel — the toolkit's own output, not the app's.
    let romDrew = null;
    if (wantsRom) {
        const PX = 40 + 8, PY = 68 + 46; // inside the panel, below its text rows
        let white = 0;
        for (let x = PX; x < PX + 200; x++) if (fb[PY * W + x] === 1) white++;
        romDrew = white > 150;
    }

    const ok = planeOn && alphaOpaque && drew && animated && (romDrew !== false);
    console.log(`\n${path}`);
    console.log(`  console.log   : "${logged}"`);
    console.log(`  plane0 enabled: ${planeOn}`);
    console.log(`  palette opaque: ${alphaOpaque}`);
    console.log(`  pixels drawn  : ${drew}`);
    console.log(`  animates      : ${animated}`);
    if (romDrew !== null) console.log(`  GEM drew      : ${romDrew}   (rom.wasm rendering for this app)`);
    console.log(`  => ${ok ? "PASS ✅" : "FAIL ❌"}`);
    return ok;
}

const targets = process.argv.slice(2);
const files = targets.length ? targets : ["docs/demo-c.wasm", "docs/demo-rust.wasm"];
let allOk = true;
for (const f of files) allOk = (await check(f)) && allOk;
process.exit(allOk ? 0 : 1);
