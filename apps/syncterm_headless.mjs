// Headless gate for the SyncTERM spike (apps/ports/syncterm): the BBS terminal as a GEM program on its DATA disk,
// in the desk mode (640x480 at 1:1), its network MOCKED by an in-cart BBS (kestrel_fakebbs.c). As
// apps/ports_headless.mjs does for the other ports: GEM boots over docs/demo-syncterm.zmd, a double-click runs
// BOOT.WSM (apps/ports_gem.mjs), then:
//   desk      the program switched the machine to the desk mode (hwDeskActive) and the status line is drawn
//   bbs       SyncTERM dialled telnet://fakebbs.zig on its own (the URL on its command line), the telnet options
//             were negotiated and the BBS's ANSI screen (WELCOME.ANS off the floppy) is drawn: the desk's rows of the
//             screen and of the negotiation line are pinned, pixel for pixel
//   echo      keys typed (Z I G, Enter, O K) come back as the BBS's echo: the prompt rows change, and are pinned
//   quit      Alt+X (SyncTERM's disconnect), then Enter on "Save this directory entry?" (No): SyncTERM's main returns,
//             request 4, and GEM's desktop comes back exactly as it was
//   node apps/syncterm_headless.mjs [--break type|quit] [--png <dir>]
// --break type: the keys are never typed (the echo check must fail); quit: the quit is never asked for.
// Pins: re-bless only for a deliberate change to the cart or data/BBS.ANS (print them with PINS=1).
import { readFile, mkdir } from "node:fs/promises";
import { machine, step, picture, colours, sha, png } from "./ports_machine.mjs";
import { launchFromGem, serviceQuit } from "./ports_gem.mjs";

const CART = "docs/demo-syncterm.wasm", DISK = "docs/demo-syncterm.zmd";
const FRAMES = 200, SCREEN_AT = 90, ECHO_AT = 140, QUIT_AT = 160, AFTER_QUIT = 60;
const ALT = 0xe013, ENTER = 13;
// The desk's pixel rows: the 80x25 cells are 8x16; the BBS screen is rows 1..20, the negotiation line row 22,
// the prompts rows 23..24 (1-based); the status line under the cells is drawn at y 432.
const SCREEN_ROWS = [0, 351], PROMPT_ROWS = [352, 383], STATUS_ROWS = [432, 447];
const PIN_SCREEN = "f938e38a09305fbf4f8b506d5075b5a48b6d6b0f009ede7043a5e5a7a9521578";
const PIN_ECHO = "addc08465215b806305b94961c2496bbaaaeaba744b4d6d388989cebaec57b0f";

const args = process.argv.slice(2);
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : ""; };
const broke = opt("--break"), pngDir = opt("--png");
if (broke && !["type", "quit"].includes(broke)) throw new Error(`--break ${broke}: syncterm has type, quit`);

let failures = 0;
function check(name, ok, detail = "") {
    if (!ok) failures++;
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`);
}

// The desk's 640x480 picture (RGBA), as scene_hash reads a desk frame: hwRenderDesk's two 640x240 halves.
function desk(m) {
    const W = 640, out = new Uint8Array(W * 480 * 4);
    for (const h of [0, 1]) {
        m.machine.hwRenderDesk(h);
        out.set(new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), W * 240 * 4), h * W * 240 * 4);
    }
    return { W, H: 480, px: out };
}
const band = (pic, [y0, y1]) => pic.px.subarray(y0 * pic.W * 4, (y1 + 1) * pic.W * 4);
const lit = (b) => { let n = 0; for (let i = 0; i < b.length; i += 4) n += (b[i] | b[i + 1] | b[i + 2]) !== 0; return n; };

const events = [
    ...(broke === "type" ? [] : [[100, "ZIG"], [104, [ENTER]], [110, "OK"]]),
    ...(broke === "quit" ? [] : [[QUIT_AT, [ALT]], [QUIT_AT + 1, "x"], [QUIT_AT + 30, [ENTER]]]),
];
const press = (d, what) => { for (const c of typeof what === "string" ? [...what].map((ch) => ch.charCodeAt(0)) : what) { d.key(c); d.keyUp(c); } };

async function run() {
    const m = await machine(await readFile(DISK));
    const r = { m, shots: new Map(), trap: "", deskOn: 0 };
    try {
        r.gem = await launchFromGem(m, CART);
        for (let f = 1; f <= FRAMES + AFTER_QUIT; f++) {
            if (!m.backs) for (const [ef, what] of events) if (ef === f) press(m.demo, what);
            step(m);
            if (!m.backs && [SCREEN_AT, ECHO_AT].includes(f)) r.shots.set(f, desk(m));
            if (f === SCREEN_AT) r.deskOn = m.machine.hwDeskActive();
            serviceQuit(m);
        }
        r.last = sha(picture(m).px);
    } catch (e) { r.trap = String(e) + (m.log.length ? ` (the cart's last words: ${m.log.slice(-3).join(" / ")})` : ""); }
    return r;
}

console.log(`syncterm: ${CART} + ${DISK}${broke ? ` (--break ${broke})` : ""}`);
const r = await run();
const g = r.gem;
check("GEM boots over the data disk and runs BOOT.WSM, the committed cart",
    g && g.dataDisk && g.sector.ours && g.name === "BOOT.WSM" && g.same, g ? `${g.files.join(" ")}; ${g.name}${g.same ? " = " : " != "}${CART}` : r.trap);
check("boot and frames", !r.trap, r.trap || `${FRAMES} frames, no trap`);
check("desk mode on (HW 1.17.0)", r.deskOn === 1, `hwDeskActive ${r.deskOn} at frame ${SCREEN_AT}`);
const a = r.shots.get(SCREEN_AT), b = r.shots.get(ECHO_AT);
if (a && b) {
    const hs = sha(band(a, SCREEN_ROWS)), he = sha(band(b, PROMPT_ROWS));
    if (process.env.PINS) console.log(`  pins: PIN_SCREEN=${hs} PIN_ECHO=${he}`);
    check("status line drawn under the 80x25 screen", lit(band(a, STATUS_ROWS)) > 640 * 4, `${lit(band(a, STATUS_ROWS))} lit pixels`);
    check("BBS screen drawn (telnet negotiated, WELCOME.ANS sent)", colours(a) >= 8 && hs === PIN_SCREEN,
        `${colours(a)} colours; rows ${SCREEN_ROWS.join("..")} ${hs === PIN_SCREEN ? "= pin" : hs}`);
    check("typed keys echoed by the BBS", sha(band(a, PROMPT_ROWS)) !== he && he === PIN_ECHO,
        `prompt rows ${he === PIN_ECHO ? "= pin" : he}`);
} else check("pictures", false, "no desk picture at the checked frames");
check("Alt+X, No: SyncTERM quits to the desktop as it was (request 4)", r.m.backs === 1 && r.m.log.includes("syncterm: quit") && g && r.last === g.desk,
    `${r.m.backs ?? 0} request 4, desktop ${g && r.last === g.desk ? "as it was" : "differs"}; ${r.m.log.filter((l) => l.startsWith("syncterm")).join(" / ")}`);
if (pngDir) {
    await mkdir(pngDir, { recursive: true });
    for (const [f, p] of r.shots) await png(p, `${pngDir}/syncterm_${f}.png`);
}
if (broke) {
    console.log(failures ? `\nsyncterm: PASS (--break ${broke} was caught)` : `\nsyncterm: FAILED - --break ${broke} was not caught`);
    process.exit(failures ? 0 : 1);
}
console.log(failures ? `\nsyncterm: ${failures} FAILED` : "\nsyncterm: PASS");
process.exit(failures ? 1 : 0);
