// Headless RACER, the R82 32X look (docs/ports/kestrel_racing/LOOK.md): a track's panorama file, <TRACK>.PAN
// (racer/pano.zig, panofile.zig; written by tools/racer/panc.py). Three disks are built here from the cart and Salt
// Flats, with OUR synthetic test strip (panc.py's test_strip: no 32X data): SALT.PAN good, SALT.PAN with a texel flipped
// after its CRC, and no SALT.PAN. At Salt's attract pose A:
//   1. the good file is loaded (racer,pan,SALT.PAN,256,28,6) and drawn: every pixel that differs from the no-panorama
//      view is a panorama entry where that view had the sky, the far ground or the backdrop shape (the 3D faces drawn
//      over it are untouched), the panorama shows, the CPU and AFFINE fills agree, the view is pinned;
//   2. the corrupted file is refused by name (racer,pan,refused,SALT.PAN,BadCrc) and the view is the no-panorama one
//      byte for byte (the mood's backdrop shape);
//   --break crc (key ^: the CRC not checked, so the corrupted file is drawn) must be caught.
//   node apps/harness/racer_look.mjs [<shot dir>] [--break crc] [--print-pins]
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { diskHook } from "./racer_disk.mjs";
import { bootObj, key } from "./obj_machine.mjs";
import { png } from "./skystrike_zig_frame.mjs";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
if (BREAK !== null && BREAK !== "crc") { console.error(`racer_look: unknown --break ${BREAK}`); process.exit(1); }
const PRINT = argv.includes("--print-pins");
const OUT = argv[0] && !argv[0].startsWith("--") ? argv[0] : null;
const PINS = { pan: "4fb4fc7eb950" }; // Salt pose A with the test panorama
const W = 320, H = 200, REG_FB_BASE = 0x44, OFF_PAL = 0x0100, NCOL = 6;
const SALT = "apps/zig/assets/screens/racer/salt.ktrk";
const errors = [];
const fail = (m) => errors.push(m);

function run(cmd, args) {
    const r = spawnSync(cmd, args, { encoding: "utf8" });
    if (r.status !== 0) throw new Error(`${cmd} ${args.join(" ")}: ${r.stderr}`);
    return r.stdout;
}

const dir = await mkdtemp(join(tmpdir(), "racer_look-"));
const disk = async (name, files) => {
    const out = join(dir, name);
    run("python3", ["-I", "tools/mkdisk.py", "site/carts/demo-racer.wasm", "-o", out, "--title", "racer", "--date", "20261127",
        ...files.flatMap((f) => ["--file", f])]);
    return new Uint8Array(await readFile(out));
};
run("python3", ["-I", "tools/racer/panc.py", SALT, "-o", join(dir, "good.pan")]);
run("python3", ["-I", "tools/racer/panc.py", SALT, "-o", join(dir, "bad.pan"), "--corrupt"]);
const first = Number(run("python3", ["-I", "-c", `import sys; sys.path.insert(0, "tools/racer"); import panc
print(panc.free_entries(open("${SALT}", "rb").read(), ${NCOL}))`]));
const disks = {
    good: await disk("good.zmd", [`SALT.KTR=${SALT}`, `SALT.PAN=${join(dir, "good.pan")}`]),
    bad: await disk("bad.zmd", [`SALT.KTR=${SALT}`, `SALT.PAN=${join(dir, "bad.pan")}`]),
    none: await disk("none.zmd", [`SALT.KTR=${SALT}`]),
};
await rm(dir, { recursive: true });

async function view(img, keys = []) {
    const log = [];
    const S = await bootObj("site/carts/demo-racer.wasm", (s) => log.push(s), diskHook(img));
    for (let i = 0; i < 3; i++) S.frame();
    for (const k of [...keys, "t", "A"]) { key(S, k); for (let i = 0; i < 3; i++) S.frame(); }
    for (let i = 0; i < 4; i++) S.frame();
    const shown = [0, 1].filter((p) => S.demo.isPlaneEnabled(p))[0] ?? 0;
    const vb = S.machine.hwVideoBase(), dv = new DataView(S.memory.buffer, vb, OFF_PAL);
    const px = new Uint8Array(S.memory.buffer, vb + dv.getUint32(REG_FB_BASE + 4 * shown, true), W * H).slice();
    const pal = new Uint32Array(S.memory.buffer, vb + OFF_PAL, 256).slice();
    return { px, pal, log: log.filter((l) => l.startsWith("racer,pan,")) };
}
const Y0 = 12, Y1 = 188; // the 3D view (the HUD bands above and below name the fill path)
const hash = (px) => createHash("sha256").update(px.subarray(Y0 * W, Y1 * W)).digest("hex").slice(0, 12);
const pre = BREAK === "crc" ? ["^"] : [];

const none = await view(disks.none);
const good = await view(disks.good, pre);
const goodAff = await view(disks.good, [...pre, "f"]);
const bad = await view(disks.bad, pre);

// 1. the good file: loaded, drawn only where the backdrop was (sky 1, far ground 4, the shape 12-14), the faces untouched
if (!good.log.includes(`racer,pan,SALT.PAN,256,28,${NCOL}`)) fail(`the good panorama: ${good.log.join(" ") || "no racer,pan line"}`);
const owns = (c) => c >= first && c < first + NCOL;
let shownPx = 0, wrong = 0;
for (let i = 0; i < W * H; i++) {
    if (owns(good.px[i])) shownPx++;
    if (good.px[i] === none.px[i]) continue;
    if (!owns(good.px[i]) || ![1, 4, 12, 13, 14].includes(none.px[i])) wrong++;
}
if (shownPx < 4000 || wrong) fail(`the panorama drawn: ${shownPx} of its pixels, ${wrong} changed outside the backdrop`);
if (hash(goodAff.px) !== hash(good.px)) fail("the panorama: CPU and AFFINE fills differ");
const pin = hash(good.px);
if (PRINT) console.log(`pan: "${pin}"`);
else if (pin !== PINS.pan) fail(`the panorama view ${pin}, pinned ${PINS.pan}`);
// 2. the corrupted file: refused by name, the mood's shape drawn
if (!bad.log.includes("racer,pan,refused,SALT.PAN,BadCrc")) fail(`the corrupted panorama: ${bad.log.join(" ") || "not refused"}`);
if (hash(bad.px) !== hash(none.px)) fail("the corrupted panorama: the view is not the no-panorama one");
if (OUT) {
    await mkdir(OUT, { recursive: true });
    for (const [n, v] of [["look_pan.png", good], ["look_nopan.png", none]]) {
        await png(`${OUT}/${n}`, Uint32Array.from(v.px, (c) => (c ? v.pal[c] : 0xff000000)), W, H);
    }
}

if (BREAK) {
    if (!errors.length) { console.error(`racer_look --break ${BREAK}: NOT caught`); process.exit(1); }
    console.log(`racer_look --break ${BREAK}: caught (${errors[0]})`);
    process.exit(0);
}
if (errors.length) { for (const e of errors) console.error(`racer_look: FAIL ${e}`); process.exit(1); }
console.log(`racer_look: PASS (SALT.PAN drawn on ${shownPx} pixels, only where the backdrop was, CPU = AFFINE, pinned ${pin}; a corrupted one refused BadCrc, the shape drawn)`);
