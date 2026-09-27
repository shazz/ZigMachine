// SKYSTRIKE level data (cart 79): the Tiled maps are the game's data, and a
// disk carrying its own MISSIONS.DAT / SCRNDATA.DAT is played in their place.
//   round trip  tools/skystrike/levels.py check: import(export(original)) is
//               byte-exact, the committed maps (apps/zig/assets/screens/
//               skystrike/levels/) import to exactly the cart's built-in files,
//               and 22 broken maps are refused with their location
//   custom disk mission 1 edited as a map (its target moved to screen 30, a
//               new briefing, screen 4 made sea in every map), imported and
//               packed on a disk (levels.py disk): the cart briefs and plays
//               THAT mission (tgtx, mission type, sc9 + 4 read back)
//   bad disk    a disk whose MISSIONS.DAT is 300 bytes stops on the error
//               trap with the reason, and stays there
//   node apps/skystrike_levels.mjs [--break disk]   (--break disk: the disk
//               served is the built-in data, so the custom check must fail)
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync, rmSync, cpSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { session, toPlay, L } from "./skystrike_session.mjs";

const LEVELS = "apps/zig/assets/screens/skystrike/levels";
const SC9 = (6 << 16) + 32033;
const broke = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
if (broke && broke !== "disk") throw new Error("--break disk");
const py = (...args) => execFileSync("python3", ["tools/skystrike/levels.py", ...args], { encoding: "utf8" });
const errors = [];

// A drive serving a .zmd, as docs/sealed-loader.js diskReadBlock does.
const drive = (zmd) => (memory) => ({
    diskReadBlock(block, dst) {
        const src = zmd.subarray(block * 512, block * 512 + 512);
        new Uint8Array(memory.buffer, dst, src.length).set(src);
        return src.length;
    },
});

function customMaps(dir) {
    cpSync(LEVELS, dir, { recursive: true });
    const m1 = path.join(dir, "mission01.json");
    const doc = JSON.parse(readFileSync(m1, "utf8"));
    doc.properties.find((p) => p.name === "briefing").value = "A CUSTOM MISSION\nfrom a Tiled map on a disk";
    doc.layers[1].objects.push({ id: 1, gid: 38, name: "target", type: "target", x: 30 * 320 + 128, y: 168,
        width: 64, height: 64, rotation: 0, visible: true });
    doc.layers[0].data[4] = 9 + 1; // screen 4: sea (type 9), never randomised
    writeFileSync(m1, JSON.stringify(doc));
    py("sync-world", m1, dir);
}

async function custom(tmp) {
    const maps = path.join(tmp, "maps");
    customMaps(maps);
    const zmd = path.join(tmp, "custom.zmd");
    py("disk", broke === "disk" ? LEVELS : maps, "--out", zmd);
    const s = await session(1234, drive(readFileSync(zmd)));
    await toPlay(s);
    const got = { tgtx: s.v("tgtx"), mission: s.v("mission"), screen4: s.val(SC9 + 4), label: s.label() };
    if (got.tgtx !== 30 || got.mission !== 2 || got.screen4 !== 9 || got.label === L.l2700b)
        errors.push(`custom disk: tgtx ${got.tgtx}, mission ${got.mission}, screen 4 type ${got.screen4} ` +
            `(want 30, 2, 9): the disk's MISSIONS.DAT / SCRNDATA.DAT were not played`);
    else console.log("  custom disk: mission 1 from the disk's maps: target screen 30, screen 4 sea");
}

async function badDisk(tmp) {
    const bad = path.join(tmp, "bad");
    py("import", LEVELS, "--out", bad);
    const dat = readFileSync(path.join(bad, "MISSIONS.DAT"));
    writeFileSync(path.join(bad, "MISSIONS.DAT"), dat.subarray(0, 300));
    const zmd = path.join(tmp, "bad.zmd");
    execFileSync("python3", ["tools/mkdisk.py", "docs/demo-skystrike.wasm", "-o", zmd, "--title", "bad",
        "--file", `MISSIONS.DAT=${path.join(bad, "MISSIONS.DAT")}`]);
    const s = await session(1234, drive(readFileSync(zmd)));
    s.vbl(50); s.press(32); s.vbl(200);
    if (s.label() !== L.l2700b) errors.push(`bad disk: a 300-byte MISSIONS.DAT ran on (label ${s.label()}, not the error trap)`);
    else console.log("  bad disk: a 300-byte MISSIONS.DAT stops on the error trap, and stays there");
}

const tmp = mkdtempSync(path.join(tmpdir(), "skylevels-"));
try {
    try { process.stdout.write("  " + py("check")); } catch (e) { errors.push(`levels.py check: ${e.stderr || e.message}`.trim()); }
    await custom(tmp);
    await badDisk(tmp);
} finally {
    rmSync(tmp, { recursive: true, force: true });
}
if (broke) {
    console.log(errors.length ? `skystrike levels: PASS (--break ${broke} caught: ${errors[0]})` : `skystrike levels: FAILED -- --break ${broke} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `skystrike levels: FAILED -- ${errors.join("; ")}` : "skystrike levels: all pass");
process.exit(errors.length ? 1 : 0);
