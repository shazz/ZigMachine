// SyncTERM's downloads land on C: (R81, apps/ports/syncterm/kestrel_dialdir.c kestrel_dldir + patches/bbslist.c.sed,
// zmodem.c.sed). The cart is started from GEM over its data disk with C: = a copy of docs/gemdos-c.img (no DOWNLOAD
// folder on it), its writes served as the page serves them (docs/kos-cfile.js); the in-cart BBS (kestrel_fakebbs.c
// + kestrel_fakexfer.c) dialled from the dialing directory sends TEST.BIN (2500 bytes, with CR NUL and 255 255 in it) when
// X / Y / W / K is typed at its prompt, and the harness starts the receiver the way a user does (Alt+D, the protocol,
// the filename). What lands on C: is read back off the image with mtools:
//   xmodem    X, Alt+D, XMODEM-CRC, "XM.BIN": C:\DOWNLOAD (made by the cart) holds XM.BIN = the 2500 bytes + the ^Z padding of
//             XMODEM's last 1K block (3072 bytes); the 255 255 and CR NUL survived telnet (IAC doubling, binary mode)
//   ymodem    Y, Alt+D, YMODEM: TEST.BIN = exactly the 2500 bytes (the header block gives the length)
//   collision W (YMODEM again, other bytes, same name), Alt+D, YMODEM: "Duplicate File Name" -> Overwrite: TEST.BIN = the new bytes
//   cancel    K (XMODEM the sender drops after block 2: CAN x5), Alt+D, XMODEM-CRC, "CAN.BIN": SyncTERM keeps what it had
//             written (2048 bytes, a partial file); upstream removes only an EMPTY file of a failed transfer
//   no r+     every C: write answered >= 0 (an "r+" / append on C: is ENOTSUP, a refused write is not an answer here)
// --break SABOTAGES and passes only if caught: write (the host refuses every C: write: no file lands), skip (the
// receiver is never started: no file lands).
//   node apps/syncterm_download.mjs [--break write|skip] [--png <dir>]
import { readFile, writeFile, mkdir, mkdtemp, rm } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { machine, step, picture, png } from "./ports_machine.mjs";
import { launchFromGem, serviceQuit } from "./ports_gem.mjs";
import { makeCDrive, makeCFile } from "./scene_hash_disk.mjs";

const CART = "docs/demo-syncterm.wasm", DISK = "docs/demo-syncterm.zmd", C_IMAGE = "docs/gemdos-c.img";
const ALT = 0xe013, ENTER = 13, DOWN = 1, SIZE = 2500;
const args = process.argv.slice(2);
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : ""; };
const broke = opt("--break"), pngDir = opt("--png");
if (broke && !["write", "skip"].includes(broke)) throw new Error(`--break ${broke}: write or skip`);

let failures = 0;
function check(name, ok, detail = "") {
    if (!ok) failures++;
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`);
}

// kestrel_fakexfer.c's kestrel_xfer_byte, the file the BBS offers.
const content = (variant, n = SIZE) => Uint8Array.from({ length: n }, (_, i) =>
    i >= 300 && i < 304 ? [13, 0, 255, 255][i - 300] : (i * 167 + 13 + 41 * variant) & 255);
const padded = (b, to) => { const o = new Uint8Array(to).fill(0x1a); o.set(b); return o; };

const m = await machine(await readFile(DISK));
const img = new Uint8Array(await readFile(C_IMAGE));
m.env.kosDriveRead = makeCDrive(m.memory, img);
const serve = makeCFile(m.memory, img), answers = [];
m.env.kosFileOp = (req) => { const r = broke === "write" ? -13 : serve(req); answers.push(r); return r; };

const run = (n) => { for (let i = 0; i < n; i++) { step(m); serviceQuit(m); } };
const keys = (what) => { for (const c of typeof what === "string" ? [...what].map((ch) => ch.charCodeAt(0)) : what) { m.demo.key(c); m.demo.keyUp(c); run(1); } };
const arrow = (dir) => { m.demo.input(dir); m.demo.inputRelease(dir); run(2); };
const frames = { n: 0 };
function until(re, max, what) { // step until the cart logs a line matching re
    for (let f = 0; f < max; f++) { if (m.log.some((l) => re.test(l))) return f; run(1); frames.n++; }
    throw new Error(`${what}: no "${re}" in ${max} frames (the cart's last words: ${m.log.slice(-3).join(" / ")})`);
}
const download = (protocol, name) => { // Alt+D, the protocol's row in the menu, and XMODEM's filename
    if (broke === "skip") return;
    keys([ALT]); keys("d"); run(10);
    for (let i = 0; i < protocol; i++) arrow(DOWN);
    keys([ENTER]); run(10);
    if (name) { keys(name); keys([ENTER]); }
};
const ZMODEM = 0, YMODEM = 2, XMODEM_CRC = 3;
const dump = () => m.log.filter((l) => /^(syncterm|fakebbs)/.test(l)).join(" / ");
const snaps = {};
function transfer(tag, line, protocol, name, doneRe, extra = () => {}) {
    keys(line); keys([ENTER]); run(20);
    download(protocol, name);
    extra();
    if (broke !== "skip") until(doneRe, 6000, tag);
    run(60); keys([ENTER]); run(60);                        // the BBS is done; SyncTERM closes the file, "hit any key"
    snaps[tag] = img.slice();
}

console.log(`syncterm_download: ${CART} + ${DISK}, C: = a copy of ${C_IMAGE}${broke ? ` (--break ${broke})` : ""}`);
let trap = "";
let gem;
try {
    snaps.start = img.slice();                               // before SyncTERM lists its directory: C:\DOWNLOAD is made then
    gem = await launchFromGem(m, CART);
    run(70); keys([ENTER]);                                  // the dialing directory: Enter dials fakebbs.zig
    run(150);
    transfer("xmodem", "X", XMODEM_CRC, "XM.BIN", /fakebbs: xfer X done/);
    transfer("ymodem", "Y", YMODEM, "", /fakebbs: xfer Y done/);
    transfer("collision", "W", YMODEM, "", /fakebbs: xfer W done/, () => { run(40); keys([ENTER]); });   // Overwrite is the menu's first row
    transfer("cancel", "K", XMODEM_CRC, "CAN.BIN", /fakebbs: xfer K done/);
    if (pngDir) { await mkdir(pngDir, { recursive: true }); await png(picture(m), `${pngDir}/download_end.png`); }
} catch (e) { trap = String(e); }

const dir = await mkdtemp(`${tmpdir()}/syncterm_download_`);
const mtool = (tool, snap, ...rest) => { try { return execFileSync(tool, ["-i", `${dir}/${snap}.img`, ...rest], { stdio: ["ignore", "pipe", "pipe"] }); } catch { return null; } };
for (const [k, v] of Object.entries(snaps)) await writeFile(`${dir}/${k}.img`, v);
const ls = (snap) => (mtool("mdir", snap, "-b", "::HD/DOWNLOAD") ?? Buffer.alloc(0)).toString().split(/\r?\n/).filter(Boolean).map((l) => l.replace(/^.*\//, "")).sort();
const file = (snap, name) => { const b = mtool("mtype", snap, `::HD/DOWNLOAD/${name}`); return b ? new Uint8Array(b) : null; };
const same = (a, b) => a && b && a.length === b.length && a.every((v, i) => v === b[i]);
const firstDiff = (a, b) => !a ? "no file" : a.length !== b.length ? `${a.length} bytes, expected ${b.length}` : `differs at byte ${a.findIndex((v, i) => v !== b[i])}`;
function verify(name, snap, file_, want) {
    const got = file(snap, file_);
    check(name, same(got, want), same(got, want) ? `${want.length} bytes, equal` : firstDiff(got, want));
}

check("GEM runs BOOT.WSM, the committed cart", gem && gem.name === "BOOT.WSM" && gem.same, trap);
check("the transfers ran (no trap)", !trap, trap || `${frames.n} frames waited for the BBS`);
if (broke !== "skip") check("the image starts with no C:\\DOWNLOAD", ls("start").length === 0 && mtool("mdir", "start", "::HD/DOWNLOAD") === null, "folder absent");
verify("xmodem (X, XMODEM-CRC, 1K blocks): C:\\DOWNLOAD\\XM.BIN, ^Z-padded last block, 255 255 / CR NUL intact", "xmodem", "XM.BIN", padded(content(0), 3072));
verify("ymodem: C:\\DOWNLOAD\\TEST.BIN, exactly 2500 bytes", "ymodem", "TEST.BIN", content(0));
verify("collision (Duplicate File Name, Overwrite): TEST.BIN replaced by the new bytes", "collision", "TEST.BIN", content(1));
verify("cancel (sender CAN x5 after block 2): CAN.BIN is the 2048 bytes received, kept", "cancel", "CAN.BIN", content(0, 2048));
check("C:\\DOWNLOAD holds exactly CAN.BIN TEST.BIN XM.BIN", JSON.stringify(ls("cancel")) === JSON.stringify(["CAN.BIN", "TEST.BIN", "XM.BIN"]), ls("cancel").join(" ") || "empty");
check("every C: write answered (no refused or unsupported open)", answers.length > 0 && answers.every((x) => x >= 0),
    `${answers.length} answers, ${answers.filter((x) => x < 0).length} negative`);
if (process.env.PINS || failures) console.log(`  cart: ${dump()}`);
await rm(dir, { recursive: true, force: true });

if (broke) {
    console.log(failures ? `\nsyncterm_download: PASS (--break ${broke} was caught)` : `\nsyncterm_download: FAILED - --break ${broke} was not caught`);
    process.exit(failures ? 0 : 1);
}
console.log(failures ? `\nsyncterm_download: ${failures} FAILED` : "\nsyncterm_download: PASS");
process.exit(failures ? 1 : 0);
