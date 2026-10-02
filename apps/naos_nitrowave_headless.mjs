// Headless NAOS / NITROWAVE DEMO driver (cart 81). The reference is the
// ORIGINAL disk on Hatari (TOS 1.62, frameskip 0): apps/naos_nitrowave_ref.json.gz,
// from prototypes/naos_nitrowave_re/make_ref.py -- for each ported program,
// frames counted in VBLs from its start, mapped to the 400x280 plane:
//   menu  1, 2, 7, 50, 151, 180 (the scroller paused on 's'), 400, 714..716
//         (the path starting over), 900, 1100
//   F2    1, 2, 3, 60, 201 (the entry walk starts), 600, 1000, 1300, 1700
//         (the sprite's global move)
//   frames   every pixel of the plane = the capture's colour (ST colour words)
//   music    each program asks for its own tune (subtune 1)
//   keys     F2 in the menu starts the big sprite; 'F' freezes it; Space goes
//            back to the menu, which starts over; Space there asks for the
//            menu disk. No zg.mem allocation refused
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
const K = { space: 32, f2: 0xe002, f: "F".charCodeAt(0) };
const TUNES = { menu: "big_sprite.sndh", bspr: "so_watt_no_crew.sndh" };

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

const refs = JSON.parse(gunzipSync(await readFile("apps/naos_nitrowave_ref.json.gz")));
const unz = (s) => inflateSync(Buffer.from(s, "base64"));
const { memory, machine, demo } = await boot("docs/demo-naos_nitrowave.wasm");
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight(), XS = W / 400;
const errors = [];
await mkdir(outdir, { recursive: true });

/// The plane as palette indices, through each colour's ST word (c * 255 / 7)
/// to its first index in the part's palette.
function plane(ref) {
    const canon = new Map();
    ref.palette.forEach((w, i) => { if (!canon.has(w)) canon.set(w, i); });
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

async function ppm(path, ref, idx) {
    const rgb = (w, s) => ((w >> s) & 7) * 255 / 7;
    const body = Buffer.alloc(400 * H * 3);
    idx.forEach((v, i) => { const w = ref.palette[v] ?? 0x700; body[3 * i] = rgb(w, 8); body[3 * i + 1] = rgb(w, 4); body[3 * i + 2] = rgb(w, 0); });
    await writeFile(path, Buffer.concat([Buffer.from(`P6\n400 ${H}\n255\n`), body]));
}

function diff(got, exp) {
    let bad = 0, first = null;
    for (let i = 0; i < got.length; i++) if (got[i] !== exp[i]) { bad++; first ??= `x ${i % 400} y ${(i / 400) | 0}: ${got[i]} not ${exp[i]}`; }
    return bad ? `${bad} pixels differ (first at ${first})` : null;
}

/// Run the part on screen from its first VBL and hold its frames to Hatari's.
async function frames(name) {
    const ref = refs[name];
    const base = unz(ref.base);
    const want = new Map([[ref.first, base]]);
    for (const [k, v] of Object.entries(ref.frames)) want.set(Number(k), unz(v).map((b, i) => b ^ base[i]));
    const ks = [...want.keys()].sort((a, b) => a - b);
    const passed = [];
    let frame = 0;
    for (const k of ks) {
        while (frame < k) { demo.frame(VBL_MS); frame++; }
        const got = plane(ref);
        const bad = diff(got, want.get(broke === "late" ? ks[ks.indexOf(k) + 1] ?? k : k));
        if (bad) errors.push(`${name} frame ${k}: ${bad}`);
        else passed.push(k);
        await ppm(`${outdir}/${name}_${String(k).padStart(5, "0")}.ppm`, ref, got);
    }
    console.log(`  ${name}: ${passed.length} of ${ks.length} frames = the original on Hatari, pixel for pixel (${passed.join(", ")})`);
    const dec = new TextDecoder();
    const song = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    if (song !== TUNES[name] || demo.songTune() !== 1) errors.push(`${name} music: asked for ${song} #${demo.songTune()}, not ${TUNES[name]} #1`);
    else console.log(`  ${name} music: ${song} #1`);
}

function cost(label) {
    let best = Infinity;
    for (let r = 0; r < 5; r++) {
        const t0 = performance.now();
        for (let i = 0; i < 100; i++) demo.frame(VBL_MS);
        best = Math.min(best, (performance.now() - t0) / 100);
    }
    console.log(`  ${label} frame cost (warm, best of 5x100, one VBL a frame): ${best.toFixed(3)} ms`);
}

/// 'F' stops the part's motion, a second 'F' lets it go on.
function freeze() {
    demo.key(K.f);
    const a = plane(refs.bspr);
    for (let i = 0; i < 10; i++) demo.frame(VBL_MS);
    const b = plane(refs.bspr);
    demo.key(K.f);
    for (let i = 0; i < 10; i++) demo.frame(VBL_MS);
    const c = plane(refs.bspr);
    if (diff(a, b)) errors.push("keys: 'F' does not freeze the big sprite");
    else if (!diff(b, c)) errors.push("keys: a second 'F' does not let the big sprite go on");
    else console.log("  keys: 'F' freezes the big sprite and lets it go");
}

await frames("menu");
cost("menu");
demo.key(K.f2);
await frames("bspr");
cost("F2");
freeze();
demo.key(K.space);
if (demo.pollCartRequest() !== 0) errors.push("keys: Space in F2 asks for another cart instead of the menu screen");
const menu1 = diff(plane(refs.menu), unz(refs.menu.base)); // not run yet: the frame F2 left
demo.frame(VBL_MS);
if (diff(plane(refs.menu), unz(refs.menu.base))) errors.push(`keys: Space in F2 does not restart the menu (${menu1 ? "" : "no change; "}${diff(plane(refs.menu), unz(refs.menu.base))})`);
demo.key(K.space);
if (demo.pollCartRequest() !== -1) errors.push("keys: Space in the menu does not ask for the menu disk");
if (machine.hwRamAllocFailures() !== 0) errors.push(`alloc: ${machine.hwRamAllocFailures()} zg.mem requests refused`);

if (broke) {
    console.log(errors.length ? `naos_nitrowave: PASS (--break ${broke} caught: ${errors[0]})` : `naos_nitrowave: FAILED -- --break ${broke} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `naos_nitrowave: FAILED -- ${errors.join("; ")}` : "naos_nitrowave: all pass");
process.exit(errors.length ? 1 : 0);
