// Headless proof that the Union cracktro's music starts WITH THE TRSI LOGO, and
// that the main screen keeps that tune instead of starting it again (Matt: "the
// music should start with the trsi logo"). The Codef remake (intro/index.html
// init()) starts Sharpness Buzztone together with its sequencer, whose first
// effect is the TRSI logo, and the main part never changes the track.
//
// Boots demo-union_intro.wasm over the real machine + ROM and runs the host loop
// exactly (clear, frame, render every ENABLED plane): the TRSI animation is
// depacked from HBL handlers, which only run inside hwRenderPlane. The first
// TRSI frame is the first frame plane 0 is enabled (the RASTERS depack shows
// none). The song bridge is polled every frame, the way docs/sealed-loader.js
// does. Requires:
//   - the first request is track 1, at or before the first TRSI frame;
//   - the main screen is reached (plane 2, its scrolltext, enabled);
//   - no second request: main does not restart the tune.
//
//   node apps/union_intro_music_check.mjs              # the check
//   node apps/union_intro_music_check.mjs --fail-proof # must FAIL: another tune wanted
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112, FRAMES = 1200; // main starts around frame 960
const FAIL_PROOF = process.argv.includes("--fail-proof");
const WANT = FAIL_PROOF ? "union/150_mph.sndh" : "union/sharpness_buzztone.sndh";
const TRSI_PLANE = 0, MAIN_PLANE = 2;

async function bootCart(cartPath) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(cartPath);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

// Run the host loop; note the first TRSI frame, the first main frame, and every request.
function run({ memory, machine, demo }) {
    const dec = new TextDecoder(), planes = machine.hwPlanesNumber();
    const seen = { trsi: -1, main: -1, requests: [] };
    for (let f = 0; f < FRAMES; f++) {
        machine.hwClear();
        demo.frame(16.6);
        for (let p = 0; p < planes; p++) if (demo.isPlaneEnabled(p)) machine.hwRenderPlane(p);
        if (seen.trsi < 0 && demo.isPlaneEnabled(TRSI_PLANE)) seen.trsi = f;
        if (seen.main < 0 && demo.isPlaneEnabled(MAIN_PLANE)) seen.main = f;
        if (demo.pollSongRequest())
            seen.requests.push({ f, name: dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())) });
    }
    return seen;
}

const seen = run(await bootCart("docs/demo-union_intro.wasm"));
console.log(`union_intro: first TRSI frame ${seen.trsi}, main screen from frame ${seen.main}`);
for (const r of seen.requests) console.log(`  frame ${r.f}: song request "${r.name}"`);
const first = seen.requests[0];
const checks = [
    [!!first && first.name === WANT, `the first request is "${WANT}"`],
    [seen.trsi >= 0 && !!first && first.f <= seen.trsi, "it comes at or before the first TRSI frame"],
    [seen.main > seen.trsi, "the main screen is reached after the intro"],
    [seen.requests.length === 1, "main does not request the tune again"],
];
for (const [ok, what] of checks) console.log(`  ${ok ? "ok  " : "FAIL"} ${what}`);
const ok = checks.every(([c]) => c);
if (FAIL_PROOF) {
    console.log(ok ? "=> FAIL ❌ the fail proof passed: the check cannot tell a wrong tune" : "=> PASS ✅ fail proof: a wrong tune name is refused");
    process.exit(ok ? 1 : 0);
}
console.log(ok ? "=> PASS ✅ the cracktro's music starts with the TRSI logo and main keeps it" : "=> FAIL ❌ the music does not start with the TRSI logo once");
process.exit(ok ? 0 : 1);
