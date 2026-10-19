// Headless LOCKBUSTER 2 driver (cart 92). The Go production
// github.com/olivierh59500/go-lockbuster2 tested its screen-memory clock
// against gzipped RAM snapshots of the ORIGINAL 68000 routines
// (internal/source/testdata/: header + all six scroll engines); this harness
// holds the Zig cart to the same bars, end to end:
//   engine   at the seven checkpoints (both title slides and all six
//            engines) the cart's exposed ring window hashes to the
//            checkpoint's sha256, byte for byte, phase and toggles included
//   picture  the machine's 320x200 window AND its border raster equal the Go
//            shader's output, computed here from the same inputs (the 16
//            words, the F5/F6 HBL bank, floor(y/2), the row+9 ink raster)
//   keys     F1..F6 steer exactly what message-3 advertises
//   cycle    tick 22000 is one full sequence and a text restart: header done
//            (header_tick 610), phase still in 0..7 (Go's regression test)
//   leave    Escape and Space both hand the screen back to the menu
//   soak     no zg.mem allocation refused; ms/frame reported, not budgeted
//   node apps/lockbuster2_headless.mjs [outdir]
//   node apps/lockbuster2_headless.mjs --break rasters
//            the ONLY check that runs is the inverted one (the border/sides
//            must be ONE flat colour): it passes only when the real screen's
//            per-line raster is GONE, so the gate that runs it on the shipped
//            cart fails, i.e. the shipped cart cannot regress into a screen
//            whose bars are a static palette without this line noticing
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { performance } from "node:perf_hooks";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const VBL_MS = 20;
const OUT = process.argv[2] || "/tmp/lockbuster2";
const bi = process.argv.indexOf("--break");
const brk = bi > 0 ? process.argv[bi + 1] : null;
if (brk && brk !== "rasters") throw new Error(`--break rasters only`);
const breakRasters = brk === "rasters";

const W = 320, H = 200;
const VBORDER = 40; // PHYSICAL height of the top/bottom border bands

// ---------------- boot (the rno_natrium shape: machine + ROM + cart) --------
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: romEnv })).instance.exports;
machine.hwSetRomHigh(romRam(await readFile("docs/rom.wasm")).high ?? 0);
const noop = () => {};
const cartBytes = await readFile("docs/demo-lockbuster2.wasm");
const env = {
    ...romEnv,
    hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop, hwRamSize: machine.hwRamSize,
    hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
    hwRamAlloc: machine.hwRamAlloc, hwRamMark: machine.hwRamMark,
    hwRamRelease: machine.hwRamRelease, hwRamAllocFailures: machine.hwRamAllocFailures,
    hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
    hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
    hwRomRamFree: machine.hwRomRamFree, ...rom,
};
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;
demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
machine.hwInit();
demo.boot();
demo.skipBoot();

await mkdir(OUT, { recursive: true });
console.log("boot ok");

// ---------------- helpers ----------------------------------------------------
const errors = [];
const ok = (cond, msg) => {
    if (cond) console.log(`  ok: ${msg}`);
    else errors.push(msg);
};
const check = (cond, msg) => {
    if (!cond) throw new Error(msg);
    console.log(`  ok: ${msg}`);
};

const stateFlags = () => {
    const s = demo.lb2State();
    return {
        phase: s & 7,
        gold: !!(s & (1 << 19)),
        color_text: !!(s & (1 << 20)),
        new_raster: !!(s & (1 << 21)),
    };
};

const engineScreen = () => {
    const ptr = demo.lb2Screen();
    if (!ptr) throw new Error("the engine window export is not ready");
    return new Uint8Array(memory.buffer, ptr, 32000);
};

let framesRendered = 0;
const stepFrame = () => {
    machine.hwClear();
    demo.frame(VBL_MS);
    framesRendered++;
};
const runTo = (tick) => {
    while (demo.lb2Tick() < tick) stepFrame();
};
/// A key's effect lands in the NEXT render; the border is painted one
/// hwClear behind the plane, so two frames make state/table/composite agree.
const pressKey = (cp) => {
    demo.key(cp);
    stepFrame();
    stepFrame();
};

const pw = machine.hwPhysWidth(); // 800: low res is x-doubled
const ph = machine.hwPhysHeight();
const bx = machine.hwBorderX(), by = machine.hwBorderY();
const pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), pw * ph * 4);

/// The composite as RGB, the visible 320x200 plus the left border column.
function presentRGB() {
    machine.hwRenderPlane(0);
    const win = new Uint8Array(W * H * 3);
    for (let y = 0; y < H; y++)
        for (let x = 0; x < W; x++) {
            const i = ((by + y) * pw + (bx + x * 2)) * 4;
            win.set(pfb.subarray(i, i + 3), (y * W + x) * 3);
        }
    const border = new Uint8Array(ph * 3);
    for (let line = 0; line < ph; line++)
        border.set(pfb.subarray((line * pw + 0) * 4, (line * pw + 0) * 4 + 3), line * 3);
    return { win, border };
}

async function shot(path, win) {
    await writeFile(path, Buffer.concat([Buffer.from(`P6\n${W} ${H}\n255\n`), win]));
}

function eq(got, want, what) {
    for (let i = 0; i < want.length; i++)
        if (got[i] !== want[i])
            throw new Error(
                `${what}: byte ${i} (pixel ${(((i / 3) | 0) % W)},${((i / 3) | 0 / W) | 0}) is ` +
                `${got[i]} but the Go shader says ${want[i]}`,
            );
}

function borderColors(border) {
    const seen = new Set();
    for (let line = VBORDER; line < VBORDER + H; line++)
        seen.add(border[line * 3] + "," + border[line * 3 + 1] + "," + border[line * 3 + 2]);
    return [...seen];
}

// ---------------- the model: the Go shader, ran over the ring's bytes --------
// The 16 words are the Go shader's quoted uniforms; the raster banks are read
// from the very files the cart embeds, the Go way (BE words; past the bank: 0).
const WORDS = [0, 0, 0x134, 0x235, 0x124, 0x023, 0x346, 0x245, 0x356, 0x457, 0x467, 0x567, 0x677, 0x577, 0x701, 0x777];
const WORDS_GOLD = [0, 0, 0x341, 0x532, 0x421, 0x320, 0x643, 0x542, 0x653, 0x754, 0x764, 0x765, 0x776, 0x775, 0x107, 0x777];
const RASTERS = [
    await readFile("apps/zig/assets/screens/lockbuster2/raster-old.bin"),
    await readFile("apps/zig/assets/screens/lockbuster2/raster-new.bin"),
];
const rasterWord = (bank, row) => (2 * row + 1 < RASTERS[bank].length
    ? RASTERS[bank].readUInt16BE(2 * row)
    : 0);
const nib = (w) => [((w >> 8) & 7) * 34, ((w >> 4) & 7) * 34, (w & 7) * 34];

function modelFrame(state, engineScreen) {
    const bank = state.new_raster ? 1 : 0;
    const words = state.gold ? WORDS_GOLD : WORDS;
    const raster = (row) => nib(rasterWord(bank, row));
    const px = new Uint8Array(W * H * 3);
    for (let y = 0; y < H; y++) {
        const row = (y / 2) | 0;
        for (let x = 0; x < W; x++) {
            const at = y * 160 + (x >> 4) * 8;
            const half = (x & 8) >> 3;
            const bit = 7 - (x & 7);
            let v = 0;
            for (let p = 0; p < 4; p++) v |= ((engineScreen[at + half + p * 2] >> bit) & 1) << p;
            const c = v === 0 ? raster(row)
                : (v === 1 && state.color_text) ? raster(row + 9)
                : nib(words[v]);
            const o = (y * W + x) * 3;
            px[o] = c[0]; px[o + 1] = c[1]; px[o + 2] = c[2];
        }
    }
    // The border carries colour 0's word per PHYSICAL line, black in the bands.
    const border = new Uint8Array(ph * 3);
    for (let line = 0; line < ph; line++) {
        const inBand = line >= VBORDER && line < VBORDER + H;
        const c = inBand ? raster(((line - VBORDER) / 2) | 0) : nib(0);
        border[line * 3] = c[0]; border[line * 3 + 1] = c[1]; border[line * 3 + 2] = c[2];
    }
    return { px, border };
}

// ---------------- run ---------------------------------------------------------
if (breakRasters) {
    // The inverted check ONLY: run deep enough that a scroll phase with its
    // bars is up, then demand a flat border. On the real screen this fails,
    // which is exactly what the gate harness line promises.
    runTo(1800);
    stepFrame(); stepFrame();
    const border = presentRGB().border;
    const distinct = borderColors(border).length;
    if (distinct > 1)
        throw new Error(`--break rasters caught: the border runs ${distinct} distinct per-line colours, which IS the real raster`);
    console.log("  break rasters: the border is one flat colour (a dead raster); this harness line only stops a regression");
    process.exit(0);
}

// Music: the Rollout. The production's own music.ym is ROLLOUT1.YM ("Rollout
// Tune 1", Jochen Hippel) => the archive's Rollout.sndh, subtune 1.
demo.frame(VBL_MS);
const songName = demo.pollSongRequest()
    ? Buffer.from(memory.buffer.slice(demo.songNamePtr(), demo.songNamePtr() + demo.songNameLen())).toString()
    : null;
check(songName === "lockbuster2_rollout.sndh" && demo.songTune() === 1,
    `music: Rollout.sndh #1 requested (got "${songName}" #${demo.songTune()})`);

// Engine fidelity at the Go tree's checkpoints, from its own JSON.
const CHECKPOINTS = [
    ["header", 610, "0c92bddb4e96f3ea9ec9f0f64a668255a6c15527ac09f6f119cafde60c7c4a39"],
    ["map-0", 809, "bffe73a61077850d27a9e2202cb7a4ca04036bd9b58a8c6e814f6461d360d838"],
    ["map-1", 1525, "3a7c93b1b1b76ba24fe6a84c6838e97c2787c99d907c118b6de1aac86012b5b1"],
    ["map-2", 2245, "a234eca35233a90c4529e0f903dbb9c8e79b2c9162a59022fcc9c8f400d4146f"],
    ["map-3", 3041, "96f568f44fe73da24eb69b3b302bb56d5d4edd1017b9e39949995d7f56f5b4ae"],
    ["map-4", 3725, "6f7e1d4fa5c216465779457999fc1bdf6e797844e81b95d68fc322111920ca6d"],
    ["map-5", 5077, "ae6ff009393e70804bee29083950ac7f748675ecd4389845204fcef1ada9c76c"],
];
let held = null;
for (const [name, tick, want] of CHECKPOINTS) {
    runTo(tick);
    const got = createHash("sha256").update(engineScreen()).digest("hex");
    check(got === want, `${name}: tick ${tick} is the original screen memory byte for byte`);
    if (!held) {
        held = stateFlags();
        const model = modelFrame(held, engineScreen());
        const got2 = presentRGB();
        eq(got2.win, model.px, `${name} 320x200 window == Go shader`);
        eq(got2.border, model.border, `${name} border raster == Go shader`);
        await shot(`${OUT}/${name}.ppm`, got2.win);
    }
}
check(framesRendered > 0, "frames actually rendered");

// The bars are a REAL raster, not a static palette: >= 6 distinct colours per
// line along the border, edges included, and the bands below line 200 stay black.
{
    runTo(1800); // mid scroll phase 0, bars + letters on screen
    stepFrame(); stepFrame();
    const { border, win } = presentRGB();
    // the drawn frame is the Go shader's, pixel for pixel, in the demo's own bank
    const model = modelFrame(stateFlags(), engineScreen());
    eq(win, model.px, "320x200 window (scroll phase)");
    eq(border, model.border, "border raster (scroll phase)");
    const colors = borderColors(border);
    check(colors.length >= 6, `rasters: ${colors.length} distinct border colours, edge to edge`);
    let flatTop = true;
    for (let line = 0; line < VBORDER; line++)
        for (let c = 0; c < 3; c++)
            if (border[line * 3 + c] !== 0) flatTop = false;
    check(flatTop, "rasters: the top/bottom border bands stay black (past the 100-word table)");
    await shot(`${OUT}/scroll.ppm`, win);
}

// F5's alternate HBL bank changes the per-line words; F6 is the demo's own.
pressKey(0xe006);
pressKey(0xe005); // new HBL
check(stateFlags().new_raster, "F5 switched to the new HBL table");
{
    const model = modelFrame(stateFlags(), engineScreen());
    const got = presentRGB();
    eq(got.win, model.px, "320x200 window (F5 bank)");
    eq(got.border, model.border, "border raster (F5 bank)");
    await shot(`${OUT}/f5-newhbl.ppm`, got.win);
}
pressKey(0xe006);
check(!stateFlags().new_raster, "F6 back to the demo's own HBL table");

// F1/F2 (gold/metal) and F3/F4 (coloured/black text background), held while
// the letters are up: the whole window re-equals the model each time.
pressKey(0xe002); // F2 metal
check(!stateFlags().gold, "F2 metal text");
pressKey(0xe004); // F4 black text background
check(!stateFlags().color_text, "F4 black text background");
pressKey(0xe003); // F3 coloured again
pressKey(0xe001); // F1 gold
check(stateFlags().gold, "F1 gold text");

// Cycle: Go's TestCompleteSequenceAndRestart -- tick 22000 has the header
// done and the phase still sane.
runTo(22000);
const end = stateFlags();
check(demo.lb2Tick() === 22000, "cycled: the engine ran to its own tick 22000");
check(end.phase >= 0 && end.phase <= 7, `phase sane at tick 22000 (${end.phase})`);

// Leave on Escape and on Space (the demo's own bindings) -> back to the menu.
runTo(22300);
demo.key(0xe012);
{
    demo.frame(VBL_MS);
    const r = demo.pollCartRequest();
    check(r === -1, `Escape hands back to the menu (pollCartRequest ${r})`);
}
runTo(22340);
demo.key(32);
{
    demo.frame(VBL_MS);
    const r = demo.pollCartRequest();
    check(r === -1, `Space hands back to the menu (pollCartRequest ${r})`);
}

// Soak + shots: honest ms/frame, no allocation refused.
{
    const t0 = performance.now();
    const from = demo.lb2Tick();
    for (let i = 0; i < 300; i++) stepFrame();
    const ms = (performance.now() - t0) / (demo.lb2Tick() - from);
    await shot(`${OUT}/soak.ppm`, presentRGB().win);
    console.log(`  soak: ${ms.toFixed(3)} ms/frame over 300 frames (update + render + composite)`);
    const refused = machine.hwRamAllocFailures();
    check(refused === 0, `zg.mem: ${refused} refused allocations`);
}

if (errors.length) {
    for (const e of errors) console.error(`FAIL: ${e}`);
    process.exit(1);
}
console.log("lockbuster2: gate green");
