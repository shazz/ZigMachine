// The racer cart's audio wiring (apps/zig/scenes/racer/audio.zig, R82 M4) on a harness machine with a fake BARD queue host:
//   capabilities off -> no queue, the title tune then the race tune asked by zg.requestSong; on -> the queue opened (lead
//   3,072), FM 5-6 + PSG 3 + noise owned and both voices patched, the countdown's beeps and go queued in a race (key e, s)
//   live: the cart's ring piped into demo-audio.wasm's queue at 60 and 30 fps, the position a frame old: nothing late,
//   refused, dropped or re-anchored
//   node apps/harness/racer_audio_check.mjs
import { bootObj } from "./obj_machine.mjs";
import { readFile } from "node:fs/promises";
import { FRAME, LEAD, OWN, modules } from "./fm_sfx_lib.mjs";

async function racer(errors, notes) {
    const run = async (caps) => {
        const log = { attach: [], songs: [], cmds: [] };
        let S, block = 0;
        S = await bootObj("site/carts/demo-racer.wasm", () => {}, (env) => {
            env.hostBardAttach = (b, lead) => { log.attach.push(lead); block = b; return b ? 1 : 0; };
        });
        S.machine.hwSetCaps(caps);
        const mem = () => new Uint32Array(S.memory.buffer);
        const drain = () => {
            if (!block) return;
            const u = mem(), h = block >> 2, head = u[h + 4];
            for (let t = u[h + 5]; t !== head; t = (t + 1) >>> 0) { const c = h + 16 + 4 * (t % 256); log.cmds.push([u[c], u[c + 1], u[c + 2]]); }
            u[h + 5] = head;
            u[h + 7] = u[h + 7] + FRAME; u[h + 8] = 1; // the sound side's position moves a frame
        };
        const step = () => {
            S.frame(); drain();
            if (S.demo.pollSongRequest()) log.songs.push(new TextDecoder().decode(new Uint8Array(S.memory.buffer, S.demo.songNamePtr(), S.demo.songNameLen())));
        };
        step();
        S.demo.key("e".codePointAt(0)); step(); S.demo.key("s".codePointAt(0));
        for (let f = 0; f < 240; f++) step();
        return log;
    };
    const off = await run(0), on = await run(0x7f);
    const owned = on.cmds.filter(([, ad]) => ad === 0xc300), beeps = on.cmds.filter(([, ad, v]) => ad === 0xc200 && (v & 0xf0) === 0xd0 && (v & 15) < 15);
    const patches = on.cmds.filter(([, ad]) => ad >= 0xc130 && ad < 0xc1a0).length;
    const ok = off.attach.length === 0 && off.songs[0] === "kr_title.vgm" && off.songs.includes("kr_race.vgm") &&
        on.attach[0] === LEAD && owned.length === 1 && owned[0][2] === OWN && patches === 56 && beeps.length >= 4 && on.songs.includes("kr_race.vgm");
    if (!ok) errors.push(`racer: off ${JSON.stringify({ a: off.attach, s: off.songs })}, on attach ${on.attach} owned ${JSON.stringify(owned)} patches ${patches} beeps ${beeps.length} songs ${on.songs}`);
    else notes.push(`racer: caps off -> no queue, kr_title then kr_race by requestSong; on -> the queue (lead ${LEAD}), ${OWN.toString(16)} owned, the two voices' 56 operator writes, ${beeps.length} beeps through the countdown and go, ${on.cmds.length} commands in 240 frames`);
}

/** The racer's ring piped into demo-audio.wasm's queue as a host does it: drained after each cart frame, the sound side's
 *  answer (position, anchored) published back a frame late, `per` samples of sound a cart frame (735: 60 fps, 1470: 30 fps),
 *  hostMicros at that rate; the songs the cart asks for loaded under the queue. A recorded-driver race. */
async function live(errors, notes, per, frames) {
    const { memory: am, m, a } = await modules();
    let block = 0, frame = 0, heard = 0;
    const S = await bootObj("site/carts/demo-racer.wasm", () => {}, (env) => {
        env.hostBardAttach = (b, lead) => { block = b; if (b) a.audioBardOpen(lead); else a.audioBardClose(); return b ? 1 : 0; };
        env.hostMicros = () => Math.floor(frame * per * 1e6 / 44100);
    });
    const step = async () => {
        S.frame();
        if (S.demo.pollSongRequest()) {
            const name = new TextDecoder().decode(new Uint8Array(S.memory.buffer, S.demo.songNamePtr(), S.demo.songNameLen()));
            const b = await readFile(`site/music/${name}`);
            new Uint8Array(am.buffer, a.audioSongPtr(), b.length).set(b);
            if (!a.audioLoadVgm(b.length)) errors.push(`live: ${name} refused`);
        }
        if (block) {
            const u = new Uint32Array(S.memory.buffer), h = block >> 2, head = u[h + 4];
            const st = new Uint32Array(am.buffer, a.audioBardStagePtr(), 4 * a.audioBardStageCap());
            let n = 0;
            for (let t = u[h + 5]; t !== head; t = (t + 1) >>> 0, n++) st.set(u.subarray(h + 16 + 4 * (t % 256), h + 20 + 4 * (t % 256)), 4 * n);
            if (n) a.audioBardQueue(n);
            u[h + 5] = head;
            u[h + 7] = a.audioBardPosition(); u[h + 8] = a.audioBardAnchored(); // read before this frame's sound: a frame old
        }
        for (let k = 0; k < per; k += 105) {
            a.audioRender(105);
            for (const v of new Float32Array(am.buffer, m.audioLeftPtr(), 105)) heard += v !== 0;
        }
        frame++;
    };
    await step();
    for (const k of "eas") S.demo.key(k.codePointAt(0)), await step();
    for (let f = 0; f < frames; f++) await step();
    const u = new Uint32Array(S.memory.buffer), s = { applied: a.audioBardApplied(), refused: a.audioBardRefused(), late: a.audioBardLate(),
        resyncs: a.audioBardResyncs(), dropped: a.audioBardDropped() + u[(block >> 2) + 6], device: a.audioBardDevice(), tune: a.audioVgmActive() };
    if (!block || s.device !== 3 || !s.tune || s.late || s.resyncs || s.dropped || s.refused || s.applied < 100 || heard === 0)
        errors.push(`live ${per}: ${JSON.stringify(s)}, heard ${heard}`);
    else notes.push(`live: the racer's ring into demo-audio's queue at ${per} samples a cart frame (${(44100 / per).toFixed(0)} fps), the position a frame old, ${frames} frames of a race: ${s.applied} writes applied, none late, refused, dropped or re-anchored; the race tune under the queue`);
}

const errors = [], notes = [];
await racer(errors, notes);
await live(errors, notes, 735, 1200);
await live(errors, notes, 1470, 600);
await live(errors, notes, 2205, 400);
for (const n of notes) console.log(`  ${n}`);
console.log(errors.length ? `racer_audio_check: FAILED -- ${errors.join("; ")}` : "racer_audio_check: all pass");
process.exitCode = errors.length ? 1 : 0;
