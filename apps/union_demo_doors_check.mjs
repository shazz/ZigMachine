// Headless proof that the Union Demo hub launches its ported screens BY TAG.
//
// The Union screens are not channels and not menu entries (Matt, 2026-09-13):
// the hub's doors are the only way in. So this teleports Charly to each door,
// presses fire, polls the cart-request bridge the way docs/sealed-loader.js's
// loop does (pollCartRequest -> getCartTagPtr/Len), and requires every tagged
// door to ask for its cart, with that cart's disk present and kept off the
// channel list. A hub door is also walked to with the browser's key events. The
// cracktro (union_intro, the CODEF one) reaches its own door street, whose doors are
// decorative: Space there asks for no cart.
//
//   node apps/union_demo_doors_check.mjs
import { readFile, access } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const WANT = ["union_beatdis", "union_deltaforce", "union_tnt3", "union_superscroller", "union_tnt1", "union_reps", "union_tnt2", "union_l16", "union_multifake", "union_texcopier", "union_textracker"]; // by teleport key: doors '1', '2', '3', '5', '6', '7', '8', '9', '0', 'H'
const DIR = { fire: 5 };

const machines = []; // every boot's video machine, for the zg.mem refusal check

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
    machines.push(machine);
    return { memory, machine, demo };
}

// A fresh hub opens on the intro splash (union_demo/opening.zig): Space (as the host sends
// it: input fire + key 32), 30 frames after the splash's tune is asked for, ends it; the
// graphics depack behind the ONE TEX panel (The Carebears' credits), which holds once landed
// until Space again (pressed every 30 frames from then on); then the street starts with its
// own tune. No cart swap on the way. Returns the first Space and the street's first frame.
const dec = new TextDecoder();
function untilLoaded(demo, memory) {
    let space = -1;
    for (let f = 0; f < 1200; f++) {
        if (space >= 0 && f >= space && (f - space) % 30 === 0) { demo.input(DIR.fire); demo.key(32); }
        demo.frame(16.6);
        if (demo.pollCartRequest() !== 0) throw new Error(`the hub asked for a cart swap at frame ${f}, before its street`);
        if (!demo.pollSongRequest()) continue;
        const name = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
        if (name === "ikari_union.sndh" && space < 0) space = f + 30; // the splash is up
        if (name.includes("alloy_run")) return { space, street: f + 1 };
    }
    throw new Error("the hub never reached its street");
}

// The remake's teleport keys (entities.js:99-152, controls.zig): '1'..'9' are
// doors 0..8, '0' door 9, 'H' door 10, in TMX object order (menu_map.zig DOORS).
const TELEPORT = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "H"];
const launched = []; // [door key, tag] for every door that asked for a cart
for (const k of TELEPORT) {
    const { memory, demo } = await boot("docs/demo-union_demo.wasm");
    untilLoaded(demo, memory);
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
// channels.json is a list of {tag, title, type} records (tools/channels.py).
const channels = JSON.parse(await readFile("docs/channels.json", "utf8")).map((c) => c.tag);
for (const tag of WANT) {
    try { await access(`docs/demo-${tag}.zmd`); } catch { problems.push(`no disk docs/demo-${tag}.zmd`); }
    if (channels.includes(tag)) problems.push(`${tag} is a +/- channel; it must be hub-only`);
}
// The Union Demo is ONE cart opening on its intro (Matt, 2026-09-13 and 10-23): the +/-
// channel and the UNION DEMO menu entry boot union_demo, whose splash leads to the street.
for (const tag of ["union_demo", "union_intro"])
    if (!channels.includes(tag)) problems.push(`${tag} is missing from the channel list`);
if (channels.includes("union_intro_screen")) problems.push("union_intro_screen is still a channel; the splash lives in union_demo");
const catalog = await readFile("apps/zig/scenes/catalog.zig", "utf8");
const menu = catalog.match(/\.name = "UNION DEMO", \.tag = "([^"]*)"/);
if (!menu || menu[1] !== "union_demo") problems.push(`the UNION DEMO menu entry boots "${menu?.[1]}", not union_demo`);

// The cracktro (union_intro) flows from its parts into its door street with no cart swap, and
// its 18 doors (efmain.js posDoors) are decorative (Matt, 2026-10-23): Space held down (fire
// every frame, as the host sends it) from boot for a whole lap asks for nothing.
const MAIN_PLANE = 1; // the parts draw on plane 0; the door street enables plane 1
{
    const { machine, demo } = await boot("docs/demo-union_intro.wasm");
    let main = -1;
    const asked = [];
    const LAP = Math.floor(778 / 0.3); // frames for one lap of the street (main.zig SCROLL_WRAP, 0.3 tiles a frame)
    for (let f = 0; f < 6000 && (main < 0 || f < main + LAP); f++) {
        machine.hwClear(); // the host loop: rendered planes, or the HBL-driven depack never runs
        demo.frame(16.6);
        for (let p = 0; p < machine.hwPlanesNumber(); p++) if (demo.isPlaneEnabled(p)) machine.hwRenderPlane(p);
        if (main < 0 && demo.isPlaneEnabled(MAIN_PLANE)) main = f;
        demo.input(DIR.fire);
        const req = demo.pollCartRequest();
        if (req !== 0) asked.push(`${req} at frame ${f}`);
    }
    if (main < 0) problems.push("union_intro never reached its door street");
    if (asked.length) problems.push(`union_intro asked for a cart: ${asked.slice(0, 3).join(", ")} (its doors are decorative)`);
    console.log(`union_intro: parts -> door street at frame ${main}, no swap; Space for a lap asked for nothing`);
}

// A hub door entered the way a player does with the browser's keys (docs/sealed-loader.js):
// Up and Right held (auto-repeat keydowns), Space tapped (keydown, keyup) -- not a teleport.
{
    const { memory, demo } = await boot("docs/demo-union_demo.wasm");
    untilLoaded(demo, memory);
    let tag = null;
    for (let f = 0; f < 600 && tag === null; f++) {
        if (f % 2 === 0) demo.input(3);
        if (f % 2 === 1 && f < 300) demo.input(0);
        if (f % 30 === 0) { demo.input(DIR.fire); demo.key(32); }
        if (f % 30 === 3) demo.inputRelease(DIR.fire);
        demo.frame(16.6);
        if (demo.pollCartRequest() === 1) tag = dec.decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
    }
    if (tag !== WANT[0]) problems.push(`walking up and right with Space tapped asks for "${tag}", not ${WANT[0]} (the first door)`);
}

// The opening is ONE intro screen: the splash, then a single TEX panel (the street's
// loader: its depack takes ~96 frames), then the street, in one cart with no swap.
{
    const { memory, demo } = await boot("docs/demo-union_demo.wasm");
    const { space, street } = untilLoaded(demo, memory);
    if (space < 0 || street - space > 160)
        problems.push(`the opening: Space at frame ${space}, street at ${street}: more than one loader panel between them`);
    console.log(`union_demo: splash -> Space (frame ${space}) -> one loader panel -> street (frame ${street}), no swap`);
}
// The hub and the intro depack into zg.mem blocks: a refusal is a screen that never loaded.
const refused = machines.reduce((n, m) => n + m.hwRamAllocFailures(), 0);
if (refused) problems.push(`${refused} zg.mem allocation(s) refused`);

if (problems.length) {
    console.log(`union_demo doors: FAIL\n  ${problems.join("\n  ")}`);
    process.exit(1);
}
console.log(`union_demo doors: ${launched.join(" and ")} launched by tag from the street, disks present, off the ${channels.length} channels`);
