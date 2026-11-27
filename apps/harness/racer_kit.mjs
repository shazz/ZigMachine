// Headless RACER, the Track Kit as a product (R82 Kestrel Racing M7, docs/ports/kestrel_racing/TRACK_KIT.md): a USER-MADE
// track, end to end, from the sample's committed Blender export (tools/racer/tracks/sample_oval.ktrk.json):
//   export -> tools/racer/trackc.py -> SAMPLE.KTR (+ panc.py's test strip on its free entries: SAMPLE.PAN) -> tools/racer/trackpack.py
//   1. --hd: the pack builder's HD/RACER/ folder as C: (a FAT image through KOS GEMDOS, env.kosDriveRead), beside the shelf
//      disk: SAMPLE then BROKEN listed after the disk's tracks, SAMPLE loaded and flown at its mood's draw distance cap (7);
//      BROKEN.KTR (the sample with its mood's draw distance 2, the CRC made good: a hand-edited file) refused at the scan
//      with the reason the pack builder's Python twin (tools/racer/twin_trk.py) gives, word for word;
//   2. --zmd: the pack builder's disk (the cart + SAMPLE.KTR + SAMPLE.PAN) as the only disk: OVAL SAMPLE listed, SAMPLE loaded
//      with its panorama drawn (racer,pan,SAMPLE.PAN).
//   node apps/harness/racer_kit.mjs [--break hd]     (--break hd: the C: image without SAMPLE.KTR, which must be caught)
import { mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import { diskHook } from "./racer_disk.mjs";
import { bootObj, key } from "./obj_machine.mjs";
import { makeCDrive } from "./scene_hash_disk.mjs";

const BREAK = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : "";
if (BREAK && BREAK !== "hd") { console.error(`racer_kit: unknown --break ${BREAK}`); process.exit(1); }
const errors = [];
const fail = (m) => errors.push(m);
const py = (args) => execFileSync("python3", ["-I", ...args], { maxBuffer: 16 << 20 });

async function run(hook, keys, frames = 40) {
    const log = [];
    const S = await bootObj("site/carts/demo-racer.wasm", (s) => log.push(s), hook);
    for (const k of keys) { key(S, k); for (let i = 0; i < frames; i++) S.frame(); }
    const csv = log.filter((l) => l.startsWith("racer,csv,")).pop();
    return { log, track: csv ? csv.split(",")[3] : null, r: csv ? Number(csv.split(",")[4]) : null, loads: log.filter((l) => l.startsWith("racer,load,")).map((l) => l.split(",")[2]) };
}
const listed = (r) => r.log.filter((l) => l.startsWith("racer,track,") && !l.includes("refused")).map((l) => l.split(",")[2]).join(" ");

const tmp = mkdtempSync(join(tmpdir(), "racer_kit-"));
try {
    const ktr = join(tmp, "in", "SAMPLE.KTR");
    mkdirSync(join(tmp, "in"));
    py(["tools/racer/trackc.py", "tools/racer/tracks/sample_oval.ktrk.json", "-o", ktr]);
    py(["tools/racer/panc.py", ktr, "-o", join(tmp, "in", "SAMPLE.PAN")]);
    py(["tools/racer/trackpack.py", ktr, "--hd", join(tmp, "sd")]);
    py(["tools/racer/trackpack.py", join(tmp, "in"), "--zmd", join(tmp, "pack.zmd"), "--title", "RACER M7 PACK"]);

    // BROKEN.KTR: the sample with its mood's draw distance cap 2 (the cart takes 0 or 3..8), its CRC recomputed
    const CIMG = `
import sys, zlib, pathlib; sys.path[:0] = ["tools", "fpga/tools"]
import sd_layout; from kos_fat_fixture import Image
from racer import twin_trk
img = Image("SD CARD", 4096); hd = sd_layout.HD
img.mkdir(hd); img.mkdir(hd + "/RACER")
for f in sorted(pathlib.Path(sys.argv[1]).iterdir()):
    if not (sys.argv[2] == "hd" and f.name == "SAMPLE.KTR"): img.write(hd + "/RACER/" + f.name, f.read_bytes())
b = bytearray(pathlib.Path(sys.argv[1], "SAMPLE.KTR").read_bytes())
at = int.from_bytes(b[100:104], "little"); b[at + 26] = 2; b[8:12] = zlib.crc32(b[128:]).to_bytes(4, "little")
try: twin_trk.check(bytes(b)); why = "accepted"
except twin_trk.Refused as e: why = e.why
img.write(hd + "/RACER/BROKEN.KTR", bytes(b))
pathlib.Path(sys.argv[3]).write_text(why)
sys.stdout.buffer.write(img.bytes())`;
    const whyFile = join(tmp, "why.txt");
    const cimg = new Uint8Array(execFileSync("python3", ["-I", "-c", CIMG, join(tmp, "sd", "HD", "RACER"), BREAK, whyFile], { maxBuffer: 16 << 20 }));
    const twin = readFileSync(whyFile, "utf8");
    const hd = await run((env) => { diskHook()(env); env.kosDriveRead = makeCDrive(env.memory, cimg); }, ["t", "t", "t", "t", "t", "l"]);
    const broken = hd.log.find((l) => l.startsWith("racer,track,refused,BROKEN,"));
    if (listed(hd) !== "OVAL CITY SALT NEON GLACIER SAMPLE BROKEN" || hd.loads.at(-1) !== "SAMPLE" || hd.track !== "SAMPLE")
        fail(`C:\\RACER\\SAMPLE.KTR (the pack builder's --hd): lists ${listed(hd)}; loads ${hd.loads}; on ${hd.track}`);
    if (hd.track === "SAMPLE" && hd.r !== 7) fail(`SAMPLE's mood caps the draw distance at 7: the flyby runs at R ${hd.r}`);
    if (!broken || broken !== `racer,track,refused,BROKEN,${twin}`) fail(`BROKEN.KTR: the cart says ${broken}, the twin ${twin}`);

    const pack = await run(diskHook(join(tmp, "pack.zmd")), ["t", "l"]);
    const pan = pack.log.find((l) => l.startsWith("racer,pan,"));
    if (listed(pack) !== "OVAL SAMPLE" || pack.track !== "SAMPLE" || !pan || !pan.startsWith("racer,pan,SAMPLE.PAN,"))
        fail(`the pack disk (--zmd): lists ${listed(pack)}; on ${pack.track}; ${pan}`);
    if (BREAK) {
        const caught = errors.some((e) => e.startsWith("C:\\RACER\\SAMPLE.KTR"));
        if (caught) console.log(`racer_kit PASS (--break ${BREAK} caught: ${errors[0]})`);
        else { console.error(`racer_kit: --break ${BREAK} was NOT caught`); process.exitCode = 1; }
    } else if (errors.length) { for (const m of errors) console.error(`racer_kit: ${m}`); process.exitCode = 1; }
    else console.log(`racer_kit: PASS (the sample export -> SAMPLE.KTR: from C:\\RACER\\ listed after the disk's and flown at R ${hd.r}; ${broken} = the twin's; the pack disk lists OVAL SAMPLE, ${pan})`);
} finally {
    rmSync(tmp, { recursive: true, force: true });
}
