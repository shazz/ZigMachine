// SyncTERM's dialing directory on C: (apps/ports/syncterm/kestrel_dialdir.c). The SyncTERM cart is started from
// GEM over its data disk (apps/ports_gem.mjs) with C: = a copy of docs/gemdos-c.img, its writes served as the page
// serves them (docs/kos-cfile.js), the network MOCKED (no ZIGNIC card: the in-cart BBS answers fakebbs.zig):
//   seed      no list on C: yet: one is written, C:\SYNCTERM\SYNCTERM.LST, from the floppy's DIAL.TXT + the in-cart BBS
//   dir       SyncTERM opens on its dialing directory (no URL on its command line), pinned
//   dial      Enter on fakebbs.zig dials it: the BBS's screen is drawn (pinned), typed keys come back (pinned)
//   drop      G Enter (the BBS's Goodbye) hangs up from the BBS's end; OK: back on the directory, as it was
//   hangup    dialled again, Alt+H, Yes: back on the directory, as it was
//   add       Insert, "Local BBS", Telnet, fakebbs.zig: a third entry, pinned; Alt+X quits to GEM's desktop
//   on C:     the image holds the list (mtools): [Local BBS] at fakebbs.zig, and fakebbs.zig called twice
//   relaunch  a new machine over the same image: the directory lists the three entries (pinned); Local BBS dials
// --break SABOTAGES and passes only if caught: write (the host refuses every C: write: no list, nothing kept),
// hangup (Alt+H never pressed: the call never ends, no way back to the directory).
//   node apps/syncterm_dialdir.mjs [--break write|hangup] [--png <dir>]     (pins: print them with PINS=1)
import { readFile, writeFile, mkdir, mkdtemp, rm } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { machine, step, picture, sha, png } from "./ports_machine.mjs";
import { launchFromGem, serviceQuit } from "./ports_gem.mjs";
import { makeCDrive, makeCFile } from "./scene_hash_disk.mjs";

const CART = "docs/demo-syncterm.wasm", DISK = "docs/demo-syncterm.zmd", C_IMAGE = "docs/gemdos-c.img";
const ALT = 0xe013, INS = 0xe00b, ENTER = 13, UP = 0, DOWN = 1;
const CELLS = [0, 399], SCREEN = [0, 351], PROMPT = [352, 383]; // the 80x25 cells of 8x16; the BBS's art; its prompt rows
const PIN = { // re-bless only for a deliberate change to the cart or data/BBS.ANS
    dir: "857e1bb7d3a4fe383cf47fc6dcb00654d5176b39460b2bc9f26751a4a58b952f", // fakebbs.zig, vert.synchro.net; the settings
    bbs: "f938e38a09305fbf4f8b506d5075b5a48b6d6b0f009ede7043a5e5a7a9521578", // = syncterm_headless.mjs's PIN_SCREEN
    echo: "01f481c616421b648a4f01dc3d19a54785f8e92a304b4e15ab8f8bdfb0e1dedc", // "> ZIG", then a new prompt
    added: "8cbd1d87e11ae17fa037dcc7efdc3e8ee8d1c614245d8f51a3ca7ac9e9926cfa", // three entries, Local BBS selected
    relaunch: "42fabbad53d6629f280b73557228c9174cd9075a6181825b705c884b5b239617", // three entries, the first selected
};

const args = process.argv.slice(2);
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : ""; };
const broke = opt("--break"), pngDir = opt("--png");
if (broke && !["write", "hangup"].includes(broke)) throw new Error(`--break ${broke}: write or hangup`);

let failures = 0;
function check(name, ok, detail = "") {
    if (!ok) failures++;
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`);
}

function desk(m) { // the desk's 640x480 RGBA: hwRenderDesk's two 640x240 halves
    const W = 640, px = new Uint8Array(W * 480 * 4);
    for (const h of [0, 1]) {
        m.machine.hwRenderDesk(h);
        px.set(new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), W * 240 * 4), h * W * 240 * 4);
    }
    return { W, H: 480, px };
}
const band = (pic, [y0, y1]) => sha(pic.px.subarray(y0 * pic.W * 4, (y1 + 1) * pic.W * 4));
const keys = (what) => (d) => { for (const c of typeof what === "string" ? [...what].map((ch) => ch.charCodeAt(0)) : what) { d.key(c); d.keyUp(c); } };
const arrow = (dir) => (d) => { d.input(dir); d.inputRelease(dir); };

// Session 1 over a fresh C:, then session 2 over the image it left.
const FIRST = [
    [70, keys([ENTER])], [170, keys("ZIG")], [174, keys([ENTER])], [200, keys("G")], [204, keys([ENTER])], [240, keys([ENTER])],
    [280, keys([ENTER])], ...(broke === "hangup" ? [] : [[370, keys([ALT])], [371, keys("h")], [390, keys([ENTER])]]),
    [430, keys([INS])], [440, keys("Local BBS")], [444, keys([ENTER])], [460, arrow(UP)], [462, arrow(UP)], [470, keys([ENTER])],
    [490, keys("fakebbs.zig")], [494, keys([ENTER])], [540, keys([ALT])], [541, keys("x")],
];
const FIRST_SHOTS = { dir: 60, bbs: 160, echo: 190, dropped: 230, dir2: 270, dir3: 420, added: 530 };
const SECOND = [[70, arrow(DOWN)], [72, keys([ENTER])], [170, keys([ALT])], [171, keys("x")]];
const SECOND_SHOTS = { relaunch: 60, bbs: 160 };

async function session(img, events, shots, frames) {
    const m = await machine(await readFile(DISK));
    m.env.kosDriveRead = makeCDrive(m.memory, img);
    const serve = makeCFile(m.memory, img), answers = [];
    m.env.kosFileOp = (req) => { const r = broke === "write" ? -13 : serve(req); answers.push(r); return r; };
    const r = { m, answers, pics: {}, trap: "" };
    try {
        r.gem = await launchFromGem(m, CART);
        for (let f = 1; f <= frames; f++) {
            if (!m.backs) for (const [ef, fn] of events) if (ef === f) fn(m.demo);
            step(m);
            for (const [name, sf] of Object.entries(shots)) if (sf === f && !m.backs) r.pics[name] = desk(m);
            serviceQuit(m);
        }
        r.last = sha(picture(m).px);
    } catch (e) { r.trap = String(e) + (m.log.length ? ` (the cart's last words: ${m.log.slice(-3).join(" / ")})` : ""); }
    r.quit = m.backs === 1 && m.log.includes("syncterm: quit") && r.gem && r.last === r.gem.desk;
    return r;
}
function pinned(name, pic, rows) {
    const h = pic ? band(pic, rows) : "no picture";
    if (process.env.PINS) console.log(`  pin ${name}: "${h}",`);
    return [h === PIN[name], h === PIN[name] ? "= pin" : h];
}
function listOnC(dir) {
    try { return execFileSync("mtype", ["-i", `${dir}/c.img`, "::HD/SYNCTERM/SYNCTERM.LST"], { stdio: ["ignore", "pipe", "pipe"] }).toString(); } catch { return null; }
}
const section = (list, name) => (list ?? "").split(/\r?\n(?=\[)/).find((s) => s.startsWith(`[${name}]`)) ?? "";

console.log(`syncterm_dialdir: ${CART} + ${DISK}, C: = a copy of ${C_IMAGE}${broke ? ` (--break ${broke})` : ""}`);
const img = new Uint8Array(await readFile(C_IMAGE));
const a = await session(img, FIRST, FIRST_SHOTS, 600);
check("GEM runs BOOT.WSM, the committed cart", a.gem && a.gem.name === "BOOT.WSM" && a.gem.same, a.trap);
check("boot and frames", !a.trap, a.trap || "600 frames, no trap");
check("seed: no list on C:, one written from DIAL.TXT + the in-cart BBS", a.m.log.some((l) => /seeded \/C\/SYNCTERM\/SYNCTERM.LST with 2 entries/.test(l)) && a.answers.length > 0 && a.answers.every((x) => x >= 0),
    `${a.m.log.find((l) => l.includes("seeded")) ?? "no seed"}; ${a.answers.length} C: write(s) ${JSON.stringify(a.answers.slice(0, 6))}`);
let [ok, d] = pinned("dir", a.pics.dir, CELLS);
check("the dialing directory opens (no URL), the two entries", ok, d);
const dirHash = a.pics.dir ? band(a.pics.dir, CELLS) : "";
[ok, d] = pinned("bbs", a.pics.bbs, SCREEN);
check("Enter on fakebbs.zig dials it: the BBS's screen", ok, d);
[ok, d] = pinned("echo", a.pics.echo, PROMPT);
check("typed keys come back as the BBS's echo", ok, d);
const back = (pic) => (pic && band(pic, CELLS) === dirHash ? "the directory, as it was" : "not the directory");
check("the BBS hangs up (G): Disconnected, OK, back on the directory", a.pics.dropped && band(a.pics.dropped, CELLS) !== dirHash && back(a.pics.dir2) === "the directory, as it was", back(a.pics.dir2));
check("dialled again, Alt+H, Yes: back on the directory", back(a.pics.dir3) === "the directory, as it was", back(a.pics.dir3));
[ok, d] = pinned("added", a.pics.added, CELLS);
check("Insert: Local BBS, Telnet, fakebbs.zig: listed", ok, d);
check("Alt+X on the directory quits to GEM's desktop as it was (request 4)", a.quit, `${a.m.backs ?? 0} request 4; ${a.m.log.filter((l) => l.startsWith("syncterm")).join(" / ")}`);

const dir = await mkdtemp(`${tmpdir()}/syncterm_dialdir_`);
await writeFile(`${dir}/c.img`, img);
const list = listOnC(dir);
await rm(dir, { recursive: true, force: true });
const local = section(list, "Local BBS"), fake = section(list, "fakebbs.zig");
check("on C: (mtools): SYNCTERM.LST holds [Local BBS] at fakebbs.zig, telnet", /Address\s*=fakebbs\.zig/.test(local) && /ConnectionType\s*=Telnet/.test(local),
    list === null ? "no ::HD/SYNCTERM/SYNCTERM.LST" : `${list.length} bytes, [Local BBS] ${local ? "there" : "missing"}`);
check("on C:: fakebbs.zig's TotalCalls is 2 (the in-place update rewritten whole)", /TotalCalls\s*=2\b/.test(fake), (fake.match(/TotalCalls\s*=\S*/) ?? ["no TotalCalls"])[0]);

const b = await session(img, SECOND, SECOND_SHOTS, 230);
check("relaunch: boot and frames", !b.trap, b.trap || "230 frames, no trap");
check("relaunch: no seed (the list is on C:)", !b.m.log.some((l) => l.includes("seeded")));
[ok, d] = pinned("relaunch", b.pics.relaunch, CELLS);
check("relaunch: the directory reads the three entries back off C:", ok, d);
check("relaunch: Local BBS dials (the BBS's screen as before)", b.pics.bbs && band(b.pics.bbs, SCREEN) === PIN.bbs, b.pics.bbs ? band(b.pics.bbs, SCREEN) : "no picture");
check("relaunch: Alt+X in the call quits to GEM", b.quit);

if (pngDir) {
    await mkdir(pngDir, { recursive: true });
    for (const [s, r] of [["a", a], ["b", b]]) for (const [n, p] of Object.entries(r.pics)) await png(p, `${pngDir}/dialdir_${s}_${n}.png`);
}
if (broke) {
    console.log(failures ? `\nsyncterm_dialdir: PASS (--break ${broke} was caught)` : `\nsyncterm_dialdir: FAILED - --break ${broke} was not caught`);
    process.exit(failures ? 0 : 1);
}
console.log(failures ? `\nsyncterm_dialdir: ${failures} FAILED` : "\nsyncterm_dialdir: PASS");
process.exit(failures ? 1 : 0);
