// Headless RICK DANGEROUS driver. Boots the sealed machine the way
// docs/sealed-loader.js does, then checks the cart against the ORIGINAL GAME
// (RICKST.PRG run on the rip's 68000 harness, which the reference model
// reproduces byte for byte: apps/rick_dangerous_fixture.json.gz, from
// tools/rick_dangerous/make_fixture.py):
//   replay   recorded runs (the level walks, the deaths and GAME OVER, the
//            hall of fame name entries, the menus, the bots' runs through each
//            level), from their first key frame, in lockstep: every call
//            gets the harness's ACIA / Timer A bytes at its entry and the stick
//            and key changes during it, every VBL its Timer A bytes. Every frame
//            must take the harness's VBLs, leave the game's RAM + both screens +
//            the video base + the colour registers with the harness's CRC, make
//            the harness's play_sound requests (id, flag, dropped or not), and
//            ask the host for the SNDH subtune (or the silence) they imply.
//   live     the cart as a player runs it: the title up with its tune, FIRE
//            through the level select and the intro into level 1, the plane is
//            the ST screen through the colour registers, 50 Hz time on a 60 Hz
//            host, P pauses, Escape restarts to the title, Escape there leaves.
//   sound    rick_dangerous.sndh on the sealed audio machine: for every sound
//            id, the game's own driver in the SNDH leaves its RAM (the driver
//            state, tick after tick) where the cart's transcription leaves it.
//   resident the same, with LATER requests between the ticks (every id, the
//            shot's paired play(8,1)+play(8,0), dynamite's two $0A in one
//            frame), forwarded as the loader does: the load, then each
//            zg.sndhCall on the RUNNING driver. The RAM must still match.
//   node apps/rick_dangerous_headless.mjs [outdir]
//   --break joy     one wrong stick byte: the replay must catch it
//   --break vbl     one VBL interrupt too many: the replay must catch it
//   --break sound   the drop rule's state flipped before a sound: caught
//   --break alloc   a refused zg.mem allocation: caught
//   --break sndh    the SNDH plays the next subtune: the driver RAM check catches it
//   --break reload  every call forwarded as a reload (the old host): the
//                   resident check catches it
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { gunzipSync, inflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const CART = "docs/demo-rick_dangerous.wasm";
const MUSIC = "rick_dangerous.sndh";
const NIDS = 29;
const RESIDENT = 0x8000; // sound.s's d0 flag for a zg.sndhCall on the running driver
const RW = 800, RH = 280; // the physical frame: 320x200 at (40, 40), x doubled
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
const BREAKS = ["joy", "vbl", "sound", "alloc", "sndh", "reload"];
if (broke && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/rick_dangerous";
const fixture = JSON.parse(gunzipSync(await readFile(process.env.RICK_FIXTURE || "apps/rick_dangerous_fixture.json.gz")).toString());
const dec = new TextDecoder();

async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const env0 = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
    const rom = (await WebAssembly.instantiate(romBytes, { env: env0 })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(CART);
    const env = { ...env0, ...rom };
    for (const n of Object.keys(machine)) if (n.startsWith("hwRam") || n.startsWith("hwRomRam")) env[n] = machine[n];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

function songRequest(memory, demo) {
    if (!demo.pollSongRequest()) return null;
    const name = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    return name === "none" ? "none" : `${name}#${demo.songTune()}`;
}

/// The frame's zg.sndhCall d0s, as the loader drains them (after the request).
function sndhCalls(memory, demo) {
    const n = demo.pollSndhCalls(), out = [];
    for (let i = 0; i < n; i++) out.push(demo.sndhCallD0(i));
    const name = n ? dec.decode(new Uint8Array(memory.buffer, demo.sndhCallNamePtr(), demo.sndhCallNameLen())) : MUSIC;
    if (name !== MUSIC) out.push(`on ${name}`);
    return out;
}

/// What the host must be asked for a frame's sound log: the plays that are
/// not dropped and not the tick's own, in order. The first one while the SNDH
/// is not loaded (and the first after a sound off) is a LOAD, every later one
/// a resident zg.sndhCall; a sound off (or a load) discards the calls queued
/// before it, as ZigOS does. `resident` carries over from frame to frame.
function expectedHost(log, resident) {
    let req = null, calls = [];
    for (const e of log) {
        if (e === 0xfffff) { req = "none"; calls = []; resident = false; continue; }
        if (e & 0x50000) continue; // dropped / the tick's own
        const id = (e >> 8) & 0xff, d1 = e & 0xff, alt = (e >> 17) & 1;
        if (id >= NIDS) continue; // not in the SNDH (sound.zig)
        const sub = 1 + id + NIDS * (d1 ? 2 : alt);
        if (resident) calls.push(RESIDENT | sub);
        else { req = `${MUSIC}#${sub}`; calls = []; resident = true; }
    }
    return { req, calls, resident };
}

// ---------------------------------------------------------------- the replays
function runSize(run) {
    return (fixture.snapBytes + 3 & ~3) + 4 * (17 + run.tape.length + run.irqs.length);
}

const BREAK_AT = { joy: 120, vbl: 60, sound: null, alloc: 30 };

function breakFrame(run) {
    if (broke !== "sound") return BREAK_AT[broke] ?? -1;
    // the frame before the first sound that is not dropped (flip the drop rule's input there)
    const f = run.frames.findIndex((fr) => fr[2].some((e) => !(e & 0x50000) && ((e >> 8) & 0xff) >= 8));
    return f > 0 ? f : -1;
}

async function replay(name, ctx) {
    const run = fixture.runs[name];
    const { memory, machine, demo } = ctx;
    const snap = inflateSync(Buffer.from(run.init.snap, "base64"));
    const base = demo.rickTestBuf(ctx.bufSize);
    if (!base) return [`${name}: rickTestBuf(${ctx.bufSize}) refused`];
    const ints0 = snap.length + 3 & ~3;
    new Uint8Array(memory.buffer, base, snap.length).set(snap);
    const ints = new Int32Array(memory.buffer, base + ints0, 17 + run.tape.length + run.irqs.length);
    ints.set(run.init.pal.concat([run.init.vbase]));
    ints.set(run.tape, 17);
    ints.set(run.irqs, 17 + run.tape.length);
    const rc = demo.rickTestLoad(snap.length, ints0, run.tape.length, run.irqs.length, run.per_call ? 1 : 0);
    if (rc !== 0) return [`${name}: rickTestLoad refused (${rc})`];
    const errors = [];
    const fail = (msg) => { if (errors.length < 4) errors.push(`${name}: ${msg}`); };
    const bf = breakFrame(run);
    let ok = 0, vblOk = 0, sndOk = 0, reqOk = 0, sounds = 0, nCalls = 0;
    let resident = false; // rickTestLoad starts the cart's as a fresh cart has it
    const t0 = performance.now();
    for (let f = 0; f < run.frames.length; f++) {
        if (f === bf) {
            if (broke === "joy") demo.rickTestPoke(0x38cad, 0x04); // the stick pushed left
            if (broke === "vbl") demo.rickTestIrq();
            if (broke === "sound") demo.rickTestPoke(0x34a84, 1); // "a tune is playing"
            if (broke === "alloc") demo.rickTestRefuse();
        }
        const [crc, vbls, snd] = run.frames[f];
        const v = demo.rickTestFrame();
        if (v === vbls) vblOk++; else fail(`frame ${f} took ${v} VBLs, the harness ${vbls}`);
        const got = demo.rickTestVal(0) >>> 0;
        if (got === crc >>> 0) ok++;
        else {
            const bad = demo.rickTestVal(3) | 0;
            fail(`frame ${f}: state CRC ${got.toString(16)}, the harness ${(crc >>> 0).toString(16)}` +
                (bad >= 0 ? ` (first differing call: frame ${bad} call ${demo.rickTestVal(4) | 0})` : ""));
        }
        const n = demo.rickTestVal(5);
        const log = [];
        for (let i = 0; i < n; i++) log.push(demo.rickTestVal(100 + i));
        const plays = log.filter((e) => e !== 0xfffff);
        sounds += snd.length;
        if (plays.join() === snd.join()) sndOk++;
        else fail(`frame ${f}: play_sound [${plays.map((e) => e.toString(16))}], the harness [${snd.map((e) => e.toString(16))}]`);
        const req = songRequest(memory, demo), calls = sndhCalls(memory, demo), want = expectedHost(log, resident);
        resident = want.resident;
        nCalls += calls.length;
        const hex = (v) => v.map((d) => typeof d === "number" ? d.toString(16) : d);
        if (req === want.req && calls.join() === want.calls.join()) reqOk++;
        else fail(`frame ${f}: the host was asked for ${req} + calls [${hex(calls)}], ` +
            `the log implies ${want.req} + [${hex(want.calls)}]`);
        if (errors.length >= 4 && !broke) break;
    }
    const nf = run.frames.length;
    const tape = demo.rickTestVal(1), oob = demo.rickTestVal(2), unk = demo.rickTestVal(6);
    if (tape) fail(`${tape} tape mismatches (the cart ran another call than the harness)`);
    if (oob) fail(`${oob} accesses outside the 512 KB`);
    if (unk) fail(`${unk} entity types with no handler`);
    if (!errors.length && demo.rickTestVal(8) !== run.tape.length) fail(`tape consumed ${demo.rickTestVal(8)}/${run.tape.length}`);
    if (!errors.length && demo.rickTestVal(9) !== run.irqs.length) fail(`interrupts consumed ${demo.rickTestVal(9)}/${run.irqs.length}`);
    if (machine.hwRamAllocFailures()) fail(`${machine.hwRamAllocFailures()} zg.mem allocation(s) refused`);
    const ms = (performance.now() - t0) / nf;
    console.log(`  ${name}: ${nf} frames; VBLs ${vblOk}/${nf}, state CRC ${ok}/${nf}, play_sound ${sndOk}/${nf} ` +
        `(${sounds} requests), host requests ${reqOk}/${nf} (${nCalls} resident calls) (${ms.toFixed(3)} ms/frame)`);
    return errors;
}

// ---------------------------------------------------------------- the live path
function visible(memory, machine) {
    const pfb = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), RW * RH);
    const out = new Uint32Array(320 * 200);
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) out[y * 320 + x] = pfb[(40 + y) * RW + 80 + 2 * x];
    return out;
}
async function shot(px, path) {
    const rgb = Buffer.alloc(320 * 200 * 3);
    for (let i = 0; i < px.length; i++) { rgb[3 * i] = px[i] & 255; rgb[3 * i + 1] = (px[i] >> 8) & 255; rgb[3 * i + 2] = (px[i] >> 16) & 255; }
    await writeFile(path, Buffer.concat([Buffer.from("P6\n320 200\n255\n"), rgb]));
}

/// The ST screen at the video base, decoded here, against the plane as shown.
function stDiff(memory, demo, shown) {
    const vb = demo.rickTestVbase();
    if (vb !== 0x70000 && vb !== 0x78000) return `video base $${vb.toString(16)}`;
    const scr = new Uint8Array(memory.buffer, demo.rickTestMemPtr() + vb, 32000);
    const pal = new BigInt64Array(memory.buffer, demo.rickTestPalPtr(), 16);
    const gun = (n) => Math.floor((n & 7) * 255 / 7);
    let bad = 0;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const g = y * 160 + (x >> 4) * 8, b = 15 - (x & 15);
        let c = 0;
        for (let p = 0; p < 4; p++) c |= ((((scr[g + 2 * p] << 8) | scr[g + 2 * p + 1]) >> b) & 1) << p;
        const w = Number(pal[c]);
        const want = (gun(w >> 8) | gun(w >> 4) << 8 | gun(w) << 16 | 0xff000000) >>> 0;
        if (shown[y * 320 + x] >>> 0 !== want) bad++;
    }
    return bad ? `${bad} pixels differ` : null;
}

async function live() {
    const { memory, machine, demo } = await boot();
    const songs = [];
    const step = (n, dt) => {
        for (let i = 0; i < n; i++) {
            machine.hwClear();
            demo.frame(dt);
            const r = songRequest(memory, demo);
            if (r) songs.push(r);
            for (const d0 of sndhCalls(memory, demo)) songs.push(typeof d0 === "number" ? `${MUSIC}#${d0 & ~RESIDENT}` : d0);
            machine.hwRenderPlane(0);
        }
    };
    const errors = [];
    const fire = (ms) => { demo.key(13); step(Math.round(ms / 20), 20); demo.keyUp(13); step(10, 20); };
    step(250, 20); // 5 s: the start-up, the title picture
    const title = visible(memory, machine);
    await shot(title, `${outdir}/title.ppm`);
    const colours = new Set(title);
    if (colours.size < 6) errors.push(`the title shows ${colours.size} colours`);
    const td = stDiff(memory, demo, title);
    if (td) errors.push(`the title plane is not the ST screen: ${td}`);
    if (!songs.includes(`${MUSIC}#${1 + 5 + NIDS * 2}`)) errors.push(`no title tune (${MUSIC} subtune ${1 + 5 + NIDS * 2}): ${songs}`);
    fire(200); // the title -> the level select
    step(150, 20);
    await shot(visible(memory, machine), `${outdir}/select.ppm`);
    fire(200); // level 1 -> its intro
    step(200, 20);
    await shot(visible(memory, machine), `${outdir}/intro.ppm`);
    if (!songs.includes(`${MUSIC}#1`)) errors.push(`no level 1 jingle (subtune 1): ${songs}`);
    fire(200); // -> the game
    step(200, 20);
    const g = visible(memory, machine);
    await shot(g, `${outdir}/game.ppm`);
    const gd = stDiff(memory, demo, g);
    if (gd) errors.push(`the game plane is not the ST screen: ${gd}`);
    const mem = () => new Uint8Array(memory.buffer, demo.rickTestMemPtr(), 0x80000);
    const rickX = () => (mem()[0x3a1d4] << 8) | mem()[0x3a1d5];
    if (mem()[0x3a1d1] !== 1) errors.push("Rick is not in slot 1 after the intro");
    const x0 = rickX();
    demo.input(3); step(40, 20); demo.inputRelease(3); step(5, 20);
    if (rickX() <= x0) errors.push(`right did not move Rick (x ${x0} -> ${rickX()})`);
    // a 60 Hz host keeps the ST's 50 Hz: 10 s = ~500 VBLs
    const v0 = demo.rickTestVal(10);
    step(600, 1000 / 60);
    const dv = demo.rickTestVal(10) - v0;
    if (Math.abs(dv - 500) > 8) errors.push(`10 s at 60 Hz ran ${dv} ST VBLs, not ~500`);
    // P pauses (the frame counter stops), P again resumes
    demo.key(0x70); step(2, 20); demo.keyUp(0x70);
    const f0 = demo.rickTestVal(7);
    step(50, 20);
    if (demo.rickTestVal(7) !== f0) errors.push("P did not pause the loop");
    demo.key(0x70); step(2, 20); demo.keyUp(0x70); step(20, 20);
    if (demo.rickTestVal(7) === f0) errors.push("P again did not resume");
    // Escape: to the title; Escape there leaves
    demo.key(0xe012); step(2, 20); demo.keyUp(0xe012);
    step(300, 20);
    demo.key(0xe012); step(1, 20);
    if (demo.pollCartRequest() !== -1) errors.push("Escape on the title did not leave for the menu");
    if (machine.hwRamAllocFailures()) errors.push(`${machine.hwRamAllocFailures()} zg.mem allocation(s) refused`);
    console.log(`  live: the title (${colours.size} colours, its tune), FIRE -> select -> intro -> level 1, ` +
        `Rick walks, ${dv} ST VBLs in 10 s at 60 Hz, P pauses and resumes, Escape -> title -> leaves`);
    return errors;
}

// ---------------------------------------------------------------- the sound
async function audioMachine() {
    const AUDIO_PAGES = 48;
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    return { memory, m, audio };
}

// The driver's RAM the two sides must agree on: the state bytes, the music
// channels, the sfx voices. The Timer A pointer runs on the SNDH player's MFP
// clock and the cart's per-VBL one: compared only while no digi plays.
const DRIVER = [[0x34a7e, 0x34a84], [0x34a85, 0x34a88], [0x34b18, 0x34b98], [0x34ebc, 0x34f0c]];

async function sound(ctx) {
    const bytes = new Uint8Array(await readFile(`docs/music/${MUSIC}`));
    const { memory, demo } = ctx;
    const errors = [];
    let ticks = 0, tunes = 0, moving = 0;
    for (let id = 0; id < NIDS; id++) for (const v of [0, 1, 2]) {
        const sub = 1 + id + NIDS * v;
        const a = await audioMachine();
        a.audio.audioInit();
        new Uint8Array(a.memory.buffer, a.audio.audioSongPtr(), bytes.length).set(bytes);
        if (!a.audio.audioLoadSndh(bytes.length)) { errors.push("audioLoadSndh refused the image"); return errors; }
        a.audio.audioSndhPlay(broke === "sndh" ? sub % (3 * NIDS) + 1 : sub);
        demo.rickTestSndBegin(sub);
        const ram68 = () => new Uint8Array(a.memory.buffer, a.audio.audioSongPtr(), 0x100000);
        const cart = () => new Uint8Array(memory.buffer, demo.rickTestMemPtr(), 0x80000);
        // the image's code really sits at the game's addresses (play_sound $34750)
        if (ram68().subarray(0x34750, 0x34790).join() !== cart().subarray(0x34750, 0x34790).join())
            errors.push(`subtune ${sub}: the SNDH did not copy the driver to $34692`);
        let bad = null, prev = null;
        for (let t = 0; t < 250 && !bad; t++) {
            a.audio.audioRender(882); // 20 ms: one 50 Hz play call
            demo.rickTestSndTick();
            ticks++;
            const s = ram68(), c = cart();
            const now = s.subarray(0x34b18, 0x34f0c).join();
            if (prev !== null && now !== prev) moving++;
            prev = now;
            const digi = c[0x34a84] === 0xff || s[0x34a84] === 0xff;
            for (const [lo, hi] of DRIVER) for (let p = lo; p < hi && !bad; p++) {
                if (digi && p === 0x34a84) continue;
                if (s[p] !== c[p]) bad = `tick ${t}: $${p.toString(16)} SNDH ${s[p]} cart ${c[p]}`;
            }
        }
        if (bad) errors.push(`subtune ${sub} (id ${id}): ${bad}`);
        if (a.audio.audioSndhStuckPc && a.audio.audioSndhStuckPc()) errors.push(`subtune ${sub}: stuck at PC ${a.audio.audioSndhStuckPc()}`);
        tunes++;
        if (errors.length > 4) break;
    }
    if (moving < 1000) errors.push(`the driver state changed on only ${moving} ticks: nothing is playing`);
    console.log(`  sound: ${tunes} subtunes (every id x the 3 voice variants), ${ticks} ticks (${moving} moving): ` +
        `the SNDH's own driver RAM = the cart's transcription, tick for tick`);
    return errors;
}

// The loader's side, on the audio machine: the frame's song request (a load,
// or "none"), then its zg.sndhCalls on the running image. --break reload
// forwards every call as a reload instead, as the host did before sndhCall.
function hostPoll(a, ctx, bytes, errors) {
    const r = songRequest(ctx.memory, ctx.demo);
    const load = (d0) => {
        new Uint8Array(a.memory.buffer, a.audio.audioSongPtr(), bytes.length).set(bytes);
        if (!a.audio.audioLoadSndh(bytes.length)) errors.push("audioLoadSndh refused the image");
        a.audio.audioSndhPlay(d0 & 0xff);
    };
    if (r === "none") a.audio.audioReset();
    else if (r) load(Number(r.split("#")[1]));
    const calls = sndhCalls(ctx.memory, ctx.demo);
    for (const d0 of calls) {
        if (typeof d0 !== "number") errors.push(`resident: a call ${d0}`);
        else if (broke === "reload") load(d0 & ~RESIDENT);
        else if (!a.audio.audioSndhCall(d0)) errors.push(`resident: call $${d0.toString(16)} found no SNDH playing`);
    }
    return calls.length;
}

// Later requests on a RUNNING driver: after a first sound (an effect, a digi,
// a tune), every id at tick 4, the shot's pair at 9, dynamite twice at 15, and
// every id again at 30 on the looping voice. Both sides take the requests
// between two ticks; the driver RAM must agree tick for tick, as in sound().
const LATER = (id) => [[4, [[id, 0]]], [9, [[8, 1], [8, 0]]], [15, [[0xa, 0], [0xa, 0]]], [30, [[id, 1]]]];

async function resident(ctx) {
    const bytes = new Uint8Array(await readFile(`docs/music/${MUSIC}`));
    const { memory, demo } = ctx;
    const cart = () => new Uint8Array(memory.buffer, demo.rickTestMemPtr(), 0x80000);
    const errors = [];
    demo.rickTestSndBegin(0); // the entry image, to read the sound table from
    songRequest(memory, demo); sndhCalls(memory, demo);
    const kind = (id) => (cart()[0x3498a + 8 * id] << 8) | cart()[0x3498b + 8 * id];
    const bases = [1, 2, 0].map((k) => [...Array(NIDS).keys()].find((id) => kind(id) === k));
    let runs = 0, calls = 0, pairs = 0, ticks = 0;
    for (const base of bases) for (let id = 0; id < NIDS; id++) {
        const a = await audioMachine();
        a.audio.audioInit();
        demo.rickTestSndBegin(1 + base);
        hostPoll(a, ctx, bytes, errors);
        const ram68 = () => new Uint8Array(a.memory.buffer, a.audio.audioSongPtr(), 0x100000);
        const later = new Map(LATER(id));
        let bad = null;
        for (let t = 0; t < 120 && !bad; t++) {
            if (later.has(t)) {
                for (const [n, d1] of later.get(t)) demo.rickTestSndPlay(n, d1);
                const n = hostPoll(a, ctx, bytes, errors);
                calls += n;
                if (n > 1) pairs++;
            }
            a.audio.audioRender(882);
            demo.rickTestSndTick();
            ticks++;
            const s = ram68(), c = cart();
            const digi = c[0x34a84] === 0xff || s[0x34a84] === 0xff;
            for (const [lo, hi] of DRIVER) for (let p = lo; p < hi && !bad; p++) {
                if (digi && p === 0x34a84) continue;
                if (s[p] !== c[p]) bad = `tick ${t}: $${p.toString(16)} SNDH ${s[p]} cart ${c[p]}`;
            }
        }
        if (bad) errors.push(`resident: first id ${base}, later id ${id}: ${bad}`);
        runs++;
        if (errors.length > 4) break;
    }
    if (calls < 100 || pairs < 10) errors.push(`resident: only ${calls} calls (${pairs} frames with two): the requests were dropped`);
    console.log(`  resident: ${runs} runs (a first effect / digi / tune, then every id, the paired shot, dynamite x2), ` +
        `${calls} zg.sndhCall's (${pairs} frames with two), ${ticks} ticks: the running driver's RAM = the cart's`);
    return errors;
}

await mkdir(outdir, { recursive: true });
fixture.snapBytes = inflateSync(Buffer.from(Object.values(fixture.runs)[0].init.snap, "base64")).length;
const ctx = await boot();
ctx.bufSize = Math.max(...Object.values(fixture.runs).map(runSize));
const only = process.env.RICK_ONLY ? process.env.RICK_ONLY.split(",") : null;
let errors = [];
if (broke === "sndh") errors.push(...await sound(ctx));
else if (broke === "reload") errors.push(...await resident(ctx));
else for (const name of Object.keys(fixture.runs)) if (!only || only.includes(name)) errors.push(...await replay(name, ctx));
if (broke) {
    // each fault must be caught by ITS check, not only by another one
    const by = { joy: "state CRC", vbl: "VBLs", sound: "play_sound", alloc: "allocation", sndh: "SNDH", reload: "resident: first id" }[broke];
    const hit = errors.find((e) => e.includes(by));
    console.log(hit ? `rick_dangerous: PASS (--break ${broke} caught: ${hit})` :
        `rick_dangerous: FAILED -- --break ${broke} was not caught by the ${by} check (${errors.length} other errors)`);
    process.exit(hit ? 0 : 1);
}
if (!process.env.RICK_REPLAY_ONLY) errors.push(...await live(), ...await sound(ctx), ...await resident(ctx));
console.log(errors.length ? `rick_dangerous: FAILED -- ${errors.join("; ")}` : "rick_dangerous: all pass");
process.exit(errors.length ? 1 : 0);
