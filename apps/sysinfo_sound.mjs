// SYSINFO's SOUND page, for apps/sysinfo_check.mjs: the sound files on its disk, selected and
// played off the disk. Run over a booted SysInfo (apps/sysinfo_machine.mjs):
//   list     page 3 lists the disk's three sound files (JINKS.SND, GAUNTLET.SAP, SAMPLE.RAW) with
//            their FAT sizes and kinds; the selected one is in inverse, Down moves it
//   drive    P reads the selection through the drive into the cart's RAM: the bytes the host is
//            handed (the sfx queue's pointer) are the FAT file's, byte for byte
//   bridge   an SNDH / SAP is zg.requestSongBytes (sfx op 8, kind 1 / 2); docs/sealed-loader.js's
//            own postSfx turns it into loadSndh / loadSap, and the audio module those messages
//            reach plays it in mode 4 (SNDH on the 68000) / 5 (SAP on the POKEY), with a sound;
//            the PCM is zg.samplePlay (op 6) at 12500 Hz
//   stop     S stops: a song with the song bridge's "none", the PCM with sampleStop (op 7)
import { readFile } from "node:fs/promises";
import { parseDisk } from "../docs/zmdisk.js";
import { frames, page, field, glass, K } from "./sysinfo_machine.mjs";

const FILES = [
    { name: "JINKS.SND", kind: "SNDH (68000 + YM)", op: 8, a: 1, mode: 4 },
    { name: "GAUNTLET.SAP", kind: "SAP (6502 + POKEY)", op: 8, a: 2, mode: 5 },
    { name: "SAMPLE.RAW", kind: "PCM 12500 HZ", op: 6, rate: 12500 },
];
const FILES_ROW = 15; // page_av.zig FILES_ROW + 1

/// The cart's sfx queue this frame: { op, a, b, bytes, rate } each, bytes copied out as the host does.
function drain(s) {
    const n = s.demo.pollSfx(), at = s.demo.sfxEntriesPtr();
    const dv = new DataView(s.memory.buffer, at, n * 16), out = [];
    for (let i = 0; i < n; i++) {
        const o = i * 16, ptr = dv.getUint32(o + 4, true), len = dv.getUint32(o + 8, true);
        out.push({ op: dv.getUint8(o), a: dv.getUint8(o + 1), b: dv.getUint8(o + 2), ptr, len,
                   rate: dv.getUint32(o + 12, true), bytes: new Uint8Array(s.memory.buffer, ptr, len).slice() });
    }
    return out;
}
function songRequest(s) {
    if (!s.demo.pollSongRequest()) return null;
    return new TextDecoder().decode(new Uint8Array(s.memory.buffer, s.demo.songNamePtr(), s.demo.songNameLen()));
}

/// docs/sealed-loader.js's postSfx, cut out of the loader and run over a stand-in worklet port:
/// the messages the real host would post for the cart's queue.
async function hostMessages(s, n, at) {
    const src = (await readFile("docs/sealed-loader.js", "utf8")).match(/^function postSfx\(mem, at, n\) \{[\s\S]*?^\}\n/m)[0];
    const posted = [];
    const run = new Function("audioNode", `let songGen = 0, sndhResident = null, songPosted = Promise.resolve(), sfxChain = Promise.resolve();
        ${src}; postSfx(arguments[1], arguments[2], arguments[3]); return sfxChain;`);
    await run({ port: { postMessage: (m) => posted.push(m) } }, s.memory, at, n);
    return posted;
}

/// The audio module (docs/demo-audio.wasm over machine-audio.wasm), as audio_switch_check.mjs runs it.
async function audioModule() {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const k of Object.keys(machine)) if (k.startsWith("machine")) env[k] = machine[k];
    const d = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    d.audioInit();
    const left = new Float32Array(memory.buffer, machine.audioLeftPtr(), 1024);
    return {
        d,
        load(msg) { // the worklet's loadSndh / loadSap: writeSong, load, play the tune
            const cap = d.audioSongCapacity(), src = new Uint8Array(msg.bytes), len = Math.min(src.length, cap);
            new Uint8Array(memory.buffer, d.audioSongPtr(), cap).set(src.subarray(0, len));
            if (msg.type === "loadSndh") return d.audioLoadSndh(len) && (d.audioSndhPlay(msg.tune || 0), true);
            return d.audioLoadSap(len) && (d.audioSapPlay(msg.tune || 0), true);
        },
        peak() { let p = 0; for (let b = 0; b < 43; b++) { d.audioRender(1024); for (const v of left) p = Math.max(p, Math.abs(v)); } return p; },
    };
}

/// A row of the page is the selected one: its first cell (a space) is inked all over (inverse).
const inverse = (s, row) => glass(s).subarray(row * 8 * 640, row * 8 * 640 + 8).every((p) => p === 0);

export async function soundPage(s, expect) {
    const files = parseDisk(s.disk, "demo-sysinfo.zmd").mounted.files;
    const disk = (n) => s.disk.subarray(files[n].start, files[n].start + files[n].len);
    s.demo.key(K.F1 + 2);
    frames(s, 2);
    drain(s); songRequest(s); // nothing from the other pages
    let rows = page(s);
    for (const [i, f] of FILES.entries()) {
        const r = rows[FILES_ROW + i];
        expect(f.name in files && r.includes(f.name) && r.includes(`${files[f.name].len} BYTES`) && r.includes(f.kind),
            `page 3 lists ${f.name} off the disk: ${files[f.name]?.len} bytes, ${f.kind}`);
    }
    expect(inverse(s, FILES_ROW) && !inverse(s, FILES_ROW + 1), "the first file is the selected one, in inverse");
    const audio = await audioModule();
    for (const [i, f] of FILES.entries()) {
        if (i > 0) { s.demo.input(1); frames(s, 1); } // Down
        expect(inverse(s, FILES_ROW + i), `Down selects ${f.name}`);
        drain(s); songRequest(s);
        s.demo.key("p".charCodeAt(0));
        frames(s, 1);
        const stop = songRequest(s), q = drain(s), e = q.find((x) => x.op === f.op);
        expect(!!e && (f.op !== 8 || e.a === f.a) && (!f.rate || e.rate === f.rate),
            `P on ${f.name}: sfx op ${f.op}${f.a ? ` kind ${f.a}` : ""}${f.rate ? ` at ${f.rate} Hz` : ""} (${q.map((x) => x.op).join(",")})`);
        const want = disk(f.name);
        expect(!!e && e.len === want.length && e.bytes.every((b, j) => b === want[j]), `${f.name}: the bytes handed over are the FAT file's, read through the drive`);
        if (f.op === 8 && e) {
            const msgs = await hostMessages(s, q.length, s.demo.sfxEntriesPtr());
            const m = msgs.find((x) => x.type === (f.a === 1 ? "loadSndh" : "loadSap"));
            const ok = !!m && audio.load(m), peak = ok ? audio.peak() : 0;
            expect(ok && audio.d.audioMode() === f.mode && peak > 0.01,
                `the host posts ${m?.type}, the audio module plays it in mode ${audio.d.audioMode()} (want ${f.mode}), peak ${peak.toFixed(3)}`);
        }
        if (i === 2) expect(stop === "none", `playing ${f.name} stopped the SAP before it ("${stop}")`);
        rows = page(s);
        expect(field(rows, "STATUS") === `PLAYING ${f.name}` && rows[FILES_ROW + i].includes("PLAYING"), `the page says ${f.name} plays`);
        s.demo.key("s".charCodeAt(0));
        frames(s, 1);
        const req = songRequest(s), after = drain(s);
        expect(f.op === 8 ? req === "none" : after.some((x) => x.op === 7), `S stops ${f.name} (${f.op === 8 ? `song "${req}"` : "sampleStop"})`);
        expect(field(page(s), "STATUS") === "STOPPED", "the page says STOPPED");
        if (i === 1) { s.demo.key("p".charCodeAt(0)); frames(s, 1); } // the SAP plays on into the PCM's turn
    }
}
