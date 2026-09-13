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
const WANT = ["union_multifake", "union_textracker"]; // by teleport key: door '9', door 'H'
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
    return { memory, demo };
}

// The remake's teleport keys (entities.js:99-152, controls.zig): '1'..'9' are
// doors 0..8, '0' door 9, 'H' door 10, in TMX object order (menu_map.zig DOORS).
const TELEPORT = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "H"];
const dec = new TextDecoder();
const launched = []; // [door key, tag] for every door that asked for a cart
for (const k of TELEPORT) {
    const { memory, demo } = await boot("docs/demo-union_demo.wasm");
    demo.frame(16.6);
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
for (const tag of ["union_demo", "union_intro"])
    if (!channels.includes(tag)) problems.push(`${tag} is missing from the channel list`);

if (problems.length) {
    console.log(`union_demo doors: FAIL\n  ${problems.join("\n  ")}`);
    process.exit(1);
}
console.log(`union_demo doors: ${launched.join(" and ")} launched by tag from the street, disks present, off the ${channels.length} channels`);
