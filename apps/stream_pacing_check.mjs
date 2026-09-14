// Headless check: streamed audio keeps up with WALL time, whatever the frame rate.
//
// The audio worklet plays the 32 KiB stream ring at the sample rate no matter how
// often the page draws. A cart that feeds it must therefore pace by the frame's
// real dt: at a fixed rate/60 a frame, or with dt clamped to 50 ms, a phone at
// 18 fps, a 144 Hz monitor or a tab hidden for 3 s leaves the song position
// drifting off the audio clock, and once it is a ring away the ring plays stale
// laps (the stutter) or overwrites what it has not played yet.
//
// Two carts stream this way, each driven through the real machine with its own disk:
//   stream     MICROMIX.RAW @ 12517 Hz: the song position is the disk block it read last
//   st_replay  SAMPLE.RAW loaded off disc (L, type the name, click OK), SPACE at 10 KHz:
//              the song position is how far into the loaded sample it has fed
// Each runs 30 s of frames at 60 Hz (the baseline), 144 Hz, a jittery 18 fps, and 60 Hz
// with one 3 s stall (the hidden tab). The position must stay within one ring of
// start + rate * elapsed wall time on EVERY frame.
//
//   node apps/stream_pacing_check.mjs [--stream cart.wasm] [--st-replay cart.wasm]
// Given origin/main's carts from before the dt pacing (git show <rev>:docs/demo-stream.wasm)
// the check must FAIL, which is how the harness proves it can.
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const RING = 32768; // STREAM_RING (audio-worklet-sealed.js streamFeed)
const BLOCK = 512, DUR = 30;
const K_ENTER_FIELD = "SAMPLE.RAW", OK_BUTTON = [416, 127]; // filesel.zig: dx 168 + 3*8 + 176 + 8 + 40, dy 24 + 12*8 + 7

const argv = process.argv.slice(2);
function flag(name) {
    const at = argv.indexOf(name);
    if (at < 0) return null;
    const v = argv[at + 1];
    if (!v) throw new Error(`${name} takes a cart path`);
    argv.splice(at, 2);
    return v;
}
const streamCart = flag("--stream") || "docs/demo-stream.wasm";
const replayCart = flag("--st-replay") || "docs/demo-st_replay.wasm";

/// A FAT entry off a ZigMachine disk image (v2 descriptor at $400, else v1 at $000).
function findFile(disk, name) {
    const dv = new DataView(disk.buffer, disk.byteOffset, disk.byteLength);
    const magic = (off) => new TextDecoder().decode(disk.subarray(off, off + 6)) === "ZMDISK";
    const [count, fat] = magic(0x400) ? [dv.getUint16(0x4f4, true), 0x800] : magic(0) ? [dv.getUint16(0x2e4, true), 0x300] : [0, 0];
    for (let i = 0; i < count; i++) {
        const e = fat + i * 32, raw = disk.subarray(e, e + 16);
        const n = new TextDecoder().decode(raw.subarray(0, raw.indexOf(0) < 0 ? 16 : raw.indexOf(0)));
        if (n === name) return { start: dv.getUint32(e + 0x10, true), len: dv.getUint32(e + 0x14, true) };
    }
    return null;
}

/// Deterministic frame timestamps (ms), as in the codef stream simulation.
function frames({ hz, jitter = 0.4, stall = null, seed = 1 }) {
    let s = seed >>> 0;
    const r = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
    const out = [];
    for (let t = 0; t < DUR * 1000;) {
        let dt = 1000 / hz + (r() - 0.5) * 2 * jitter;
        if (stall && t < stall[0] * 1000 && t + dt >= stall[0] * 1000) dt += stall[1];
        t += dt;
        out.push(t);
    }
    return out;
}

/// The machine (video + ROM) and the cart over one shared memory, the drive and the
/// stream calls wired as sealed-loader.js wires them, the stream calls recorded.
async function boot(cartPath, disk) {
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
    const cartBytes = await readFile(cartPath);
    const io = { reads: [], feeds: [], starts: 0 };
    const env = {
        memory, ...rom,
        diskReadBlock: (block, dstOff) => {
            const src = disk.subarray(block * BLOCK, block * BLOCK + BLOCK);
            if (src.length === 0) return 0;
            new Uint8Array(memory.buffer, dstOff, src.length).set(src);
            io.reads.push(block);
            return src.length;
        },
        hostAudioStreamStart: () => { io.starts++; },
        hostAudioFeed: (ptr, len) => { io.feeds.push([ptr, len]); },
        hostAudioStreamStop: () => {},
    };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { demo, io };
}

/// Drive `times` through frame(dt); position() is read after every frame. Returns
/// the worst |position - (start + rate * wall)| in bytes, and where it happened.
function drive(demo, times, rate, position) {
    const p0 = position();
    let last = 0, worst = 0, at = 0;
    for (const t of times) {
        demo.frame(t - last);
        last = t;
        const drift = position() - (p0 + rate * t / 1000);
        if (Math.abs(drift) > Math.abs(worst)) { worst = drift; at = t; }
    }
    return { worst: Math.round(worst), at: +(at / 1000).toFixed(2) };
}

async function runStream(times) {
    const disk = new Uint8Array(await readFile("docs/demo-stream.zmd"));
    const f = findFile(disk, "MICROMIX.RAW");
    if (!f) throw new Error("MICROMIX.RAW is not on docs/demo-stream.zmd");
    const first = f.start / BLOCK, blocks = Math.ceil(f.len / BLOCK);
    const { demo, io } = await boot(streamCart, disk);
    // Unwrapped song position: blocks moved forward since the previous frame (a skip
    // or the clip's loop both count), times the block size.
    let seen = 0, lastBlock = null, pos = 0;
    const position = () => {
        for (; seen < io.reads.length; seen++) {
            const b = io.reads[seen];
            if (b < first || b >= first + blocks) continue;
            pos += lastBlock === null ? (b - first + 1) * BLOCK : ((b - lastBlock + blocks) % blocks) * BLOCK;
            lastBlock = b;
        }
        return pos;
    };
    if (io.starts !== 1 || position() === 0) throw new Error("the cart did not start its stream on boot");
    return drive(demo, times, 12517, position);
}

async function runReplay(times) {
    const disk = new Uint8Array(await readFile("docs/demo-st_replay.zmd"));
    const f = findFile(disk, K_ENTER_FIELD);
    if (!f) throw new Error(`${K_ENTER_FIELD} is not on docs/demo-st_replay.zmd`);
    const { demo, io } = await boot(replayCart, disk);
    const settle = () => { for (let i = 0; i < 3; i++) demo.frame(1000 / 60); };
    settle();
    demo.key(0x6c); // 'l': the ITEM SELECTOR
    settle();
    for (const ch of K_ENTER_FIELD) demo.key(ch.charCodeAt(0));
    demo.pointer(...OK_BUTTON, 1);
    settle();
    demo.pointer(...OK_BUTTON, 0);
    settle();
    const readBefore = io.reads.length;
    demo.key(0x20); // SPACE: replay at the boot rate, 10 KHz
    if (io.starts !== 1) throw new Error(`SPACE did not start the stream (${io.starts} starts): the sample never loaded`);
    if (readBefore < f.len / BLOCK) throw new Error(`only ${readBefore} blocks read: ${K_ENTER_FIELD} did not load`);
    // The first feed starts at pcm[0]; every later one is an offset into the sample.
    const position = () => {
        if (io.feeds.length === 0) return 0;
        const [ptr, len] = io.feeds[io.feeds.length - 1];
        return ptr + len - io.feeds[0][0];
    };
    return drive(demo, times, 10000, position);
}

const SCENARIOS = [
    ["60 Hz", frames({ hz: 60 })],
    ["144 Hz", frames({ hz: 144, jitter: 0.3 })],
    ["phone 18 fps", frames({ hz: 18, jitter: 4 })],
    ["60 Hz, 3 s stall", frames({ hz: 60, stall: [10, 3000] })],
];
const errors = [];
for (const [cart, run] of [["stream", runStream], ["st_replay", runReplay]]) {
    for (const [name, times] of SCENARIOS) {
        try {
            const { worst, at } = await run(times);
            const ok = Math.abs(worst) < RING;
            console.log(`  ${cart.padEnd(9)} ${name.padEnd(17)} worst drift ${String(worst).padStart(7)} B at ${at} s ${ok ? "ok" : "FAIL"}`);
            if (!ok) errors.push(`${cart}, ${name}: the song is ${worst} B off wall time at ${at} s (more than one ${RING} B ring)`);
        } catch (e) {
            errors.push(`${cart}, ${name}: ${e.message}`);
        }
    }
}
if (errors.length) {
    for (const e of errors) console.log(`FAIL: ${e}`);
    process.exit(1);
}
console.log("stream pacing: both carts track wall time within one ring at 60 Hz, 144 Hz, 18 fps and across a 3 s stall ✅");
