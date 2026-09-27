// SKYSTRIKE harness, part 2 (apps/skystrike_headless.mjs is the driver): the
// sealed machine booted the way docs/sealed-loader.js boots it, the cart as a
// player runs it (live), and skystrike.sndh on the sealed audio machine.
import { readFile, writeFile } from "node:fs/promises";
import { boot } from "./skystrike_session.mjs";

export const MUSIC = "skystrike.sndh";
const RESIDENT = 0x8000; // sound.s: d0 $8000 + op << 8 + arg is a call on the running image
const K_ESC = 0xe012;
const RW = 800, RH = 280; // the physical frame: 320x200 at (40, 40), x doubled

// ---------------------------------------------------------------- the live path
function visible(memory, machine) {
    const pfb = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), RW * RH);
    const out = new Uint32Array(320 * 200);
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) out[y * 320 + x] = pfb[(40 + y) * RW + 80 + 2 * x];
    return out;
}

/// The cart's physic screen through its colour registers (3-bit guns x 255/7)
/// against the plane as displayed.
function stDiff(memory, demo, shown) {
    const px = new Uint8Array(memory.buffer, demo.skyTestPtr(0), 64000);
    const pal = new Uint16Array(memory.buffer.slice(demo.skyTestPtr(4), demo.skyTestPtr(4) + 32));
    const gun = (n) => Math.floor((n & 7) * 255 / 7);
    let bad = 0;
    for (let i = 0; i < 64000; i++) {
        const w = pal[px[i] & 15];
        if (shown[i] >>> 0 !== (gun(w >> 8) | gun(w >> 4) << 8 | gun(w) << 16 | 0xff000000) >>> 0) bad++;
    }
    return bad ? `${bad} pixels differ` : null;
}

async function shot(px, path) {
    const rgb = Buffer.alloc(320 * 200 * 3);
    for (let i = 0; i < px.length; i++) { rgb[3 * i] = px[i] & 255; rgb[3 * i + 1] = (px[i] >> 8) & 255; rgb[3 * i + 2] = (px[i] >> 16) & 255; }
    await writeFile(path, Buffer.concat([Buffer.from("P6\n320 200\n255\n"), rgb]));
}

/// Title up at a 50 Hz host, SPACE -> the menu, FIRE -> the briefing, 60 Hz
/// keeps the ST's 50 Hz, Escape on the title leaves.
export async function live(outdir, label) {
    const { memory, machine, demo } = await boot();
    // ORIGINAL: plane 0 is the ST's screen. The power-on mode is ZIG, which
    // shows the title scaled into the open frame instead (apps/skystrike_zig.mjs).
    demo.skyTestMode(0);
    const errors = [];
    const step = (n, dt) => {
        for (let i = 0; i < n; i++) { machine.hwClear(); demo.frame(dt); machine.hwRenderPlane(0); }
    };
    step(250, 20);
    const title = visible(memory, machine);
    await shot(title, `${outdir}/live_title.ppm`);
    const colours = new Set(title).size;
    if (colours < 8) errors.push(`live: the title shows ${colours} colours`);
    const d = stDiff(memory, demo, title);
    if (d) errors.push(`live: the plane is not the ST screen: ${d}`);
    if (demo.skyTestVal(0) !== label.l2006) errors.push(`live: not on the title's scroller (label ${demo.skyTestVal(0)})`);
    const v0 = demo.skyTestVal(8);
    step(600, 1000 / 60);
    const dv = demo.skyTestVal(8) - v0;
    if (Math.abs(dv - 500) > 8) errors.push(`live: 10 s at 60 Hz ran ${dv} ST VBLs, not ~500`);
    demo.key(K_ESC);
    step(1, 20);
    if (demo.pollCartRequest() !== -1) errors.push("live: Escape on the title did not leave for the menu");
    const b = await boot();
    const bstep = (n) => { for (let i = 0; i < n; i++) { b.machine.hwClear(); b.demo.frame(20); } };
    bstep(100);
    b.demo.key(0x20);
    bstep(3);
    b.demo.keyUp(0x20);
    bstep(300);
    if (b.demo.skyTestVal(0) !== label.l2126b && b.demo.skyTestVal(0) !== label.l2126)
        errors.push(`live: SPACE on the title did not open the menu (label ${b.demo.skyTestVal(0)})`);
    b.demo.key(K_ESC);
    b.machine.hwClear(); b.demo.frame(20);
    if (b.demo.pollCartRequest() === -1) errors.push("live: Escape left from the menu (only the title leaves)");
    const fails = machine.hwRamAllocFailures() + b.machine.hwRamAllocFailures();
    if (fails) errors.push(`live: ${fails} zg.mem allocation(s) refused`);
    console.log(`  live: title (${colours} colours) = the ST screen, ${dv} ST VBLs in 10 s at 60 Hz, SPACE -> menu, Escape leaves only from the title`);
    return errors;
}

// ---------------------------------------------------------------- the sound
async function audioMachine(bytes) {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 }); // AUDIO_PAGES
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadSndh(bytes.length)) throw new Error(`audioLoadSndh refused ${MUSIC}`);
    const regs = () => [...new Uint8Array(memory.buffer, m.audioYmRegsPtr(), 16)];
    return { audio, regs };
}

/// Changes of the three volume registers over `ms`, sampled every `n` samples.
function volumeChanges(a, ms, n) {
    let last = null, changes = 0;
    for (let s = 0; s < ms * 44.1; s += n) {
        a.audio.audioRender(n);
        const r = a.regs().slice(8, 11).join();
        if (last !== null && r !== last) changes++;
        last = r;
    }
    return changes;
}

/// The three tunes play; subtune 4 is silent; on the running image the gun
/// sample (Maestro's Timer A digi) drives the volume registers thousands of
/// times a second; the engine call leaves noise 31 - th under envelope 10.
export async function sound(broke) {
    const bytes = new Uint8Array(await readFile(`docs/music/${MUSIC}`));
    const errors = [];
    const report = [];
    for (const sub of [1, 2, 3, 4]) {
        const a = await audioMachine(bytes);
        a.audio.audioSndhPlay(sub);
        const ch = volumeChanges(a, 3000, 882);
        report.push(`${sub}:${ch}`);
        if (sub < 4 && ch < 20) errors.push(`sndh: subtune ${sub} changed the volumes ${ch} times in 3 s (no music)`);
        if (sub === 4 && ch) errors.push(`sndh: subtune 4 (silence) changed the volumes ${ch} times`);
        if (a.audio.audioSndhStuckPc()) errors.push(`sndh: subtune ${sub} stuck at PC ${a.audio.audioSndhStuckPc()}`);
    }
    const a = await audioMachine(bytes);
    a.audio.audioSndhPlay(4);
    a.audio.audioRender(882);
    const call = (op, arg) => { if (!a.audio.audioSndhCall(RESIDENT | op << 8 | arg)) errors.push(`sndh: call ${op},${arg} found no SNDH playing`); };
    call(3, 1); // samloop on
    call(1, broke === "sndh" ? 0 : 1); // samplay 1 (the guns); --break sndh: sample 0
    const digi = volumeChanges(a, 200, 8);
    if (digi < 400) errors.push(`sndh: samplay 1 moved the volumes ${digi} times in 200 ms (no digi)`);
    call(2, 0); // samstop
    const stopped = volumeChanges(a, 100, 8);
    if (stopped) errors.push(`sndh: the volumes changed ${stopped} times in 100 ms after SAMSTOP`);
    call(3, 0); // samloop off
    call(1, 2); // the crash, once
    const crash = volumeChanges(a, 100, 8);
    volumeChanges(a, 4000, 882);
    const after = volumeChanges(a, 100, 8);
    if (crash < 200 || after) errors.push(`sndh: samplay 2 moved the volumes ${crash} times in 100 ms, ${after} times 4 s later (want many, then none)`);
    for (const [op, arg] of [[4, 16], [5, 22], [7, 0], [8, 35], [6, 10]]) call(op, arg); // the engine at th = 9
    a.audio.audioRender(882);
    const r = a.regs();
    const want = { 6: 22, 11: 35, 12: 0, 13: 10 };
    for (const [k, v] of Object.entries(want)) if (r[k] !== v) errors.push(`sndh: the engine left reg ${k} = ${r[k]}, not ${v}`);
    if ((r[7] & 0x38) === 0x38) errors.push(`sndh: the engine left the noise off in the mixer ($${r[7].toString(16)})`);
    if (![8, 9, 10].some((k) => r[k] === 16)) errors.push(`sndh: the engine left no voice on the envelope (${r.slice(8, 11)})`);
    console.log(`  sound: ${MUSIC} volume changes over 3 s by subtune ${report.join(" ")}; ` +
        `samplay 1 on the running image: ${digi} changes in 200 ms, none after SAMSTOP; samplay 2: ${crash} in 100 ms, none once over; the engine call: noise 22, envelope 10 period 35`);
    return errors;
}
