// Composited-picture fingerprint: scene_hash.mjs's host loop, but hashing what the viewer SEES,
// not each plane's PFB. After every enabled plane's pass its PFB row is folded into the picture
// the way FRESCO's mixer (fpga/rtl/video/zm_video_mix.v) and the browser's stacked canvases do,
// premultiplied 8-bit source-over from the tube colour:
//     P = round(c * a / 255);  D = P + (D * (256 - a) >> 8)
// For proving a plane MERGE identical: per-plane hashes change when content moves between
// planes, the composited picture must not.
//
//   node apps/composite_hash.mjs <cart.wasm> [frames=1200] [every=10] [--disk X.zmd] [--call F:export:args]
//                                [--expect <total sha256>]   (exit 1 unless the run's total is that)
//   node apps/composite_hash.mjs --compare a.json b.json      (scene_hash.mjs's compare)
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { makeDrive } from "./scene_hash_disk.mjs";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const TUBE = [0x12, 0x10, 0x10]; // #121010, zm_video_mix.v TUBE

async function boot(cartPath, machineDir, diskPath) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile(`${machineDir}/machine-video.wasm`), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile(`${machineDir}/rom.wasm`);
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(cartPath);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hwRam") || k.startsWith("hwRomRam")) env[k] = machine[k];
    Object.assign(env, { hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit });
    if (diskPath) env.diskReadBlock = makeDrive(memory, { buf: new Uint8Array(await readFile(diskPath)) });
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

/** Fold one plane's PFB (RGBA bytes) into the picture D (RGB bytes). */
function over(pfb, D) {
    for (let i = 0, j = 0; j < D.length; i += 4, j += 3) {
        const a = pfb[i + 3];
        for (let c = 0; c < 3; c++) {
            const r = pfb[i + c] * a + 128;
            D[j + c] = (((r + (r >> 8)) >> 8) + ((D[j + c] * (256 - a)) >> 8)) & 0xff;
        }
    }
}

async function fingerprint(argv) {
    const pos = [], calls = new Map();
    let disk = null, expect = null;
    for (let i = 0; i < argv.length; i++) {
        if (argv[i] === "--disk") disk = argv[++i];
        else if (argv[i] === "--expect") expect = argv[++i];
        else if (argv[i] === "--call") {
            const [f, name, args = ""] = argv[++i].split(":");
            if (!calls.has(+f)) calls.set(+f, []);
            calls.get(+f).push([name, args === "" ? [] : args.split(",").map(Number)]);
        } else pos.push(argv[i]);
    }
    const [cart, frames = "1200", every = "10"] = pos;
    const { memory, machine, demo } = await boot(cart, process.env.MACHINE_DIR || "docs", disk);
    const px = machine.hwPhysWidth() * machine.hwPhysHeight();
    const planes = machine.hwPlanesNumber();
    const D = new Uint8Array(px * 3);
    const total = createHash("sha256");
    const samples = [];
    for (let f = 1; f <= +frames; f++) {
        for (const [name, args] of calls.get(f) ?? []) demo[name](...args);
        machine.hwClear();
        demo.frame(16.6);
        const sample = f % +every === 0;
        if (sample) for (let j = 0; j < D.length; j += 3) D.set(TUBE, j);
        for (let p = 0; p < planes; p++) {
            if (!demo.isPlaneEnabled(p)) continue;
            machine.hwRenderPlane(p); // every frame: HBL-driven state must not starve
            if (sample) over(new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), px * 4), D);
        }
        if (!sample) continue;
        const hash = createHash("sha256").update(D).digest("hex");
        total.update(hash);
        samples.push({ frame: f, hash });
    }
    const digest = total.digest("hex");
    // A cart refused a zg.mem buffer ran on a bad pointer: its fingerprint is not evidence.
    if (machine.hwRamAllocFailures()) {
        console.error(`composite_hash: ${cart}: ${machine.hwRamAllocFailures()} zg.mem allocation(s) refused`);
        process.exit(1);
    }
    if (expect === null) return console.log(JSON.stringify({ cart, frames: +frames, every: +every, samples, total: digest }));
    // --expect: the gate's form, the total pinned from the build before a change.
    const distinct = new Set(samples.map((s) => s.hash)).size;
    if (distinct < 2) {
        console.log(`FAIL ${cart}: ${distinct} distinct picture(s) in ${samples.length} samples: nothing moves`);
        process.exit(1);
    }
    if (digest !== expect) {
        console.log(`FAIL ${cart}: composited pictures over ${frames} frames hash ${digest.slice(0, 16)}, pinned ${expect.slice(0, 16)}`);
        process.exit(1);
    }
    console.log(`PASS ${cart}: ${samples.length} composited pictures over ${frames} frames (${distinct} distinct) = the pinned ${expect.slice(0, 16)}`);
}

async function compare(a, b) {
    const A = JSON.parse(await readFile(a, "utf8")), B = JSON.parse(await readFile(b, "utf8"));
    const bad = A.samples.filter((s, j) => s.hash !== B.samples[j]?.hash);
    if (A.samples.length !== B.samples.length || bad.length) {
        console.log(`DIFFER: ${bad.length}/${A.samples.length} samples, first at frame ${bad[0]?.frame}`);
        process.exit(1);
    }
    console.log(`IDENTICAL: ${A.samples.length} composited samples over ${A.frames} frames (${A.total.slice(0, 16)})`);
}

const argv = process.argv.slice(2);
if (argv[0] === "--compare") await compare(argv[1], argv[2]);
else await fingerprint(argv);
