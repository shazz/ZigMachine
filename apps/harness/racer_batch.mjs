// Headless RACER, Matt's board batch (R82, docs/ports/kestrel_racing/BATCH.md), on the shelf disk and SYNTHETIC car sets
// (tools/racer/carc.py from our own GT: no other data):
//   1. wheels (wheelspin.zig): a race at the recorded driver; the same run with the wheels never posed (key &) draws other
//      pixels mid-race while every racer,cars physics line is the same (the spin is drawn, never simulated);
//   2. the near chase camera (pov.zig): on the oval's grid the player's GT is whole and big in the picture, its lowest pixel
//      24 rows or more above the view's bottom (the tyres and their shadow in view: Matt's 32x-8 framing);
//   3. the x bench as a race: the picture HUD over the bench (rows 16-40 differ from key 0's bands) with the same lap CRC
//      lines; with the fake BARD queue the bench asks for the race tune and owns the effects' channels (key j: silent as
//      before); key _ (the PSG layout, what -Dracer_music uses) owns PSG 1, 3 and the noise only and writes no FM register;
//   4. the car switch (key ]): C:\RACER\ holds CAR.KCR (tagged STOCK) and PROTO.KCR (tagged PROTO); in a race ] cycles
//      CAR -> PROTO -> GT -> CAR, each tagged set's class taken, the view changes;
//   5. the course select's model turns (frames 0 and 120 differ above the info panel, the panels do not); fire: the car
//      select (racer,front,garage), its car turns, down shows the next car, fire races (racer,front,off).
//   node apps/harness/racer_batch.mjs [<shot dir>] [--break still|near|hud|tag|turn]
import { execFileSync } from "node:child_process";
import { diskHook } from "./racer_disk.mjs";
import { bootObj, key } from "./obj_machine.mjs";
import { makeCDrive } from "./scene_hash_disk.mjs";
import { png } from "./skystrike_zig_frame.mjs";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
const BREAKS = { still: "&", near: "~", hud: "<", tag: ">", turn: "*" };
if (BREAK !== null && !(BREAK in BREAKS)) { console.error(`racer_batch: unknown --break ${BREAK}`); process.exit(1); }
const OUT = argv[0] && !argv[0].startsWith("--") ? argv[0] : null;
const W = 320, H = 200, Y0 = 12, Y1 = 188, REG_FB_BASE = 0x44, OFF_PAL = 0x0100;
const errors = [], notes = [];
const fail = (m) => errors.push(m);

async function boot(hook = diskHook(), extra = () => {}) {
    const log = [];
    let block = 0;
    const cmds = [], songs = [];
    const S = await bootObj("site/carts/demo-racer.wasm", (s) => log.push(s), (env, m) => {
        hook(env, m);
        env.hostBardAttach = (b) => { block = b; return b ? 1 : 0; };
        extra(env);
    });
    const drain = () => {
        if (!block) return;
        const u = new Uint32Array(S.memory.buffer), h = block >> 2, head = u[h + 4];
        for (let t = u[h + 5]; t !== head; t = (t + 1) >>> 0) { const c = h + 16 + 4 * (t % 256); cmds.push([u[c], u[c + 1], u[c + 2]]); }
        u[h + 5] = head; u[h + 7] = u[h + 7] + 735; u[h + 8] = 1;
    };
    const step = () => {
        S.frame(); drain();
        if (S.demo.pollSongRequest()) songs.push(new TextDecoder().decode(new Uint8Array(S.memory.buffer, S.demo.songNamePtr(), S.demo.songNameLen())));
    };
    const B = {
        S, log, cmds, songs,
        run: (n) => { for (let i = 0; i < n; i++) step(); },
        key: (k) => { key(S, k); step(); step(); step(); },
        input: (d) => { S.demo.input(d); step(); S.demo.inputRelease(d); step(); },
        view: () => {
            const shown = [0, 1].filter((p) => S.demo.isPlaneEnabled(p))[0] ?? 0;
            const vb = S.machine.hwVideoBase(), dv = new DataView(S.memory.buffer, vb, OFF_PAL);
            return new Uint8Array(S.memory.buffer, vb + dv.getUint32(REG_FB_BASE + 4 * shown, true), W * H).slice();
        },
        lines: (tag) => log.filter((l) => l.startsWith(`racer,${tag},`)),
        shot: async (path) => {
            const px = B.view(), vb = S.machine.hwVideoBase(), pal = new Uint32Array(S.memory.buffer, vb + OFF_PAL, 256);
            await png(path, Uint32Array.from(px, (v) => pal[v] | 0xff000000), W, H);
        },
    };
    B.S.machine.hwSetCaps(0x7f);
    step();
    if (BREAK) B.key(BREAKS[BREAK]);
    return B;
}
const differ = (a, b, y0 = Y0, y1 = Y1) => { let n = 0; for (let i = y0 * W; i < y1 * W; i++) if (a[i] !== b[i]) n++; return n; };

// 1. the wheels turn: drawn, not simulated
async function wheels() {
    const run = async (still) => {
        const B = await boot();
        if (still) B.key("&");
        B.key("e"); B.key("a"); B.key("v"); B.key("s");
        B.run(420);
        return { px: B.view(), cars: B.lines("cars").join(" "), B };
    };
    const a = await run(false), b = await run(true);
    if (a.cars !== b.cars || !a.cars) fail("wheels: the physics lines moved with the drawn wheels");
    const d = differ(a.px, b.px);
    if (d < 20) fail(`wheels: the turning wheels draw ${d} pixels unlike the still ones (want >= 20)`);
    else notes.push(`wheels: ${d} pixels of turned tyre mid-race, the physics lines identical`);
    if (OUT) await a.B.shot(`${OUT}/batch_wheels.png`);
}

// 2. the near chase camera shows the whole car (the GT's tyres) above the view's bottom edge
async function near() {
    const B = await boot();
    B.key("e"); B.key("v");
    B.run(70);
    const px = B.view();
    let low = -1, wide = [W, 0];
    for (let y = Y0; y < Y1; y++) for (let x = 100; x < 220; x++) {
        const c = px[y * W + x];
        if (c >= 16 + 12 * 8 && c < 16 + 15 * 8) { low = Math.max(low, y); wide = [Math.min(wide[0], x), Math.max(wide[1], x)]; }
    }
    if (low < 0) return fail("near: no player car pixel in the near view");
    if (low > Y1 - 24 || wide[1] - wide[0] < 80) fail(`near: the player's car runs to row ${low} (want <= ${Y1 - 24}: tyres and shadow clear of the view's bottom, as 32x-8), ${wide[1] - wide[0]} px wide (want >= 80)`);
    else notes.push(`near: the GT whole, rows to ${low} (view bottom ${Y1}), columns ${wide[0]}..${wide[1]}`);
    if (OUT) await B.shot(`${OUT}/batch_near.png`);
}

// 3. the x bench is a race: the picture HUD, the race tune, the effects (and the PSG layout's channels)
async function bench() {
    const run = async (keys) => {
        const B = await boot();
        for (const k of keys) B.key(k);
        B.key("x");
        B.run(400);
        return { B, px: B.view(), crcs: B.lines("crc").join(" ") };
    };
    const hud = await run([]), bands = await run(["0"]);
    const d = differ(hud.px, bands.px, 16, 40);
    if (d < 200) fail(`bench: the picture HUD is not over the x bench (${d} pixels of rows 16-40 differ from key 0's bands)`);
    if (hud.crcs !== bands.crcs || !hud.crcs) fail("bench: the lap CRC lines changed with the HUD (they must be the bare view's)");
    const owned = hud.B.cmds.filter(([, ad]) => ad === 0xc300).map((c) => c[2]);
    if (!hud.B.songs.includes("kr_race.vgm") || owned.at(-1) !== 0xc30) fail(`bench: songs ${hud.B.songs}, owned ${owned.map((o) => o.toString(16))}: want the race tune and FM 5-6 + PSG 3 + noise`);
    const quiet = await run(["j"]);
    if (quiet.B.songs.includes("kr_race.vgm")) fail("bench: key j no longer silences the bench");
    const psg = await run(["_"]);
    const own = psg.B.cmds.filter(([, ad]) => ad === 0xc300).map((c) => c[2]);
    const fmAfter = psg.B.cmds.slice(psg.B.cmds.findIndex(([, ad, v]) => ad === 0xc300 && v === 0xd00) + 1).filter(([, ad]) => ad >= 0xc000 && ad < 0xc200);
    if (own.at(-1) !== 0xd00 || fmAfter.length) fail(`bench: the PSG layout owned ${own.map((o) => o.toString(16))} and wrote ${fmAfter.length} FM registers after`);
    else notes.push(`bench: HUD over the bench (${d} px), lap CRCs unmoved, the race tune + effects; the PSG layout owns d00, no FM write`);
    if (OUT) await hud.B.shot(`${OUT}/batch_bench_hud.png`);
}

// 4. key ]: the garage's cars, a tagged set's class taken
const CIMG = `
import sys; sys.path[:0] = ["tools", "fpga/tools"]
import sd_layout; from kos_fat_fixture import Image
from racer import carc, kcar_export
doc = kcar_export.loads(open("tools/racer/cars/gt.kcar.json").read())
pal = [(250, 250, 40), (20, 20, 20), (90, 200, 250), (40, 220, 90), (250, 120, 30), (200, 40, 220), (240, 240, 240)]
img = Image("SD CARD", 2048); hd = sd_layout.HD
img.mkdir(hd); img.mkdir(hd + "/RACER")
img.write(hd + "/RACER/CAR.KCR", carc.pack_set([carc.convert(doc, scale=carc.GT_SCALE)], pal, "STOCK", 1))
img.write(hd + "/RACER/PROTO.KCR", carc.pack_set([carc.convert(doc, scale=3.0)], None, "PROTO", 2))
sys.stdout.buffer.write(img.bytes())`;
async function carSwitch() {
    const img = new Uint8Array(execFileSync("python3", ["-I", "-c", CIMG], { maxBuffer: 8 << 20 }));
    const B = await boot((env, m) => { diskHook()(env, m); env.kosDriveRead = makeCDrive(env.memory, img); });
    B.key("e");
    B.run(20);
    const px0 = B.view();
    for (let i = 0; i < 3; i++) { B.key("]"); B.run(10); }
    const picks = B.lines("carpick").map((l) => l.split(",").slice(2).join(","));
    const want = ["PROTO,PROTO", "KESTREL GT,PROTO", "STOCK,STOCK"];
    if (picks.join(" ") !== want.join(" ")) fail(`car switch: ${picks.join(" ")} != ${want.join(" ")}`);
    B.key("]");
    if (differ(px0, B.view()) < 100) fail("car switch: the 3x PROTO set draws like the 2x STOCK one");
    if (!errors.length) notes.push(`car switch: ] cycles ${picks.join(" -> ")}, the class following the tag`);
}

// 5. the course select's turning model, the car select
async function selects() {
    const B = await boot();
    B.run(3);
    B.key("\r");
    if (!B.lines("front").includes("racer,front,select")) return fail("select: Enter on the title did not open the course select");
    const a = B.view();
    B.run(120);
    const b = B.view();
    const model = differ(a, b, 30, 116), panels = differ(a, b, 117, 178);
    if (model < 30 || panels) fail(`select: the course model moved ${model} pixels (want >= 30), the panels ${panels} (want 0)`);
    if (OUT) await B.shot(`${OUT}/batch_select.png`);
    B.input(5);
    if (!B.lines("front").includes("racer,front,garage")) return fail("select: fire did not open the car select");
    const c = B.view();
    B.run(60);
    const turned = differ(c, B.view(), 30, 140);
    if (turned < 30) fail(`car select: the car turned ${turned} pixels in a second (want >= 30)`);
    if (OUT) await B.shot(`${OUT}/batch_garage.png`);
    B.input(1);
    if (!B.lines("carpick").length) fail("car select: down did not show another car");
    B.input(5);
    if (B.lines("front").at(-1) !== "racer,front,off" || B.S.demo === undefined) fail(`car select: fire did not race (${B.lines("front").at(-1)})`);
    if (!errors.length) notes.push(`selects: the course model turns (${model} px in 2 s), panels still; the car select turns (${turned} px), down / fire`);
}

await wheels();
await near();
await bench();
await carSwitch();
await selects();
for (const n of notes) console.log(`racer_batch: ${n}`);
if (BREAK) {
    if (!errors.length) { console.error(`racer_batch: FAIL: --break ${BREAK} was NOT caught`); process.exit(1); }
    console.log(`racer_batch: OK --break ${BREAK} caught: ${errors[0]}`);
    process.exit(0);
}
if (errors.length) { for (const e of errors) console.error(`racer_batch: FAIL: ${e}`); process.exit(1); }
console.log("racer_batch: OK");
