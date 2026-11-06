// The VU meters' part of the "same pixels" proof (hashes.sh proves everything else with the meters off). A
// playing picture has more than 255 colours (the meters are a 32x64 ARGB gradient), so the palette maps the
// extras to the nearest entry, and which entry depends on the order the colours came in: two builds that draw
// the same picture in another order can map a few gradient pixels differently. This runs three carts in
// lockstep and checks that every pixel where AFTER differs from BEFORE is a meter pixel: one where BEFORE
// differs from BEFORE_NO_VU (the same sources built without the meters).
//   node apps/ports/klystrack/vu_proof.mjs <before.wasm> <before_novu.wasm> <after.wasm> [frames=420] [keys=30,57349]
// From the repo root. Exit 1 if a pixel outside the meters differs.
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../../../docs/wasm_hiwater.js";

const [A, ANOVU, B] = process.argv.slice(2, 5);
const FRAMES = +(process.argv[5] ?? 420);
const KEYS = (process.argv[6] ?? "30,57349").split(";").filter(Boolean).map((k) => k.split(",").map(Number));
const DISK = await readFile("docs/demo-klystrack.zmd");

async function machineFor(cartPath) {
    const memory = new WebAssembly.Memory({ initial: 128, maximum: 128 });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), { env: { memory, hblDispatch() {} } })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(cartPath);
    const env = { memory, ...rom, consoleLogJS() {}, hostAudioStreamStart() {}, hostAudioFeed() {},
        diskReadBlock: (b, dst) => { const s = DISK.subarray(b * 512, b * 512 + 512); new Uint8Array(memory.buffer, dst, s.length).set(s); return s.length; } };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    const wasi = {};
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes))) {
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => 0;
        if (imp.module === "wasi_snapshot_preview1") wasi[imp.name] = (...a) => {
            if (imp.name.endsWith("_sizes_get")) { const v = new DataView(memory.buffer); v.setUint32(a[0], 0, true); v.setUint32(a[1], 0, true); return 0; }
            return imp.name === "fd_prestat_get" ? 8 : imp.name === "fd_write" ? 0 : 52;
        };
    }
    const demo = (await WebAssembly.instantiate(cartBytes, { env, wasi_snapshot_preview1: wasi })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit(); demo.boot(); demo.skipBoot();
    return {
        frame(f) {
            for (const [kf, code] of KEYS) { if (kf === f) demo.key(code); if (kf + 3 === f) demo.keyUp(code); }
            machine.hwClear(); demo.frame(1000 / 60); machine.hwRenderPlane(0);
            return new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), machine.hwPhysWidth() * machine.hwPhysHeight());
        },
    };
}

const [ma, mn, mb] = [await machineFor(A), await machineFor(ANOVU), await machineFor(B)];
let outside = 0, inside = 0, frames = 0, worst = 0;
for (let f = 1; f <= FRAMES; f++) {
    const a = ma.frame(f), n = mn.frame(f), b = mb.frame(f);
    let differs = false;
    for (let i = 0; i < a.length; i++) {
        if (a[i] === b[i]) continue;
        differs = true;
        if (a[i] !== n[i]) {
            inside++;
            for (let sh = 0; sh < 24; sh += 8) worst = Math.max(worst, Math.abs((a[i] >>> sh & 255) - (b[i] >>> sh & 255)));
        }
        else { if (!outside) console.log(`frame ${f}: pixel ${i} differs outside the meters`); outside++; }
    }
    frames += differs;
}
console.log(`${FRAMES} frames: ${frames} differ, ${inside} pixel-frames inside the meters (at most ${worst} a channel), ${outside} outside`);
process.exit(outside ? 1 : 0);
