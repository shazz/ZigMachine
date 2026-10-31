// KOS's power-on in the REAL browser loader (docs/sealed-loader.js + docs/kos-boot.js, run in a
// vm with the DOM stubbed, as upload_check.mjs does) against scene_hash.mjs --kos
// (apps/scene_hash_kos.mjs), frame for frame: the browser shows what node and the native host
// (fpga/tests/test_kos_boot.py) agree on. For each drive A: empty (?disk=none), a data disk
// (ST Replay's), a boot sector handing over to the OS (sysinfo's), a boot sector chainloading its
// cart (replicants_emlyn's) and a bootable disk (the tutorial's), the planes the page puts on its
// canvases, hashed as scene_hash.mjs hashes the machine's, equal its samples. A media change
// (kosMedia: window.kosInsert / kosEject) reaches the ROM's system variables. Exits 1 on the first difference.
//
// Usage: node apps/kos_boot_check.mjs [--break]
//   --break: the POST shows planes 0 and 1 in the browser (kos-boot.js mutated in the vm): the
//   check must catch it on the first frame (exit 0 when caught, 1 when missed).
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import vm from "node:vm";
import * as ZMDisk from "../docs/zmdisk.js";
import * as ZMRam from "../docs/wasm_hiwater.js";

const BREAK = process.argv.includes("--break");
const POST = 12; // ?post=: short, the POST's own frames are the same code at any length
const CASES = [ // ?disk=, the cart scene_hash.mjs boots after drive A, frames
    ["none", "demo-gem.wasm", 40], ["demo-st_replay.zmd", "demo-gem.wasm", 40],
    ["demo-sysinfo.zmd", "demo-gem.wasm", 150], ["demo-replicants_emlyn.zmd", "demo-replicants_emlyn.wasm", 270],
    ["demo-tutorial.zmd", "demo-tutorial.wasm", 40],
];

function stub() { // a DOM that accepts anything the loader does to it
    return new Proxy(function () {}, {
        get: (t, k) => (k === "then" || typeof k === "symbol") ? undefined : stub(),
        set: () => true, apply: () => stub(), construct: () => stub(),
    });
}

// The page: plane canvases whose putImageData is recorded, a fake clock and rAF.
function page(search) {
    const puts = new Map();
    const ctx2d = (p) => ({
        createImageData: (w, h) => ({ data: new Uint8ClampedArray(w * h * 4) }),
        putImageData: (img) => puts.set(p, Buffer.from(img.data)),
        clearRect: () => {},
    });
    const canvas = (p) => new Proxy(stub(), { get: (t, k) => (k === "getContext" ? () => ctx2d(p) : stub()) });
    let now = 0, raf = null;
    const doc = new Proxy(stub(), { get: (t, k) => (k === "getElementById" ? (id) => canvas(Number(id)) : stub()) });
    const win = new Proxy(stub(), {
        get: (t, k) => k === "location" ? { search } : k === "requestAnimationFrame" ? (f) => { raf = f; return 1; }
            : k === "document" ? doc : stub(),
    });
    const wasm = Object.assign(Object.create(WebAssembly), {
        instantiateStreaming: async (p, imp) => WebAssembly.instantiate(await (await p).arrayBuffer(), imp),
    });
    const ctx = vm.createContext({
        console: { log() {}, warn() {}, error: (...a) => console.error(...a) }, alert: (m) => console.error(m),
        window: win, document: doc, WebAssembly: wasm, TextDecoder, TextEncoder, URLSearchParams,
        performance: { now: () => now }, setInterval() {}, clearInterval() {}, AudioWorkletNode: stub(), AudioContext: stub(),
        fetch: async (url) => {
            const bytes = await readFile("docs/" + url.replace(/\?.*$/, ""));
            return { arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length) };
        },
        ZMDisk: { ...ZMDisk }, ZMRam: { ...ZMRam },
    });
    for (const f of ["kos-boot.js", "sealed-loader.js"]) {
        let src = execFileSync("cat", ["docs/" + f], { encoding: "utf8" });
        if (BREAK && f === "kos-boot.js") src = src.replace("isPlaneEnabled: (p) => p === 0,", "isPlaneEnabled: (p) => p <= 1,");
        vm.runInContext(src, ctx, { filename: f });
    }
    const run = (c) => vm.runInContext(c, ctx);
    const tick = (ts) => { now = ts; const f = raf; raf = null; f(ts); };
    return { puts, run, tick };
}

// A swap the frame asked for lands before the next frame, as it does in scene_hash.mjs.
async function settle(p) {
    for (let i = 0; i < 200 && p.run("swapping"); i++) await new Promise((r) => setImmediate(r));
}

// The frame's hash as scene_hash.mjs makes it: each plane's picture, or "off<p>".
function frameHash(p, planes) {
    const h = createHash("sha256");
    for (let i = 0; i < planes; i++) h.update(p.puts.has(i) ? p.puts.get(i) : `off${i}`);
    p.puts.clear();
    return h.digest("hex");
}

async function browser(disk, frames) {
    const p = page(`?disk=${disk}&post=${POST}`);
    await p.run("boot()"); // frame 1 runs inside it (start() calls the loop once)
    const planes = p.run("machine.hwPlanesNumber()");
    await settle(p);
    const out = [frameHash(p, planes)];
    for (let f = 2; f <= frames; f++) {
        p.tick((f - 1) * (1000 / 60));
        await settle(p);
        out.push(frameHash(p, planes));
    }
    return { p, out };
}

function node(disk, cart, frames) {
    const args = ["apps/scene_hash.mjs", `docs/${cart}`, String(frames), "1", "--kos", disk === "none" ? "none" : `docs/${disk}`, "--post-frames", String(POST)];
    return JSON.parse(execFileSync("node", args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] })).samples.map((s) => s.hash);
}

if (BREAK) {
    const { out } = await browser("none", 3);
    const caught = out[0] !== node("none", "demo-gem.wasm", 3)[0];
    console.log(caught ? "kos boot --break: a POST on the wrong planes is caught ✅" : "kos boot --break: MISSED ❌");
    process.exit(caught ? 0 : 1);
}

let bad = 0;
for (const [disk, cart, frames] of CASES) {
    const { out } = await browser(disk, frames);
    const ref = node(disk, cart, frames);
    const at = out.findIndex((h, i) => h !== ref[i]);
    if (at >= 0) { console.log(`FAIL  ${disk.padEnd(28)} frame ${at + 1} differs from scene_hash.mjs --kos`); bad++; }
    else console.log(`ok    ${disk.padEnd(28)} ${frames} frames = scene_hash.mjs --kos (${new Set(out).size} pictures)`);
}

// The reset button (?warm=1): no POST, straight to drive A, as scene_hash.mjs --warm.
{
    const p = page("?disk=none&warm=1");
    await p.run("boot()");
    await settle(p);
    const planes = p.run("machine.hwPlanesNumber()");
    const out = [frameHash(p, planes)];
    p.tick(1000 / 60);
    await settle(p);
    out.push(frameHash(p, planes));
    const args = ["apps/scene_hash.mjs", "docs/demo-gem.wasm", "3", "1", "--kos", "none", "--warm"];
    const ref = JSON.parse(execFileSync("node", args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] })).samples.map((s) => s.hash);
    if (out[0] !== ref[0] || out[1] !== ref[1]) { console.log("FAIL  warm reset: the page does not go straight to the desktop"); bad++; }
    else console.log("ok    warm reset (?warm=1): no POST, the desktop = scene_hash.mjs --kos none --warm");
}

// A media change while the desktop runs: the ROM counts it, the drive reads the new disk.
const { p } = await browser("none", POST + 2);
await p.run('kosMedia("demo-st_replay.zmd")');
const vars = (w) => p.run(`new Uint32Array(memory.buffer, rom.kosSysVarsPtr(), 10)[${w}]`);
const drive = vars(8), dev = vars(4);
await p.run("kosMedia(null)");
if (drive !== (1 << 8 | 1) || vars(8) !== (2 << 8) || dev !== 0 || !p.run("mountedDisk === null")) {
    console.log(`FAIL  media change: drive_a ${drive.toString(16)} then ${vars(8).toString(16)}, boot_dev ${dev}`); bad++;
} else console.log("ok    media change: insert then eject counted, the desktop's drive emptied");

console.log(bad === 0 ? "\nkos boot: the browser's power-on = scene_hash.mjs --kos on every drive ✅" : `\nkos boot: ${bad} FAILED ❌`);
process.exit(bad === 0 ? 0 : 1);
