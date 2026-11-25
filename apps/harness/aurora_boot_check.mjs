// AURORA BOOT (cart "aurora_boot", apps/zig/scenes/aurora_boot.zig): the new KESTREL boot screen, baked offline by
// tools/boot/aurora_bake.py. Boots the cart over the real machine + ROM, runs host frames as the page does (hwClear,
// frame, every enabled plane rendered) and checks the sequence against the baker's PYTHON REFERENCE
// (apps/zig/assets/screens/aurora_boot/aurora_ref.json):
//   sky       frame 10: the true-colour plane is the reference sky, byte for byte
//   aurora    each probed aurora frame j, once fully shown (its second 60 Hz frame): the plane = the reference's
//             base + palette[index] add, byte for byte (the cart's ZX0 + delta + add loop equals numpy's)
//   gone      the aurora's last frame restores the sky exactly
//   stars     at the probed records every baked star pixel is lit on plane 1 (8-bit, over the TC plane)
//   flight    plane 1 changes every frame while the stars fly; the wire (palette entry 16) is absent before the
//             falcon forms and present at the hold; the name (entry 17) only from its beat
//   fade      TC_FADE starts at 31 (black) and falls to 0 over the fade-in (the sky fades in), stays 0, and is 31 at the last record; the composed picture is black from then on
//   end       the cart asks to leave (pollCartRequest -1) from the last frame, never before
//   sound     ONE sample op (zg.samplePlay) at frame 0: signed 8-bit at the baked rate, the bytes the baker wrote
//             (md5), not looped, never stopped: it lasts as long as the picture (a frame of slack)
//   replay    a key restarts: the sky is back at once, the sample is stopped and started again
//   node apps/harness/aurora_boot_check.mjs [cart.wasm]
//   node apps/harness/aurora_boot_check.mjs --break   each mutant must be caught by the checks
//   node apps/harness/aurora_boot_check.mjs --variant=c   the variant cart aurora_boot_c against its own reference (b, c, d, e)
// The pins are the baker's own reference file: a re-bake rewrites it, nothing here is hand-copied.
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../../site/js/wasm_hiwater.js";

const PAGES = 128, REG_FB_BASE = 0x44, REG_TC_FADE = 0x0C, FX_SAMPLE = 6, FX_SAMPLE_STOP = 7;
const VARIANT = process.argv.find((a) => a.startsWith("--variant="))?.slice(10) ?? ""; // b..e: the cart aurora_boot_<v>
const DIR = `apps/zig/assets/screens/aurora_boot${VARIANT && "_" + VARIANT}/`;
const BROKE = process.argv.includes("--break");
const [cart = `site/carts/demo-aurora_boot${VARIANT && "_" + VARIANT}.wasm`] = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const ref = JSON.parse(await readFile(DIR + "aurora_ref.json", "utf8"));
const metaSrc = await readFile(DIR + "aurora_meta.zig", "utf8");
const meta = Object.fromEntries([...metaSrc.matchAll(/pub const (\w+): (?:u32|i32) = (\d+);/g)].map((m) => [m[1], +m[2]]));
const LAST = (meta.STAR_FRAMES - 1) * 2; // the last cart frame: black, asks to leave
const md5 = (b) => createHash("md5").update(b).digest("hex");
const FRAMES = LAST + 60;

async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("site/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("site/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(cart);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo, video: machine.hwVideoBase() };
}

const plane = (m, p, bytes) => new Uint8Array(m.memory.buffer, m.video + new DataView(m.memory.buffer).getUint32(m.video + REG_FB_BASE + 4 * p, true), bytes);

// One page frame: the cart's frame, its sfx entries, the two planes' memory (copied) and the composed raster.
function frame(m, f, brk) {
    const { machine, demo, memory } = m;
    machine.hwClear();
    const skip = (brk === "slow" && f % 2 === 1) || (brk === "frozen" && f >= 150);
    if (!skip) demo.frame(1000 / 60);
    const dv = new DataView(memory.buffer);
    if (brk === "nofade") dv.setUint8(m.video + REG_TC_FADE, 0);
    const tc = Uint8Array.from(plane(m, 0, 320 * 200 * 2));
    const st = Uint8Array.from(plane(m, 1, 320 * 200));
    if (brk === "badaurora" && f === 60 + 2 * 75 + 2) tc[2 * (80 * 320 + 100)] ^= 0x20; // a flipped bit in the add
    if (brk === "nostars") st.fill(0);
    if (brk === "nowire") for (let i = 0; i < st.length; i++) if (st[i] === 16) st[i] = 0;
    const n = demo.pollSfx(), at = demo.sfxEntriesPtr(), fx = [];
    for (let i = 0; i < n; i++) {
        const o = at + i * 16;
        fx.push({ op: dv.getUint8(o), a: dv.getUint8(o + 1), ptr: dv.getUint32(o + 4, true), len: dv.getUint32(o + 8, true), rate: dv.getUint32(o + 12, true) });
    }
    const sample = fx.filter((e) => e.op === FX_SAMPLE).map((e) => ({ ...e, md5: md5(new Uint8Array(memory.buffer, e.ptr, e.len)) }));
    const comp = compose(m);
    const req = brk === "stays" ? 0 : demo.pollCartRequest();
    return { tc, st, fx: brk === "nosound" ? [] : fx.filter((e) => e.op === FX_SAMPLE_STOP), sample: brk === "nosound" ? [] : sample, comp, req, fade: dv.getUint8(m.video + REG_TC_FADE) & 31 };
}

function compose(m) {
    const { machine, demo, memory } = m;
    const size = machine.hwPhysWidth() * machine.hwPhysHeight();
    const comp = new Uint32Array(size);
    for (let p = 0; p < machine.hwPlanesNumber(); p++) {
        if (!demo.isPlaneEnabled(p)) continue;
        machine.hwRenderPlane(p);
        const snap = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), size);
        for (let i = 0; i < size; i++) if (snap[i] >>> 24) comp[i] = snap[i];
    }
    return comp;
}

const lit = (a) => { let n = 0; for (const v of a) n += v !== 0; return n; };
const litRgb = (a) => { let n = 0; for (const v of a) n += (v & 0xFFFFFF) !== 0; return n; }; // the composed raster: a black pixel has alpha
const count = (a, v) => { let n = 0; for (const x of a) n += x === v; return n; };

async function run(brk) {
    const m = await boot();
    const shots = [];
    for (let f = 0; f < FRAMES; f++) {
        const r = frame(m, f + 1, brk);
        shots[f] = { tcmd5: md5(r.tc), st: r.st, stmd5: md5(r.st), lit: litRgb(r.comp), req: r.req, fade: r.fade, sample: r.sample, stops: r.fx };
    }
    const replay = await runReplay();
    return { shots, replay };
}

// The replay key, mid-sequence: the sky is back at once, the sound restarted.
async function runReplay() {  // boots its own machine
    const m = await boot();
    let r;
    for (let f = 0; f < 300; f++) frame(m, f + 1, null);
    m.demo.key(32);
    const after = [];
    for (let f = 0; f < 3; f++) { r = frame(m, 301 + f, null); after.push({ tcmd5: md5(r.tc), sample: r.sample, stops: r.fx }); }
    return after;
}

const at = (s, k) => s[k]; // shots index = cart frame
function checks({ shots, replay }) {
    const bad = [];
    const need = (ok, what) => { if (!ok) bad.push(what); };
    need(at(shots, 10).tcmd5 === ref.sky_md5, "sky: the true-colour plane at frame 10 is not the reference sky");
    for (const [j, want] of Object.entries(ref.planes_md5)) {
        const k = 2 * (meta.AURORA_AT + +j) + 1;
        need(at(shots, k).tcmd5 === want, `aurora: frame ${j} (cart frame ${k}) differs from the reference plane`);
    }
    need(ref.planes_md5[String(meta.AURORA_FRAMES - 1)] === ref.sky_md5, "gone: the reference's last aurora frame is not the sky");
    for (const [rec, xy] of Object.entries(ref.stars_xy)) {
        const s = at(shots, 2 * +rec).st;
        const miss = xy.filter(([x, y]) => x >= 0 && x < 320 && y >= 0 && y < 200 && s[y * 320 + x] === 0).length;
        need(miss === 0, `stars: record ${rec}: ${miss} baked star pixels are not lit on plane 1`);
    }
    const t0 = Math.round(1.7 * 60) + 2, t1 = Math.round(5.1 * 60);
    let moved = 0;
    for (let k = t0 + 1; k < t1; k++) moved += at(shots, k).stmd5 !== at(shots, k - 1).stmd5;
    need(moved >= (t1 - t0) * 0.9, `flight: plane 1 changed on ${moved} of ${t1 - t0} frames`);
    need(count(at(shots, 100).st, 16) === 0, "wire: lines drawn before the falcon forms");
    need(count(at(shots, 400).st, 16) > 150, `wire: only ${count(at(shots, 400).st, 16)} line pixels at the hold`);
    need(count(at(shots, 200).st, 17) === 0 && count(at(shots, 400).st, 17) > 500, "word: the name is not lit only from its beat");
    // The sky fades in from black (ref.fade_in_frames 60 Hz frames; a set baked before the fade-in has none), is 0 until the end fade.
    const fin = ref.fade_in_frames ?? 0;
    if (fin > 0) {
        need(at(shots, 0).fade >= 30, `fade-in: TC_FADE ${at(shots, 0).fade} at frame 0 (31 = black expected)`);
        need(at(shots, Math.floor(fin / 2)).fade > 5 && at(shots, Math.floor(fin / 2)).fade < 26, `fade-in: TC_FADE ${at(shots, Math.floor(fin / 2)).fade} halfway (a ramp expected)`);
        for (let k = 1; k < fin; k++) need(at(shots, k).fade <= at(shots, k - 1).fade, `fade-in: TC_FADE rises at frame ${k}`);
    }
    for (let k = fin + 1; k < LAST - 40; k++) { need(at(shots, k).fade === 0, `fade: TC_FADE ${at(shots, k).fade} at frame ${k} (0 from the end of the fade-in)`); if (bad.length > 20) break; }
    need(at(shots, LAST).fade === 31, `fade: ${at(shots, LAST).fade} at the last frame (31 expected)`);
    need(at(shots, 90).lit > 20000 && at(shots, 400).lit > 20000, "picture: the sky is not lit");
    if (fin > 0) need(at(shots, 0).lit < 2000, `fade-in: ${at(shots, 0).lit} lit pixels at frame 0 (black expected)`);
    for (let k = LAST; k < FRAMES; k++) need(at(shots, k).lit === 0, `black end: frame ${k} is not black`);
    const asked = shots.findIndex((s) => s.req === -1);
    need(asked === LAST && shots.slice(asked).every((s) => s.req === -1), `end: asks to leave from frame ${asked} (${LAST} expected, then every frame)`);
    sound(shots, need);
    need(replay[0].tcmd5 === ref.sky_md5 && replay[0].stops.length === 1 && replay[0].sample.length === 1 && replay[0].sample[0].md5 === ref.pcm_md5, "replay: the key did not restore the sky, stop and restart the sound");
    return bad;
}

function sound(shots, need) {
    const all = shots.flatMap((s, k) => s.sample.map((e) => ({ ...e, k })));
    need(all.length === 1 && all[0].k === 0, `sound: ${all.length} sample ops, first at frame ${all[0]?.k} (one, at frame 0, expected)`);
    const e = all[0];
    need(!!e && e.rate === meta.SAMPLE_RATE && e.len === meta.SAMPLE_LEN && e.a === 0 && e.md5 === ref.pcm_md5, "sound: the sample is not the baked 8-bit PCM at its rate, once");
    need(shots.every((s) => s.stops.length === 0), "sound: a stop before the end");
    need(!!e && Math.abs(e.len / e.rate - LAST / 60) < 0.05, `sound: lasts ${e ? (e.len / e.rate).toFixed(3) : "?"} s, the picture ${(LAST / 60).toFixed(3)} s`);
}

const MUTANTS = ["nofade", "nosound", "slow", "frozen", "stays", "badaurora", "nostars", "nowire"];
if (BROKE) {
    let missed = 0;
    for (const b of MUTANTS) {
        const bad = checks(await run(b));
        console.log(`aurora_boot --break ${b}: ${bad.length ? `caught (${bad[0]})` : "NOT CAUGHT"}`);
        if (!bad.length) missed++;
    }
    process.exit(missed ? 1 : 0);
}
const bad = checks(await run(null));
for (const b of bad.slice(0, 20)) console.log(`aurora_boot: ${b}`);
console.log(`aurora_boot: ${bad.length ? `FAIL (${bad.length})` : "OK"}: sky + ${Object.keys(ref.planes_md5).length} aurora frames = the Python reference, stars lit, wire/name beats, fade, black + asks to leave at ${LAST}, one sample at frame 0 (${meta.SAMPLE_LEN} B at ${meta.SAMPLE_RATE} Hz), replay`);
process.exit(bad.length ? 1 : 0);
