// Framebuffer fingerprint for ANY cart: boots the sealed machine the way
// sealed-loader.js does, runs frames at a fixed dt and SHA-256es every plane's
// raw physical output (hwRenderPlane → RGBA, HBL handlers included) every K
// frames. It exists to prove that a library migration is byte-identical: take
// a fingerprint before the change, rebuild, take one after, compare.
//
//   node apps/scene_hash.mjs <cart.wasm> [frames=1200] [every=10] [--call F:export:arg,...] [--disk X.zmd] [--composite] [--song-clock]
//                            [--data-disk X.zmd [--program]] [--kos X.zmd|none [--post-frames N] [--warm]] [--c-image X.img]
//   node apps/scene_hash.mjs --compare a.json b.json
//
// Writes JSON to stdout: { cart, frames, every, samples: [{frame, hash}], total }.
// `--call 300:key:32` invokes demo.key(32) before frame 300 (repeatable, for
// scenes that wait on input). `--call 1:set8@getAudioModePointer:2` instead writes the
// bytes 2 (comma list) at the address that export returns, as the browser's loader
// mirrors the audio state (mode, YM registers) into the cart. `--disk X.zmd` mounts X in the drive, as the
// browser does; without it diskReadBlock is a stub answering 0 (no disk).
// `--data-disk X.zmd` mounts a data disk and, after each frame, does what the browser
// does for GEM over one (insertDisk, the FAT listing; scene_hash_disk.mjs); `--program`: the
// cart is a program GEM launched off it (swapCart req 3), which the browser hands no listing.
// `--compare` exits 1 on the first differing frame.
// A .zmd in the cart's place runs its executable BOOT SECTOR (format v2: the disk's first 1 KB,
// as docs/zmdisk.js slices it), as the browser runs it before the disk's cart; the board runs
// the same bytes through its interpreter (fpga/host/bootsec.h, `host --bootsec X.zmd`).
// `--kos X.zmd|none` boots as KOS powers on (scene_hash_kos.mjs): the ROM's POST for
// --post-frames frames (default 180, 0 = none), then drive A decides what runs: X's boot
// sector, X's cart (the cart given must be it) or the desktop (the cart given: demo-gem.wasm).
// `--c-image X.img` is KOS's C: (docs/KOS_FAT.md F5): env.kosDriveRead serves X's sectors by the
// page's rules (docs/sealed-loader.js kosDriveRead, the page's ?c=X); without it, 0 (no C:). The
// cart's writes go into it (env.kosFileOp, docs/kos-cfile.js); `--c-out Y.img` saves it after the run.
// `--composite` hashes only the COMPOSED picture (each enabled plane's physical
// render, borders included, stacked as the browser's canvases are: stackOver),
// not each plane: it proves a change that moves pixels between planes (merging
// two into one) shows the same frames.
// `--song-clock` sets zigos.song_ms (what the host mirrors from the playing tune)
// to frame * 1000 / 60 before each frame, for carts that sync to the music.
import { readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { makeCDrive, makeCFile, makeDataDisk, makeDrive, mountDataDisk } from "./scene_hash_disk.mjs";
import { kosBoot } from "./scene_hash_kos.mjs";
import { writePng } from "./scene_png.mjs";

const PAGES = 128; // SHARED_PAGES in machine/sdk/memmap.zig
let cImage = null; // --c-image: KOS's C:
let cOut = null; // --c-out: where the C: image goes after the run, with what the cart wrote

async function boot(cartPath, machineDir, diskPath, dataDiskPath, program, kos) {
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
    const file = await readFile(cartPath);
    const cartBytes = cartPath.endsWith(".zmd") ? file.subarray(0, 1024) : file;
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
        hwRomRamFree: machine.hwRomRamFree, hwDeskAvailable: machine.hwDeskAvailable, hwAstro: machine.hwAstro,
        ...rom,
    };
    if (cImage) env.kosDriveRead = makeCDrive(memory, cImage);
    env.kosFileOp = cImage ? makeCFile(memory, cImage) : () => -46; // C:'s writes (docs/KOS_GEMDOS.md §7), into the image
    // One cart over the shared memory; KOS instantiates the boot sector and then the cart.
    const instantiate = async (bytes) => {
        const e = { ...env };
        for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(bytes)))
            if (imp.module === "env" && !(imp.name in e)) e[imp.name] = noop;
        demo = (await WebAssembly.instantiate(bytes, { env: e })).instance.exports;
        machine.hwSetCartHigh(cartRam(bytes).high ?? 0);
        return demo;
    };
    if (kos) {
        const k = await kosBoot({ memory, machine, rom, env, cartBytes, instantiate, drivePath: kos.drive, postFrames: kos.post, warm: kos.warm });
        return { memory, machine, demo: k, kos: k };
    }
    if (diskPath) env.diskReadBlock = makeDrive(memory, { buf: new Uint8Array(await readFile(diskPath)) });
    const mounted = dataDiskPath ? await mountDataDisk(dataDiskPath) : null;
    if (mounted) env.diskReadBlock = makeDrive(memory, mounted);
    await instantiate(cartBytes);
    machine.hwInit();
    demo.boot();
    demo.skipBoot?.(); // a boot sector has none: the browser boots it as it is
    const dataDisk = mounted ? makeDataDisk(memory, rom, mounted, program) : null;
    return { memory, machine, demo, dataDisk };
}

// The browser shows each enabled plane's PFB snapshot on its own canvas, stacked
// in plane order: a pixel is the topmost snapshot's that is not transparent
// (alpha 0), else the page behind (left 0 here).
function stackOver(comp, snap) {
    for (let i = 0; i < snap.length; i++) if (snap[i] >>> 24) comp[i] = snap[i];
}

// The desk picture (HW 1.17.0): the machine renders it as two 640x240 RGBA halves in the PFB.
const DESK_W = 640, DESK_H = 480, DESK_HALF = DESK_W * (DESK_H / 2) * 4;
function deskPicture(memory, machine) {
    const out = new Uint8Array(2 * DESK_HALF);
    for (let half = 0; half < 2; half++) {
        machine.hwRenderDesk(half);
        out.set(new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), DESK_HALF), half * DESK_HALF);
    }
    return out;
}

// The bars around it (REG_BACKGROUND, alpha 255) as the 4 bytes the board shows: R, G, B, 255.
function deskBars(machine) {
    const b = new Uint8Array(4);
    new DataView(b.buffer).setUint32(0, machine.hwDeskBars() >>> 0, true);
    return b;
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
    let disk = null, dataDisk = null, program = false, composite = false, songClock = false, kos = null;
    for (let i = 0; i < argv.length; i++) {
        if (argv[i] === "--call") callSpecs.push(argv[++i]);
        else if (argv[i] === "--composite") composite = true;
        else if (argv[i] === "--song-clock") songClock = true;
        else if (argv[i] === "--disk") disk = argv[++i];
        else if (argv[i] === "--data-disk") dataDisk = argv[++i];
        else if (argv[i] === "--program") program = true;
        else if (argv[i] === "--kos") kos = { post: 180, ...kos, drive: argv[++i] };
        else if (argv[i] === "--post-frames") kos = { ...kos, post: Number(argv[++i]) };
        else if (argv[i] === "--warm") kos = { post: 180, ...kos, warm: true };
        else if (argv[i] === "--c-image") cImage = new Uint8Array(await readFile(argv[++i]));
        else if (argv[i] === "--c-out") cOut = argv[++i];
        else pos.push(argv[i]);
    }
    const [cart, frames = "1200", every = "10"] = pos;
    const N = Number(frames), K = Number(every);
    const calls = parseCalls(callSpecs);
    if (kos && !kos.drive) throw new Error("--post-frames needs --kos");
    const { memory, machine, demo, dataDisk: step, kos: k } = await boot(cart, process.env.MACHINE_DIR || "docs", disk, dataDisk, program, kos);
    const size = machine.hwPhysWidth() * machine.hwPhysHeight() * 4;
    const planes = machine.hwPlanesNumber();
    const total = createHash("sha256");
    const samples = [];
    const comp = new Uint32Array(size >> 2);
    const [shotAt, shotPath] = (process.env.SCENE_PNG ?? "0:").split(/:(.*)/).map((x, i) => (i ? x : Number(x)));
    for (let f = 1; f <= N; f++) {
        for (const [name, args] of calls.get(f) ?? []) {
            const cur = k ? k.current() : demo; // KOS: the cart running now
            if (name.startsWith("set8@")) { // the bytes `args` at the address export `name` returns
                new Uint8Array(memory.buffer).set(args, cur[name.slice(5)]());
                continue;
            }
            if (typeof cur?.[name] !== "function") throw new Error(`cart has no export ${name}`);
            cur[name](...args);
        }
        // The host loop, exactly (docs/sealed-loader.js): clear, frame, then render
        // every ENABLED plane EVERY frame. HBL handlers only run inside
        // hwRenderPlane, so sampling-only rendering would starve HBL-driven state.
        const sample = f % K === 0;
        const h = sample ? createHash("sha256") : null;
        if (k) await k.between(); // KOS: a phase change, then kosTick (sealed-loader.js's frame)
        if (songClock) new Uint32Array(memory.buffer, demo.getSongMsPointer(), 1)[0] = Math.floor((f * 1000) / 60);
        machine.hwClear();
        demo.frame(16.6);
        step?.(demo); // --data-disk: the browser's step after the frame
        const png = shotAt === f; // SCENE_PNG=F:path: this frame's picture as a PNG (apps/scene_png.mjs)
        if (machine.hwDeskActive?.()) { // the desk mode (HW 1.17.0): "desk", the bars, the 640x480 picture
            const desk = deskPicture(memory, machine); // (composite or not: nothing to compose)
            h?.update("desk");
            h?.update(deskBars(machine)); // REG_BACKGROUND: a colour change is a new hash
            h?.update(desk);
            if (png) writePng(shotPath, desk, DESK_W, DESK_H);
        } else {
            if (composite || png) comp.fill(0);
            for (let p = 0; p < planes; p++) {
                if (!demo.isPlaneEnabled(p)) { if (!composite) h?.update(`off${p}`); continue; }
                machine.hwRenderPlane(p);
                if (composite || png) stackOver(comp, new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), size >> 2));
                else h?.update(new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), size));
            }
            if (composite) h?.update(new Uint8Array(comp.buffer));
            if (png) writePng(shotPath, new Uint8Array(comp.buffer), machine.hwPhysWidth(), machine.hwPhysHeight());
        }
        if (!sample) continue;
        const hash = h.digest("hex");
        total.update(hash);
        samples.push({ frame: f, hash });
    }
    console.log(JSON.stringify({ cart, frames: N, every: K, calls: callSpecs, samples, total: total.digest("hex") }));
    if (cOut && cImage) await writeFile(cOut, cImage);
    // A cart that takes its buffers from the RAM arena (zg.mem) and was refused
    // one ran on a bad pointer: its fingerprint is not evidence of anything.
    const refused = machine.hwRamAllocFailures();
    if (refused) {
        console.error(`scene_hash: ${cart}: ${refused} zg.mem allocation(s) refused`);
        process.exit(1);
    }
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
