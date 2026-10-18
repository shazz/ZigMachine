// Headless check: ST Replay's two outputs (Alt = ALTernate O/P, apps/zig/scenes/st_replay_play.zig).
//
//   INTERNAL  the cart feeds the stream ring every frame (zg.audioStreamStart / audioFeed)
//   EXTERNAL  the cart hands the whole sample over once (zg.samplePlay: sfx queue op 6) and
//             the audio thread refills the ring itself (docs/audio-worklet-sealed.js refillSample)
//
// 1. The cart: SAMPLE.RAW loaded off its disc, SPACE plays INTERNAL (a stream, an eighth of a
//    second fed at once); Alt switches to EXTERNAL mid-replay (the stream stops, ONE samplePlay of
//    the whole sample, no feed after it); SPACE stops it (op 7); Q + F10 plays it looped.
// 2. The worklet, run here with a stand-in AudioWorkletProcessor: a samplePlay sounds exactly as
//    the same bytes fed to the stream ring at once (the two outputs are the same sound), ends by
//    itself, loops when asked, and stops on sampleStop.
//
//   node apps/st_replay_outputs_check.mjs [--break refill]   # --break: the worklet never refills
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112, BLOCK = 512, RATE = 10000, K_ALT = 0xe013, K_F10 = 0xe00a;
const BREAK = process.argv.includes("--break");
const errors = [];
const expect = (ok, what) => { console.log(`  ${ok ? "ok  " : "FAIL"} ${what}`); if (!ok) errors.push(what); };

function findFile(disk, name) { // a FAT entry off a ZigMachine disk (v2 descriptor at $400, else v1 at $000)
    const dv = new DataView(disk.buffer, disk.byteOffset, disk.byteLength);
    const magic = (off) => new TextDecoder().decode(disk.subarray(off, off + 6)) === "ZMDISK";
    const [count, fat] = magic(0x400) ? [dv.getUint16(0x4f4, true), 0x800] : magic(0) ? [dv.getUint16(0x2e4, true), 0x300] : [0, 0];
    for (let i = 0; i < count; i++) {
        const e = fat + i * 32, raw = disk.subarray(e, e + 16), end = raw.indexOf(0);
        if (new TextDecoder().decode(raw.subarray(0, end < 0 ? 16 : end)) === name)
            return { start: dv.getUint32(e + 0x10, true), len: dv.getUint32(e + 0x14, true) };
    }
    return null;
}

async function bootCart(disk) { // the machine, the ROM and the cart over one memory, as stream_pacing_check.mjs
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
    const cartBytes = await readFile("docs/demo-st_replay.wasm");
    const io = { starts: 0, stops: 0, feeds: [] };
    const env = {
        memory, ...rom,
        diskReadBlock: (block, dst) => {
            const src = disk.subarray(block * BLOCK, block * BLOCK + BLOCK);
            new Uint8Array(memory.buffer, dst, src.length).set(src);
            return src.length;
        },
        hostAudioStreamStart: () => { io.starts++; },
        hostAudioFeed: (ptr, len) => { io.feeds.push([ptr, len]); },
        hostAudioStreamStop: () => { io.stops++; },
    };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    // One frame, then the sfx queue as sealed-loader.js postSfx reads it: [op, a, ptr, len, rate].
    const frame = () => {
        demo.frame(1000 / 60);
        const n = demo.pollSfx(), dv = new DataView(memory.buffer, demo.sfxEntriesPtr(), n * 16);
        return Array.from({ length: n }, (_, i) => [0, 1, 4, 8, 12].map((o, j) =>
            j < 2 ? dv.getUint8(i * 16 + o) : dv.getUint32(i * 16 + o, true)));
    };
    return { demo, io, frame };
}

async function checkCart() {
    const disk = new Uint8Array(await readFile("docs/demo-st_replay.zmd"));
    const f = findFile(disk, "SAMPLE.RAW");
    if (!f) throw new Error("SAMPLE.RAW is not on docs/demo-st_replay.zmd");
    const { demo, io, frame } = await bootCart(disk);
    const frames = (n) => { const q = []; for (let i = 0; i < n; i++) q.push(...frame()); return q; };
    frames(3);
    demo.key(0x6c); // L: the ITEM SELECTOR, the name typed, OK clicked
    frames(3);
    for (const ch of "SAMPLE.RAW") demo.key(ch.charCodeAt(0));
    demo.pointer(416, 127, 1);
    frames(3);
    demo.pointer(416, 127, 0);
    frames(3);
    demo.key(0x20); // SPACE: INTERNAL
    const q1 = frames(30);
    const pcm = io.feeds[0]?.[0];
    expect(io.starts === 1 && io.feeds[0]?.[1] === RATE / 8, "INTERNAL: SPACE starts the stream with an eighth of a second fed");
    expect(q1.length === 0 && io.feeds.length > 20, "INTERNAL: the cart feeds every frame, nothing on the sfx queue");
    const fed = io.feeds.length;
    demo.key(K_ALT); // to EXTERNAL, mid-replay
    const q2 = frames(60);
    expect(io.stops === 1 && io.starts === 1, "Alt: the stream stops, no stream starts again");
    expect(q2.length === 1 && q2[0].join() === [6, 0, pcm, f.len, RATE].join(),
        `Alt: ONE samplePlay of the whole sample (${q2.map((e) => e.join(" ")).join(" | ")})`);
    expect(io.feeds.length === fed, "EXTERNAL: the cart feeds nothing while the sample plays");
    demo.key(0x20); // SPACE: stop
    const q3 = frames(2);
    expect(q3.length === 1 && q3[0][0] === 7 && io.stops === 1, "EXTERNAL: SPACE stops it (sampleStop, not a stream stop)");
    demo.key(0x71); // Q: loop mode on
    demo.key(K_F10);
    const q4 = frames(2);
    expect(q4.length === 1 && q4[0][0] === 6 && q4[0][1] === 1, "EXTERNAL: Q then F10 plays it looped");
    demo.key(K_ALT); // back to INTERNAL, still playing
    const q5 = frames(2);
    expect(q5.length === 1 && q5[0][0] === 7 && io.starts === 2, "Alt again: sampleStop, the stream starts again");
}

// The worklet in node: AudioWorkletProcessor's port, registerProcessor's class.
async function bootWorklet() {
    let Proc;
    globalThis.AudioWorkletProcessor = class { constructor() { this.port = { postMessage() {} }; } };
    globalThis.registerProcessor = (_name, cls) => { Proc = cls; };
    await import("../docs/audio-worklet-sealed.js");
    const p = new Proc({ processorOptions: {
        machineBytes: await readFile("docs/machine-audio.wasm"), demoBytes: await readFile("docs/demo-audio.wasm") } });
    for (let i = 0; i < 200 && !p.ready; i++) await new Promise((r) => setTimeout(r, 10));
    if (!p.ready) throw new Error("the worklet never came up");
    if (BREAK) p.refillSample = () => {};
    const send = (data) => p.port.onmessage({ data });
    const render = (blocks) => { // `blocks` of 128 frames, left channel
        const out = new Float32Array(blocks * 128), l = new Float32Array(128), r = new Float32Array(128);
        for (let b = 0; b < blocks; b++) { p.process([], [[l, r]]); out.set(l, b * 128); }
        return out;
    };
    return { p, send, render };
}

async function checkWorklet() {
    const smp = new Uint8Array(3000).map((_, i) => ((i / 5) & 1 ? 100 : -100) & 0xff); // 1 kHz at 10 kHz, 0.3 s
    const w = await bootWorklet();
    w.send({ type: "streamStart", rate: RATE });
    w.send({ type: "streamFeed", bytes: smp.slice().buffer });
    const fed = w.render(100); // 0.29 s: the fed bytes
    w.send({ type: "streamStop" });
    w.send({ type: "samplePlay", bytes: smp.slice().buffer, rate: RATE, loop: 0 });
    const played = w.render(100);
    const loud = played.reduce((m, v) => Math.max(m, Math.abs(v)), 0);
    expect(loud > 0.1 && fed.every((v, i) => v === played[i]), `samplePlay sounds exactly as the same bytes fed (peak ${loud.toFixed(3)})`);
    w.render(20);
    expect(w.p.sample === null && w.render(10).every((v) => v === 0), "a one-shot sample ends by itself, the channel off");
    w.send({ type: "samplePlay", bytes: smp.slice().buffer, rate: RATE, loop: 1 });
    const looped = w.render(400); // 1.2 s: four laps
    expect(looped.subarray(looped.length - 128).some((v) => v !== 0) && w.p.sample !== null, "a looped sample still plays after four laps");
    w.send({ type: "sampleStop" });
    expect(w.p.sample === null && w.render(10).every((v) => v === 0), "sampleStop silences it");
}

await checkCart();
await checkWorklet();
if (BREAK) { // the mutant must be caught: a FAIL here is the pass
    const hit = errors.some((e) => e.startsWith("samplePlay sounds"));
    console.log(hit ? "st_replay_outputs: PASS (--break refill caught)" : "st_replay_outputs: FAILED -- --break refill not caught");
    process.exit(hit ? 0 : 1);
}
if (errors.length) {
    console.log(`FAIL: ${errors.length} check(s)`);
    process.exit(1);
}
console.log("ST Replay: INTERNAL feeds the stream every frame, EXTERNAL hands the sample over once and the audio side plays it ✅");
