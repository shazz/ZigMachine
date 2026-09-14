// Headless proof that the Union Demo hub launches its ported screens BY TAG.
//
// The Union screens are not channels and not menu entries (Matt, 2026-09-13):
// the hub's doors are the only way in. So this teleports Charly to each door,
// presses fire, polls the cart-request bridge the way docs/sealed-loader.js's
// loop does (pollCartRequest -> getCartTagPtr/Len), and requires every tagged
// door to ask for its cart, with that cart's disk present and kept off the
// channel list.
//
//   node apps/union_demo_doors_check.mjs
import { readFile, access } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const WANT = ["union_deltaforce", "union_multifake", "union_textracker"]; // by teleport key: door '2', '9', 'H'
const DIR = { fire: 5 };

async function boot(cartPath) {
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

// The hub first depacks its graphics behind menuloader.js's TEX panel; the
// street (and its music request) starts when that is done.
function untilLoaded(demo) {
    for (let f = 0; f < 400; f++) {
        demo.frame(16.6);
        if (demo.pollSongRequest()) return f + 1;
    }
    throw new Error("the hub never finished loading");
}

// The remake's teleport keys (entities.js:99-152, controls.zig): '1'..'9' are
// doors 0..8, '0' door 9, 'H' door 10, in TMX object order (menu_map.zig DOORS).
const TELEPORT = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "H"];
const dec = new TextDecoder();
const launched = []; // [door key, tag] for every door that asked for a cart
for (const k of TELEPORT) {
    const { memory, demo } = await boot("docs/demo-union_demo.wasm");
    untilLoaded(demo);
    demo.key(k.charCodeAt(0));
    for (let f = 0; f < 10; f++) demo.frame(16.6); // teleport, settle on the street
    let tag = null;
    for (let f = 0; f < 10 && tag === null; f++) {
        demo.input(DIR.fire);
        demo.frame(16.6);
        const req = demo.pollCartRequest();
        if (req === -1) { console.log(`union_demo doors: FAIL, door ${k} asked for the menu`); process.exit(1); }
        if (req === 1) tag = dec.decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
    }
    if (tag !== null) launched.push(tag);
}

const problems = [];
if (JSON.stringify(launched) !== JSON.stringify(WANT))
    problems.push(`doors launched [${launched.join(", ")}], want [${WANT.join(", ")}]`);
const channels = JSON.parse(await readFile("docs/channels.json", "utf8"));
for (const tag of WANT) {
    try { await access(`docs/demo-${tag}.zmd`); } catch { problems.push(`no disk docs/demo-${tag}.zmd`); }
    if (channels.includes(tag)) problems.push(`${tag} is a +/- channel; it must be hub-only`);
}
// The Union Demo opens on its intro (Matt, 2026-09-13): the +/- channel and the
// UNION DEMO menu entry boot union_intro_screen, not the street.
for (const tag of ["union_intro_screen", "union_intro"])
    if (!channels.includes(tag)) problems.push(`${tag} is missing from the channel list`);
if (channels.includes("union_demo")) problems.push("union_demo is a +/- channel; the demo's channel is its intro");
const catalog = await readFile("apps/zig/scenes/catalog.zig", "utf8");
const menu = catalog.match(/\.name = "UNION DEMO", \.tag = "([^"]*)"/);
if (!menu || menu[1] !== "union_intro_screen") problems.push(`the UNION DEMO menu entry boots "${menu?.[1]}", not union_intro_screen`);

// Every cracktro door (union_main alone, and at the end of union_intro) boots the intro.
async function doorRequest(cart, maxFrames) {
    const { memory, machine, demo } = await boot(cart);
    for (let f = 0; f < maxFrames; f++) {
        // The host loop: render the enabled planes, or HBL-driven state (union_intro's
        // rasters depack) never runs.
        machine.hwClear();
        demo.frame(16.6);
        for (let p = 0; p < machine.hwPlanesNumber(); p++) if (demo.isPlaneEnabled(p)) machine.hwRenderPlane(p);
        if (f % 4 === 0) demo.input(DIR.fire);
        const req = demo.pollCartRequest();
        if (req === 1) return dec.decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
        if (req === -1) return "menu";
    }
    return null;
}
for (const cart of ["union_main", "union_intro"]) {
    const got = await doorRequest(`docs/demo-${cart}.wasm`, cart === "union_main" ? 3000 : 6000);
    if (got !== "union_intro_screen") problems.push(`a ${cart} door asks for "${got}", not union_intro_screen`);
}

// Space on the intro opens FIRST_LOADER's panel; Space once it has landed goes
// on to the street.
{
    const { memory, demo } = await boot("docs/demo-union_intro_screen.wasm");
    let started = false;
    for (let f = 0; f < 400 && !started; f++) { demo.frame(16.6); started = demo.pollSongRequest() !== 0; }
    demo.frame(16.6);
    demo.key(32);
    const early = demo.pollCartRequest();
    for (let f = 0; f < 110; f++) demo.frame(16.6);
    demo.key(32);
    const req = demo.pollCartRequest();
    const tag = req === 1 ? dec.decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen())) : null;
    if (!started || early !== 0 || tag !== "union_demo")
        problems.push(`the intro: first Space asks for ${early} (want 0, the loader panel), Space after the panel asks for ${req} "${tag}", not 1 "union_demo"`);
}

if (problems.length) {
    console.log(`union_demo doors: FAIL\n  ${problems.join("\n  ")}`);
    process.exit(1);
}
console.log(`union_demo doors: ${launched.join(" and ")} launched by tag from the street, disks present, off the ${channels.length} channels`);
