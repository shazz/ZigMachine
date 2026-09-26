// Framebuffer fingerprint for ANY cart: boots the sealed machine the way
// sealed-loader.js does, runs frames at a fixed dt and SHA-256es every plane's
// raw physical output (hwRenderPlane → RGBA, HBL handlers included) every K
// frames. It exists to prove that a library migration is byte-identical: take
// a fingerprint before the change, rebuild, take one after, compare.
//
//   node apps/scene_hash.mjs <cart.wasm> [frames=1200] [every=10] [--call F:export:arg,...]
//   node apps/scene_hash.mjs --compare a.json b.json
//
// Writes JSON to stdout: { cart, frames, every, samples: [{frame, hash}], total }.
// `--call 300:key:32` invokes demo.key(32) before frame 300 (repeatable, for
// scenes that wait on input). `--compare` exits 1 on the first differing frame.
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig

async function boot(cartPath, machineDir) {
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

    const noop = () => {};
    const cartBytes = await readFile(cartPath);
    // Stub every host import the cart declares that we don't provide explicitly.
    const env = {
        memory,
        hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit,
        hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop,
        hwRamSize: machine.hwRamSize, hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
        hwRamAlloc: machine.hwRamAlloc, hwRamMark: machine.hwRamMark,
        hwRamRelease: machine.hwRamRelease, hwRamAllocFailures: machine.hwRamAllocFailures,
        hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
        hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
        hwRomRamFree: machine.hwRomRamFree,
        ...rom,
    };
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

function parseCalls(list) {
    const calls = new Map();
    for (const spec of list) {
        const [f, name, args = ""] = spec.split(":");
        const at = Number(f);
        if (!calls.has(at)) calls.set(at, []);
        calls.get(at).push([name, args === "" ? [] : args.split(",").map(Number)]);
    }
    return calls;
}

async function fingerprint(argv) {
    const pos = [], callSpecs = [];
    for (let i = 0; i < argv.length; i++) {
        if (argv[i] === "--call") callSpecs.push(argv[++i]);
        else pos.push(argv[i]);
    }
    const [cart, frames = "1200", every = "10"] = pos;
    const N = Number(frames), K = Number(every);
    const calls = parseCalls(callSpecs);
    const { memory, machine, demo } = await boot(cart, process.env.MACHINE_DIR || "docs");
    const size = machine.hwPhysWidth() * machine.hwPhysHeight() * 4;
    const planes = machine.hwPlanesNumber();
    const total = createHash("sha256");
    const samples = [];
    for (let f = 1; f <= N; f++) {
        for (const [name, args] of calls.get(f) ?? []) {
            if (typeof demo[name] !== "function") throw new Error(`cart has no export ${name}`);
            demo[name](...args);
        }
        // The host loop, exactly (docs/sealed-loader.js): clear, frame, then render
        // every ENABLED plane EVERY frame. HBL handlers only run inside
        // hwRenderPlane, so sampling-only rendering would starve HBL-driven state.
        const sample = f % K === 0;
        const h = sample ? createHash("sha256") : null;
        machine.hwClear();
        demo.frame(16.6);
        for (let p = 0; p < planes; p++) {
            if (!demo.isPlaneEnabled(p)) { h?.update(`off${p}`); continue; }
            machine.hwRenderPlane(p);
            h?.update(new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), size));
        }
        if (!sample) continue;
        const hash = h.digest("hex");
        total.update(hash);
        samples.push({ frame: f, hash });
    }
    console.log(JSON.stringify({ cart, frames: N, every: K, calls: callSpecs, samples, total: total.digest("hex") }));
}

async function compare(a, b) {
    const A = JSON.parse(await readFile(a, "utf8")), B = JSON.parse(await readFile(b, "utf8"));
    if (A.samples.length !== B.samples.length) {
        console.log(`DIFFER: ${A.samples.length} vs ${B.samples.length} samples`);
        process.exit(1);
    }
    for (let i = 0; i < A.samples.length; i++) {
        if (A.samples[i].hash !== B.samples[i].hash) {
            const bad = A.samples.filter((s, j) => s.hash !== B.samples[j].hash).length;
            console.log(`DIFFER: first at frame ${A.samples[i].frame}, ${bad}/${A.samples.length} samples differ`);
            process.exit(1);
        }
    }
    console.log(`IDENTICAL: ${A.samples.length} samples over ${A.frames} frames (${A.total.slice(0, 16)})`);
}

const argv = process.argv.slice(2);
if (argv[0] === "--compare") await compare(argv[1], argv[2]);
else await fingerprint(argv);
