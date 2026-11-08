// The BARD queue on the page, as apps/bard_queue_check.mjs runs it: the cart (docs/demo-bard_sid.wasm)
// over the real machine + ROM, the loader's own hostBardAttach / bardFrame / bardDrain / bardPublish
// (docs/sealed-loader.js) and the worklet's own bardQueue / bardState (docs/audio-worklet-sealed.js),
// taken from their sources, over the real audio modules. The worklet renders 128-sample blocks and
// answers every fourth, as process() does; a frame is 735 samples.
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const FRAME = 735, BLOCK = 128;

function fn(src, name, mutate) {
    const m = src.match(new RegExp(`^function ${name}\\([^)]*\\) \\{[\\s\\S]*?^\\}\\n`, "m"));
    if (!m) throw new Error(`docs/sealed-loader.js has no function ${name}`);
    return mutate ? mutate(m[0]) : m[0];
}

function proto(src, name) {
    const m = src.match(new RegExp(`^ZigAudioSealedProcessor\\.prototype\\.${name} = function \\([^)]*\\) \\{[\\s\\S]*?^\\};\\n`, "m"));
    if (!m) throw new Error(`docs/audio-worklet-sealed.js has no ${name}`);
    return m[0];
}

/** The loader's BARD functions over `memory` and `audioNode`; `brk` mutates bardDrain. */
export async function loaderBard(memory, audioNode, brk) {
    const src = await readFile("docs/sealed-loader.js", "utf8");
    const mutants = {
        stamp: (s) => s.replace("out.push(u[e], u[e + 1]", "out.push(u[e + 1] >= 0xD400 ? u[e] + 2 : u[e], u[e + 1]"), // the writes two samples late
        reg: (s) => s.replace("u[e + 1], u[e + 2], 0)", "u[e + 1] >= 0xD400 ? u[e + 1] + 1 : u[e + 1], u[e + 2], 0)"),
    };
    const drain = fn(src, "bardDrain", mutants[brk]);
    if (brk && drain === fn(src, "bardDrain")) throw new Error(`--break ${brk}: the mutant changed nothing`);
    const body = ["hostBardAttach", "flushBardOpen", "bardFrame", "bardPublish"].map((n) => fn(src, n)).join("\n") + drain;
    return new Function("memory", "audioNode",
        `let bardCart = null; ${body}; return { hostBardAttach, bardFrame, bardDrain, bardPublish, block: () => bardCart && bardCart.block };`)(memory, audioNode);
}

async function audioModules() {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    return { memory, m, a };
}

async function workletBard(snd) {
    const src = await readFile("docs/audio-worklet-sealed.js", "utf8");
    const P = new Function(`const ZigAudioSealedProcessor = { prototype: {} };
        ${proto(src, "bardQueue")}${proto(src, "bardState")} return ZigAudioSealedProcessor.prototype;`)();
    return Object.assign(Object.create(P), { demo: snd.a, memory: snd.memory });
}

async function bootCart(path, env0) {
    const memory = new WebAssembly.Memory({ initial: 128, maximum: 128 });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(path);
    const env = { memory, ...rom, ...env0(memory) };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => 0;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, demo };
}

/** `frames` frames of the cart on the page: the left channel as s16 (the native host's rounding), the
 * commands the loader took, and the players' counters. `keys`: {frame: digit - 1}. */
export async function pageRun(frames, { brk = null, keys = {} } = {}) {
    const snd = await audioModules(), proc = await workletBard(snd);
    const log = []; // every command the loader posted, as {t, addr, value, 0} words
    const audioNode = { port: { postMessage: (msg) => { if (msg.words) log.push(...new Uint32Array(msg.words)); proc.bardQueue(msg); } } };
    let loader = null, commands = 0;
    const cart = await bootCart("docs/demo-bard_sid.wasm", () => ({
        hostBardAttach: (b, lead) => loader.hostBardAttach(b, lead),
    }));
    loader = await loaderBard(cart.memory, audioNode, brk);
    const left = new Int16Array(frames * FRAME + BLOCK);
    let done = 0, blocks = 0;
    for (let f = 0; f < frames; f++) {
        if (f in keys) cart.demo.setShadeMode(keys[f]);
        cart.demo.frame(16.6);
        const b = loader.block();
        if (b) commands += ((new Uint32Array(cart.memory.buffer)[(b >>> 2) + 4] - new Uint32Array(cart.memory.buffer)[(b >>> 2) + 5]) >>> 0);
        loader.bardFrame();
        for (; done < (f + 1) * FRAME; done += BLOCK) {
            snd.a.audioRender(BLOCK);
            const l = new Float32Array(snd.memory.buffer, snd.m.audioLeftPtr(), BLOCK);
            for (let i = 0; i < BLOCK; i++) left[done + i] = Math.max(-32768, Math.min(32767, Math.floor(l[i] * 32768)));
            const st = (blocks++ & 3) === 0 ? proc.bardState() : null;
            if (st && loader.block()) loader.bardPublish(new Uint32Array(cart.memory.buffer), loader.block() >>> 2, st);
        }
    }
    const a = snd.a, blk = loader.block();
    const head = blk ? new Uint32Array(cart.memory.buffer, blk, 16) : new Uint32Array(16);
    const ring = blk ? new Uint32Array(cart.memory.buffer, blk + 64 + 16 * head[1], 4 * head[2]) : new Uint32Array(0);
    return {
        left: left.subarray(0, frames * FRAME), commands, mode: a.audioMode(), log: Uint32Array.from(log),
        events: Array.from({ length: ring.length / 4 }, (_, i) => Array.from(ring.subarray(4 * i, 4 * i + 3))), // the ring as it is
        stats: { applied: a.audioBardApplied(), pending: a.audioBardPending(), refused: a.audioBardRefused(), dropped: a.audioBardDropped(),
                 resyncs: a.audioBardResyncs(), closed: a.audioBardClosedDrops(), events: head[9], lost: head[11],
                 cartDropped: head[6], anchored: head[8] },
    };
}

/** The page's sound side for any cart that opens the BARD queue (apps/sidwizard_bard_check.mjs, ports_headless):
 * the loader's hostBardAttach / bardFrame / bardPublish and the worklet's bardQueue / bardState over the real
 * audio modules, as pageRun runs them. `hostBardAttach` goes in the cart's env; after each cart frame, `frame()`
 * takes the frame's commands and renders its samples (735 by default; 128-sample blocks, the state every fourth); `left()`
 * is everything rendered so far (s16, the native host's rounding). `brk` mutates the loader's bardDrain. */
export async function pageSound(memory, { brk = null, frames = 2000 } = {}) { // frames: of 735 samples, the most it renders
    const snd = await audioModules(), proc = await workletBard(snd);
    const log = []; // every command the loader posted, {t, addr, value, 0} words
    const audioNode = { port: { postMessage: (msg) => { if (msg.words) log.push(...new Uint32Array(msg.words)); proc.bardQueue(msg); } } };
    const loader = await loaderBard(memory, audioNode, brk);
    const left = new Int16Array(frames * FRAME + BLOCK);
    let done = 0, blocks = 0, f = 0;
    return {
        hostBardAttach: (b, lead) => loader.hostBardAttach(b, lead),
        frame(samples = FRAME) {
            loader.bardFrame();
            f += samples;
            for (; done < f && done + BLOCK <= left.length; done += BLOCK) {
                snd.a.audioRender(BLOCK);
                const l = new Float32Array(snd.memory.buffer, snd.m.audioLeftPtr(), BLOCK);
                for (let i = 0; i < BLOCK; i++) left[done + i] = Math.max(-32768, Math.min(32767, Math.floor(l[i] * 32768)));
                const st = (blocks++ & 3) === 0 ? proc.bardState() : null;
                if (st && loader.block()) loader.bardPublish(new Uint32Array(memory.buffer), loader.block() >>> 2, st);
            }
        },
        left: () => left.subarray(0, Math.min(done, f)),
        commands: () => Uint32Array.from(log),
        stats: () => ({ mode: snd.a.audioMode(), applied: snd.a.audioBardApplied(), refused: snd.a.audioBardRefused(),
            dropped: snd.a.audioBardDropped(), resyncs: snd.a.audioBardResyncs() }),
    };
}
