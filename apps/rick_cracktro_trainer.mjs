// The trainer flags against the game, for apps/rick_cracktro_headless.mjs: the
// lockstep replays of the ORIGINAL game (apps/rick_dangerous_fixture.json.gz,
// as apps/rick_dangerous_headless.mjs loads them) with a flag off, then on.
//   off  the counter goes down at some frame, and every frame up to it keeps
//        the harness's state CRC (the decrement is the original's)
//   on   the same run never takes the counter down
import { readFile } from "node:fs/promises";
import { gunzipSync, inflateSync } from "node:zlib";

export const FLAGS = [
    { bit: 1, at: 0x3adb0, name: "lives" },
    { bit: 2, at: 0x3adac, name: "bullets" },
    { bit: 4, at: 0x3adae, name: "dynamite" },
];

function load(ctx, fixture, run) {
    const { memory, demo } = ctx;
    const snap = inflateSync(Buffer.from(run.init.snap, "base64"));
    const ints0 = snap.length + 3 & ~3;
    const n = 17 + run.tape.length + run.irqs.length;
    const base = demo.rickTestBuf(ints0 + 4 * n);
    if (!base) throw new Error("rickTestBuf refused");
    new Uint8Array(memory.buffer, base, snap.length).set(snap);
    const ints = new Int32Array(memory.buffer, base + ints0, n);
    ints.set(run.init.pal.concat([run.init.vbase]));
    ints.set(run.tape, 17);
    ints.set(run.irqs, 17 + run.tape.length);
    const rc = demo.rickTestLoad(snap.length, ints0, run.tape.length, run.irqs.length, run.per_call ? 1 : 0);
    if (rc !== 0) throw new Error(`rickTestLoad refused (${rc})`);
}

/// One replay with the trainer `mask`: the counter after each frame, and the
/// frames whose state CRC is the harness's.
function replay(ctx, fixture, run, mask, at) {
    load(ctx, fixture, run);
    ctx.demo.rickTestTrainer(mask);
    const mem = () => new Uint8Array(ctx.memory.buffer, ctx.demo.rickTestMemPtr(), 0x80000);
    const counts = [mem()[at]], crcOk = [];
    for (const [crc] of run.frames) {
        ctx.demo.rickTestFrame();
        counts.push(mem()[at]);
        crcOk.push((ctx.demo.rickTestVal(0) >>> 0) === (crc >>> 0));
    }
    ctx.demo.rickTestTrainer(0);
    return { counts, crcOk };
}

const firstDrop = (c) => c.findIndex((v, i) => i > 0 && v < c[i - 1]);

/// `set(bit)`: the mask the "on" replay runs with (--break trainer: none).
export async function trainerCheck(ctx, set) {
    const fixture = JSON.parse(gunzipSync(await readFile("apps/rick_dangerous_fixture.json.gz")).toString());
    const errors = [], found = [];
    const size = (r) => (inflateSync(Buffer.from(r.init.snap, "base64")).length + 3 & ~3) + 4 * (17 + r.tape.length + r.irqs.length);
    if (!ctx.demo.rickTestBuf(Math.max(...Object.values(fixture.runs).map(size)))) return ["trainer: rickTestBuf refused"];
    for (const f of FLAGS) {
        let hit = null;
        for (const [name, run] of Object.entries(fixture.runs)) {
            const off = replay(ctx, fixture, run, 0, f.at);
            const d = firstDrop(off.counts);
            if (d < 0) continue;
            if (!off.crcOk.slice(0, d).every(Boolean)) {
                errors.push(`trainer: ${name} with no flag left the harness's CRC before frame ${d}`);
            }
            const on = replay(ctx, fixture, run, set(f.bit), f.at);
            const d2 = firstDrop(on.counts);
            hit = { name, d, n0: off.counts[d - 1], n1: off.counts[d], d2, on: on.counts[on.counts.length - 1] };
            break;
        }
        if (!hit) { errors.push(`trainer: no replay takes the ${f.name} down`); continue; }
        if (hit.d2 >= 0) errors.push(`trainer: infinite ${f.name} on, ${hit.name} still took it down at frame ${hit.d2}`);
        found.push(`${f.name} (${hit.name}: ${hit.n0} -> ${hit.n1} at frame ${hit.d} off, never down on)`);
    }
    console.log(`  trainer: ${found.join(", ")}`);
    return errors;
}
