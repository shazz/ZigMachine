// The racer cart's audio wiring (apps/zig/scenes/racer/audio.zig, R82 M4) on a harness machine with a fake BARD queue host:
//   capabilities off -> no queue, the title tune then the race tune asked by zg.requestSong; on -> the queue opened (lead
//   3,072), FM 5-6 + PSG 3 + noise owned and both voices patched, the countdown's beeps and go queued in a race (key e, s)
//   node apps/harness/racer_audio_check.mjs
import { bootObj } from "./obj_machine.mjs";
import { FRAME, LEAD, OWN } from "./fm_sfx_lib.mjs";

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


const errors = [], notes = [];
await racer(errors, notes);
for (const n of notes) console.log(`  ${n}`);
console.log(errors.length ? `racer_audio_check: FAILED -- ${errors.join("; ")}` : "racer_audio_check: all pass");
process.exitCode = errors.length ? 1 : 0;
