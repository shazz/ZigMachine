// The .hip player (libs/zig/players/hip_player.zig, paula.zig) on every Hippel module in
// docs/music/ and each song a screen plays from it: the module's own 68000 replay, on the
// browser's docs/demo-audio.wasm.
//
//   node apps/hip_check.mjs [--break beam]
//
// For each song, 10 s: the replay never runs away, it is loud, at least one Paula voice is
// started by DMACON, no voice points outside the 68000's RAM, no write reaches hardware
// nothing answers. rings_of_medusa.hip is the one whose replay WAITS FOR THE BEAM
// (`move.b 6(a6),d6 / cmp.b 6(a6),d6 / beq`, VHPOSR's low byte changing, image+$1F6),
// so it proves the beam counter (amiga_beam.zig) moves.
//
// --break beam: VHPOSR reads 0 for ever (paula.zig mutant 3). Must fail (the RoM replay hangs).
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
if (BREAK !== null && BREAK !== "beam") { console.error(`hip_check: unknown --break ${BREAK}`); process.exit(1); }

// modland's files byte for byte (docs/MUSIC.md): name, md5, songs to play.
const SONGS = [
    { file: "shaolin_title.hip", md5: "48e2ebc6c7588bee78796281b677facc", tunes: [1] },
    { file: "rings_of_medusa.hip", md5: "024e14d61ff6c311a1d7df52a7d40700", tunes: [1, 2] },
];
const SECONDS = 10, BLOCK = 1024;
const errors = [];
const fail = (m) => errors.push(m);

async function audio() {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 }); // machine/sdk/audio.zig
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    if (BREAK === "beam") a.audioHipMutant(3);
    return { memory, machine, a };
}

for (const s of SONGS) {
    const bytes = await readFile(`docs/music/${s.file}`).catch(() => null);
    if (!bytes) { fail(`docs/music/${s.file} is missing`); continue; }
    if (createHash("md5").update(bytes).digest("hex") !== s.md5) fail(`${s.file} is not modland's file (md5)`);
    for (const tune of s.tunes) {
        const { memory, machine, a } = await audio(); // a fresh machine per song
        new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
        const tag = `${s.file} song ${tune}`;
        if (!a.audioLoadHip(bytes.length)) { fail(`${tag}: refused`); continue; }
        a.audioHipPlay(tune);
        let lo = 0, hi = 0;
        for (let done = 0; done < SECONDS * 44100 && a.audioHipActive(); done += BLOCK) {
            a.audioRender(BLOCK);
            for (const v of new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK)) { lo = Math.min(lo, v); hi = Math.max(hi, v); }
            for (const v of new Float32Array(memory.buffer, machine.audioRightPtr(), BLOCK)) { lo = Math.min(lo, v); hi = Math.max(hi, v); }
        }
        const starts = [0, 1, 2, 3].map((c) => a.audioHipStarts(c));
        if (!a.audioHipActive()) { fail(`${tag}: the replay ran away (stuck at $${a.audioSndhStuckPc().toString(16)})`); continue; }
        if (!(hi - lo > 0.1)) fail(`${tag}: near silent over ${SECONDS} s (peak to peak ${(hi - lo).toFixed(3)})`);
        if (!starts.some((n) => n > 0)) fail(`${tag}: no Paula voice started`);
        if (a.audioHipBadPointers()) fail(`${tag}: ${a.audioHipBadPointers()} voices pointed outside the 68000's RAM`);
        if (a.audioUnhandledCount()) fail(`${tag}: ${a.audioUnhandledCount()} writes nothing answers, first at $${a.audioUnhandled(0).toString(16)}`);
        console.log(`  ${tag}: voice starts [${starts}], peak to peak ${(hi - lo).toFixed(2)}`);
    }
}

if (BREAK) {
    const caught = errors.length > 0;
    console.log(caught ? `hip_check: PASS (--break ${BREAK} caught: ${errors[0]})` : `hip_check: FAIL, --break ${BREAK} was NOT caught`);
    process.exit(caught ? 0 : 1);
}
if (errors.length) {
    console.log("hip_check: WRONG");
    for (const e of errors) console.log("  " + e);
    process.exit(1);
}
console.log("hip_check: OK");
