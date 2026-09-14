// Headless proof that the Union cracktro's music starts WITH THE TRSI LOGO, that
// keys 1-6 pick the tune during the intro parts too, and that nothing restarts
// or overrides the playing tune (Matt: "the music should start with the trsi
// logo"). The Codef remake (prototypes/oldies/UnionDemoCracktro/intro/index.html)
// starts Sharpness Buzztone in init() together with its sequencer, whose first
// effect is the TRSI logo. Its key handler is global (document.onkeydown), and
// keys only switch when `currentTrack != n`. Its main part never touches the music.
//
// Boots demo-union_intro.wasm over the real machine + ROM and runs the host loop
// exactly (clear, frame, render every ENABLED plane): the TRSI animation is
// depacked from HBL handlers, which only run inside hwRenderPlane. The first
// TRSI frame is the first frame plane 0 is enabled (the RASTERS depack shows
// none). Keys arrive the way docs/sealed-loader.js sends them to a cart that does
// not own the keyboard: key n -> setShadeMode(n - 1). Requires, in order:
//   - track 1, at or before the first TRSI frame;
//   - key 3 during TRSI -> Androids.ymraw; key 5 -> lap_33.sndh; key 5 again -> nothing;
//   - the main screen is reached, and asks for nothing: Lap 33 keeps playing.
//
//   node apps/union_intro_music_check.mjs              # the check
//   node apps/union_intro_music_check.mjs --fail-proof # must FAIL: another first tune wanted
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112, FRAMES = 1200; // main starts around frame 960
const FAIL_PROOF = process.argv.includes("--fail-proof");
const FIRST = FAIL_PROOF ? "union/150_mph.sndh" : "union/sharpness_buzztone.sndh";
const KEYS = [[30, 3], [60, 5], [90, 5]]; // [frames after the first TRSI frame, key]
const WANT = [FIRST, "union/Androids.ymraw", "union/lap_33.sndh"]; // every request, in order
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

function pressDue(demo, seen, f) {
    for (const [after, key] of KEYS) if (seen.trsi >= 0 && f === seen.trsi + after) {
        const owns = demo.ownsKeyboard ? demo.ownsKeyboard() !== 0 : false;
        if (!owns) demo.setShadeMode(key - 1); // sealed-loader.js: "1234567" -> setShadeMode(n - 1)
        seen.keys.push({ f, key, owns, inTrsi: seen.main < 0 });
    }
}

// Run the host loop; note the first TRSI and main frames, the keys, every request.
function run({ memory, machine, demo }) {
    const dec = new TextDecoder(), planes = machine.hwPlanesNumber();
    const seen = { trsi: -1, main: -1, keys: [], requests: [] };
    for (let f = 0; f < FRAMES; f++) {
        pressDue(demo, seen, f);
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
for (const k of seen.keys) console.log(`  frame ${k.f}: key ${k.key}${k.owns ? " (cart owns the keyboard: not sent)" : ""}${k.inTrsi ? " during the intro" : ""}`);
for (const r of seen.requests) console.log(`  frame ${r.f}: song request "${r.name}"`);
const [first] = seen.requests;
const checks = [
    [!!first && first.name === FIRST, `the first request is "${FIRST}"`],
    [seen.trsi >= 0 && !!first && first.f <= seen.trsi, "it comes at or before the first TRSI frame"],
    [seen.keys.length === KEYS.length && seen.keys.every((k) => k.inTrsi && !k.owns), "keys 3, 5, 5 reach the cart during the intro"],
    [seen.requests.length === WANT.length && seen.requests.every((r, i) => r.name === WANT[i]),
        "key 3 -> Androids, key 5 -> Lap 33, key 5 again -> nothing"],
    [seen.main > 0 && seen.requests.every((r) => r.f < seen.main), "the main screen is reached and requests nothing"],
];
for (const [ok, what] of checks) console.log(`  ${ok ? "ok  " : "FAIL"} ${what}`);
const ok = checks.every(([c]) => c);
if (FAIL_PROOF) {
    console.log(ok ? "=> FAIL ❌ the fail proof passed: the check cannot tell a wrong tune" : "=> PASS ✅ fail proof: a wrong first tune is refused");
    process.exit(ok ? 1 : 0);
}
console.log(ok ? "=> PASS ✅ music starts with the TRSI logo, keys 1-6 pick the tune, nothing restarts it" : "=> FAIL ❌ the cracktro's music does not behave like the remake");
process.exit(ok ? 0 : 1);
