// Headless NAOS / NITROWAVE DEMO driver (cart 81). The reference is the
// ORIGINAL disk on Hatari (TOS 1.62, frameskip 0): apps/naos_nitrowave_ref.json.gz,
// from prototypes/naos_nitrowave_re/make_ref.py -- the BATTLETEC menu's frames
// 1, 2, 7, 50, 151, 180 (the scroller paused on 's'), 400, 714..716 (the path
// starting over) and 900, 1100, one VBL a frame, mapped to the 400x280 plane.
//   frames   every pixel of the plane = the capture's colour (ST colour words)
//   music    the cart asks for big_sprite.sndh #1 (the menu's own tune)
//   keys     Space asks for the menu; no zg.mem allocation refused
//   node apps/naos_nitrowave_headless.mjs [outdir]
//   node apps/naos_nitrowave_headless.mjs --break late|shift
//            each frame held against the NEXT VBL's capture / the plane read
//            one pixel to the right: passes only if caught
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { gunzipSync, inflateSync } from "node:zlib";
import { performance } from "node:perf_hooks";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const BREAKS = ["late", "shift"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/naos_nitrowave";
const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const VBL_MS = 20;
const MUSIC = "big_sprite.sndh";
const K_SPACE = 32;

async function boot(cart) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const noop = () => {};
    const cartBytes = await readFile(cart);
    const hw = Object.fromEntries(Object.entries(machine).filter(([k]) => k.startsWith("hwRam") || k.startsWith("hwRomRam")));
    demo = (await WebAssembly.instantiate(cartBytes, {
        env: {
            memory, ...hw, ...rom,
            jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop, consoleLogJS: noop,
            hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit,
            audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop,
            diskReadBlock: noop, hostAudioStreamStart: noop, hostAudioFeed: noop, hostAudioStreamStop: noop,
        },
    })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

const ref = JSON.parse(gunzipSync(await readFile("apps/naos_nitrowave_ref.json.gz")));
const unz = (s) => inflateSync(Buffer.from(s, "base64"));
const base = unz(ref.base);
const want = new Map([[ref.first, base]]);
for (const [k, v] of Object.entries(ref.frames)) want.set(Number(k), unz(v).map((b, i) => b ^ base[i]));
// the plane's colour, back to the ST word (c * 255 / 7), to its first index
const canon = new Map();
ref.palette.forEach((w, i) => { if (!canon.has(w)) canon.set(w, i); });

const { memory, machine, demo } = await boot("docs/demo-naos_nitrowave.wasm");
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight(), XS = W / 400;

function plane() {
    machine.hwRenderPlane(0);
    const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
    const out = new Uint8Array(400 * H);
    const dx = broke === "shift" ? 1 : 0;
    for (let y = 0; y < H; y++) for (let x = 0; x < 400; x++) {
        const i = (y * W + Math.min(x + dx, 399) * XS) * 4;
        const word = (Math.round(px[i] * 7 / 255) << 8) | (Math.round(px[i + 1] * 7 / 255) << 4) | Math.round(px[i + 2] * 7 / 255);
        out[y * 400 + x] = canon.has(word) ? canon.get(word) : 255;
    }
    return out;
}

async function ppm(path, idx) {
    const rgb = (w, s) => ((w >> s) & 7) * 255 / 7;
    const hdr = Buffer.from(`P6\n400 ${H}\n255\n`);
    const body = Buffer.alloc(400 * H * 3);
    idx.forEach((v, i) => { const w = ref.palette[v] ?? 0x700; body[3 * i] = rgb(w, 8); body[3 * i + 1] = rgb(w, 4); body[3 * i + 2] = rgb(w, 0); });
    await writeFile(path, Buffer.concat([hdr, body]));
}

const errors = [];
const passed = [];
await mkdir(outdir, { recursive: true });
const frames = [...want.keys()].sort((a, b) => a - b);
let frame = 0;
for (const k of frames) {
    while (frame < k) { demo.frame(VBL_MS); frame++; }
    const got = plane();
    const exp = want.get(broke === "late" ? frames[frames.indexOf(k) + 1] ?? k : k);
    let bad = 0, first = null;
    for (let i = 0; i < got.length; i++) if (got[i] !== exp[i]) { bad++; first ??= `x ${i % 400} y ${(i / 400) | 0}: ${got[i]} not ${exp[i]}`; }
    if (bad) errors.push(`frame ${k}: ${bad} pixels differ from Hatari (first at ${first})`);
    else passed.push(k);
    await ppm(`${outdir}/${String(k).padStart(5, "0")}.ppm`, got);
}
console.log(`  frames: ${passed.length} of ${frames.length} = the original on Hatari, pixel for pixel (${passed.join(", ")})`);

const dec = new TextDecoder();
const song = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
if (song !== MUSIC || demo.songTune() !== 1) errors.push(`music: asked for ${song} #${demo.songTune()}, not ${MUSIC} #1`);
else console.log(`  music: ${song} #1`);
if (machine.hwRamAllocFailures() !== 0) errors.push(`alloc: ${machine.hwRamAllocFailures()} zg.mem requests refused`);

let best = Infinity;
for (let r = 0; r < 5; r++) {
    const t0 = performance.now();
    for (let i = 0; i < 200; i++) demo.frame(VBL_MS);
    best = Math.min(best, (performance.now() - t0) / 200);
}
console.log(`  frame cost (warm, best of 5x200, one VBL a frame): ${best.toFixed(3)} ms`);
demo.key(K_SPACE);
if (demo.pollCartRequest() !== -1) errors.push("keys: Space does not ask for the menu");

if (broke) {
    console.log(errors.length ? `naos_nitrowave: PASS (--break ${broke} caught: ${errors[0]})` : `naos_nitrowave: FAILED -- --break ${broke} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `naos_nitrowave: FAILED -- ${errors.join("; ")}` : "naos_nitrowave: all pass");
process.exit(errors.length ? 1 : 0);
